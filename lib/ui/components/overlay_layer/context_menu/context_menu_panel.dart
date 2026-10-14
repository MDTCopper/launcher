import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_entry.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_position.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 菜单外观与节奏
///
/// [itemHeight] 为空时按平台取：桌面 32 紧凑，移动端 48 触控下限
class ContextMenuStyle {
  const ContextMenuStyle({
    this.itemHeight,
    this.minWidth = 168,
    this.maxWidth = 248,
    this.screenMargin = 8,
    this.enterDuration = const Duration(milliseconds: 140),
    this.exitDuration = const Duration(milliseconds: 110),
    this.moveDuration = const Duration(milliseconds: 180),
    this.hoverOpenDelay = const Duration(milliseconds: 400),
    this.hoverCloseDelay = const Duration(milliseconds: 240),
    this.dismissOnScrollOutside = true,
  });

  final double? itemHeight;
  final double minWidth;
  final double maxWidth;

  /// 面板与屏幕边 / 安全区之间至少留出的距离
  final double screenMargin;

  final Duration enterDuration;
  final Duration exitDuration;

  /// 换锚点（同级菜单替换）与改尺寸的动画时长
  final Duration moveDuration;

  /// 桌面悬停多久展开子菜单
  ///
  /// 取 Windows 菜单延迟 `HKCU\Control Panel\Desktop\MenuShowDelay` 的默认值
  final Duration hoverOpenDelay;

  /// 指针离开后多久收起临时子菜单，留给「移进子菜单」的时间
  final Duration hoverCloseDelay;

  /// 菜单外滚动是否自动收起整条菜单
  ///
  /// 面板自己那块的滚动由面板的滚动视图接走，不受这条影响
  final bool dismissOnScrollOutside;

  double get resolvedItemHeight =>
      itemHeight ??
      (isMobile ? AppControlHeight.item : AppControlHeight.compact);
}

/// 面板的可变状态
///
/// 控制器改它并 markNeedsBuild，面板每次重建都从里面取最新快照；
/// 一个控制器下可以同时存在多个面板，各自持有一份状态
class ContextMenuPanelState {
  ContextMenuPanelState({
    required this.entries,
    required this.anchor,
    required this.level,
    this.barrier = false,
    this.sticky = false,
  });

  /// 面板条目
  List<ContextMenuEntry> entries;

  /// 定位锚点
  ContextMenuAnchor anchor;

  /// 层级：0 是根菜单，往下依次是子菜单
  final int level;

  /// 是否铺一层全屏关闭层；只有根菜单要
  bool barrier;

  /// 子菜单是否点击常驻；false 表示悬停临时，指针移开就收
  bool sticky;

  /// 本面板是父面板里第几个条目的子菜单；根菜单为 null
  int? parentIndex;

  /// false 表示正在播退场，播完由控制器移除
  bool visible = true;

  /// 当前展开子菜单的条目下标
  int? activeIndex;
}

/// 面板与控制器之间的交互出口
class ContextMenuPanelCallbacks {
  const ContextMenuPanelCallbacks({
    required this.onEntryActivated,
    required this.onEntryHover,
    required this.onPanelHover,
    required this.onBarrierDown,
    required this.onDismiss,
    required this.onHidden,
  });

  /// 条目被点击，[itemRect] 是该条目在 overlay 中的矩形
  final void Function(int index, Rect itemRect) onEntryActivated;

  /// 指针进入 / 离开条目
  final void Function(int index, Rect itemRect, bool inside) onEntryHover;

  /// 指针进入 / 离开整个面板
  final void Function(bool inside) onPanelHover;

  /// 右键 / 中键落在关闭层上
  ///
  /// 与 [onDismiss] 分开：要等这一次派发走完再定，下层可能接着弹新菜单
  final VoidCallback onBarrierDown;

  /// 明确要收起（Esc、左键点到关闭层）
  final VoidCallback onDismiss;

  /// 退场动画播完，可以移除这个面板了
  final VoidCallback onHidden;
}

/// 一个菜单面板：铺满 overlay，自己定位、自己播入场与退场
///
/// 翻转、避让、贴边都依赖面板尺寸，所以第一帧只量不画，
/// 量到之后才摆到目标位置并开始入场
class ContextMenuPanel extends StatefulWidget {
  const ContextMenuPanel({
    super.key,
    required this.entries,
    required this.anchor,
    required this.level,
    required this.activeIndex,
    required this.visible,
    required this.barrier,
    required this.delegate,
    required this.style,
    required this.callbacks,
  });

  final List<ContextMenuEntry> entries;
  final ContextMenuAnchor anchor;
  final int level;
  final int? activeIndex;
  final bool visible;
  final bool barrier;
  final ContextMenuPositionDelegate delegate;
  final ContextMenuStyle style;
  final ContextMenuPanelCallbacks callbacks;

  @override
  State<ContextMenuPanel> createState() => _ContextMenuPanelState();
}

class _ContextMenuPanelState extends State<ContextMenuPanel>
    with TickerProviderStateMixin {
  /// 入场 / 退场进度
  late final AnimationController _enter;

  /// 换内容时的淡入进度，避免条目直接跳变
  late final AnimationController _content;
  late final CurvedAnimation _enterCurve;

  /// 换内容时淡入的起点：不让面板整个空掉，只做一次刷新的提示
  static const double _contentFadeFloor = 0.3;

  /// 入场时缩放的起点
  static const double _enterScaleFrom = 0.94;

  Size? _panelSize;
  ContextMenuPlacement? _placement;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: widget.style.enterDuration,
    );
    _content = AnimationController(
      vsync: this,
      duration: widget.style.moveDuration,
      value: 1,
    );
    _enterCurve = CurvedAnimation(
      parent: _enter,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    HardwareKeyboard.instance.addHandler(_handleEsc);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 窗口尺寸 / 安全区变了要重新定位：位置是量到尺寸时算一次就存下来的
    final size = _panelSize;
    if (size != null) _placement = _resolvePlacement(size);
  }

  @override
  void didUpdateWidget(covariant ContextMenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      // 退场中又被打开（同级菜单替换、悬停来回）：接着往下播，不从头放
      if (widget.visible) {
        _exiting = false;
        _enter.duration = widget.style.enterDuration;
        _enter.forward();
      } else {
        _playExit();
      }
    }
    if (oldWidget.entries != widget.entries && widget.visible) {
      _content.forward(from: _contentFadeFloor);
    }
    // 锚点变了但尺寸没变时布局不会再回调，位置要自己重算
    final size = _panelSize;
    if (size != null && oldWidget.anchor != widget.anchor) {
      _placement = _resolvePlacement(size);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleEsc);
    _enterCurve.dispose();
    _enter.dispose();
    _content.dispose();
    super.dispose();
  }

  void _onMeasured(Size size) {
    if (!mounted || _panelSize == size) return;
    setState(() {
      _panelSize = size;
      _placement = _resolvePlacement(size);
    });
    if (_enter.isDismissed) _enter.forward();
  }

  /// 退场：播完动画再让控制器移除自己；期间被重新打开就留在原地
  Future<void> _playExit() async {
    if (_exiting) return;
    _exiting = true;
    if (_enter.value > 0) {
      _enter.duration = widget.style.exitDuration;
      await _enter.reverse();
    } else {
      await SchedulerBinding.instance.endOfFrame;
    }
    if (!mounted || widget.visible) {
      _exiting = false;
      return;
    }
    widget.callbacks.onHidden();
  }

  ContextMenuPlacement _resolvePlacement(Size panelSize) {
    final media = MediaQuery.of(context);
    final margin = widget.style.screenMargin;
    // 键盘也算安全区：输入法弹出时菜单不该被压在下面
    final safeArea = EdgeInsets.fromLTRB(
      media.padding.left + margin,
      media.padding.top + margin,
      media.padding.right + margin,
      media.padding.bottom + margin + media.viewInsets.bottom,
    );
    return widget.delegate.place(
      anchor: widget.anchor,
      panelSize: panelSize,
      overlaySize: media.size,
      safeArea: safeArea,
      isSubmenu: widget.level > 0,
    );
  }

  /// 面板宽度上限，不超过可用宽度
  ///
  /// 窗口比 [ContextMenuStyle.minWidth] 还窄时跟着缩，否则会被顶出窗口
  double _maxPanelWidth() {
    final media = MediaQuery.of(context);
    final available =
        media.size.width -
        media.padding.horizontal -
        widget.style.screenMargin * 2;
    final cap = available < widget.style.maxWidth
        ? available
        : widget.style.maxWidth;
    return cap < 1 ? 1 : cap;
  }

  double _minPanelWidth() {
    final max = _maxPanelWidth();
    return max < widget.style.minWidth ? max : widget.style.minWidth;
  }

  double _maxPanelHeight() {
    final media = MediaQuery.of(context);
    final available =
        media.size.height -
        media.padding.vertical -
        media.viewInsets.bottom -
        widget.style.screenMargin * 2;
    return available < widget.style.resolvedItemHeight
        ? widget.style.resolvedItemHeight
        : available;
  }

  Rect _itemRectOf(BuildContext itemContext) {
    final selfBox = context.findRenderObject();
    final itemBox = itemContext.findRenderObject();
    if (selfBox is! RenderBox || itemBox is! RenderBox) return Rect.zero;
    return itemBox.localToGlobal(Offset.zero, ancestor: selfBox) & itemBox.size;
  }

  void _handleEntryHover(BuildContext itemContext, int index, bool inside) {
    widget.callbacks.onEntryHover(index, _itemRectOf(itemContext), inside);
  }

  @override
  Widget build(BuildContext context) {
    final placement = _placement;
    return Positioned.fill(
      child: Stack(
        children: [
          if (widget.barrier) Positioned.fill(child: _buildBarrier()),
          if (placement == null)
            // 测量帧：这一帧只量不画，量到尺寸才能定位
            Positioned(
              left: 0,
              top: 0,
              child: Opacity(
                opacity: 0,
                child: IgnorePointer(
                  child: _buildPanelShell(_buildMeasuredPanel()),
                ),
              ),
            )
          else
            AnimatedPositioned(
              duration: widget.style.moveDuration,
              curve: Curves.easeOutCubic,
              left: placement.offset.dx,
              top: placement.offset.dy,
              // 三层各管一件事：入场动画 → 壳（背景 / 边框 / 阴影）→ 尺寸动画 → 内容
              // 壳必须夹在中间：放进 AnimatedSize 则缩尺寸看不出过程，
              // 放到入场动画外面则外框不跟着进出
              child: _buildEntryAnimation(
                _buildPanelShell(
                  AnimatedSize(
                    duration: widget.style.moveDuration,
                    curve: Curves.easeOutCubic,
                    alignment: placement.growFrom,
                    child: _buildMeasuredPanel(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 接管 Esc 收起菜单
  ///
  /// 走全局键盘处理器而不是焦点：overlay 里的 autofocus 不生效，
  /// 条目按钮又各自带 autofocus，靠焦点树抢不到这个键
  bool _handleEsc(KeyEvent event) {
    // 正在退场的旧面板不该抢这个键，否则新菜单刚开就被旧面板收掉
    if (!widget.visible || widget.level != 0) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    widget.callbacks.onDismiss();
    return true;
  }

  /// 关闭层：左键吞掉（免得误触下层按钮），右键与滚动透传
  ///
  /// 右键透传是为了让右键落在下层的另一个触发区时，那里能接着弹出新菜单
  Widget _buildBarrier() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (_) => widget.callbacks.onDismiss(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if ((event.buttons & kPrimaryButton) != 0) return;
          widget.callbacks.onBarrierDown();
        },
        // 菜单外滚动就收：面板自己那块里的滚动由面板的滚动视图接走，不会落到这里
        onPointerSignal: widget.style.dismissOnScrollOutside
            ? (event) {
                if (event is PointerScrollEvent) widget.callbacks.onDismiss();
              }
            : null,
        child: const SizedBox.expand(),
      ),
    );
  }

  /// 面板的壳：背景 / 圆角 / 描边 / 投影
  ///
  /// 单独一层是为了套在 [AnimatedSize] 外面，改尺寸时壳才跟着动画走
  Widget _buildPanelShell(Widget child) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: AppRadius.panelShape,
        border: Border.all(
          color: colors.border,
          width: AppBorderWidth.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPanelBody() {
    return MouseRegion(
      onEnter: (_) => widget.callbacks.onPanelHover(true),
      onExit: (_) => widget.callbacks.onPanelHover(false),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: _minPanelWidth(),
          maxWidth: _maxPanelWidth(),
        ),
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.tight),
            // 图标尺寸统一在这一层给，条目里只按状态改颜色
            child: IconTheme(
              data: const IconThemeData(size: AppIconSize.inline),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _maxPanelHeight()),
                child: SingleChildScrollView(
                  // 换内容（同级菜单替换）时淡入，位置与尺寸交给外面的布局动画
                  child: FadeTransition(
                    opacity: _content,
                    child: _buildEntries(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 量尺寸的那一层：只量内容，量到的是内容的自然尺寸
  Widget _buildMeasuredPanel() {
    return _MeasureSize(onMeasured: _onMeasured, child: _buildPanelBody());
  }

  /// 入场 / 退场的缩放 + 淡出 + 向锚点滑入，三种效果合在一个动画里
  Widget _buildEntryAnimation(Widget child) {
    final placement = _placement;
    final slideFrom = placement?.slideFrom ?? Offset.zero;
    final growFrom = placement?.growFrom ?? Alignment.topLeft;
    final scale = Tween<double>(
      begin: _enterScaleFrom,
      end: 1,
    ).animate(_enterCurve);
    return AnimatedBuilder(
      animation: _enterCurve,
      child: child,
      builder: (context, child) {
        final progress = _enterCurve.value;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: slideFrom * (1 - progress),
            child: Transform.scale(
              scale: scale.value,
              alignment: growFrom,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntries() {
    final children = <Widget>[];
    for (var index = 0; index < widget.entries.length; index++) {
      final entry = widget.entries[index];
      children.add(switch (entry) {
        ContextMenuDivider() => const _EntryDivider(),
        ContextMenuHeader(:final label) => _EntryHeader(label: label),
        ContextMenuAction() => _buildActionTile(entry, index),
        ContextMenuSubmenu() => _buildSubmenuTile(entry, index),
      });
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildActionTile(ContextMenuAction entry, int index) {
    return _EntryTile(
      label: entry.label,
      icon: entry.icon,
      danger: entry.danger,
      enabled: entry.isEnabled,
      trailing: entry.checked ? Icons.check : null,
      accentTrailing: entry.checked,
      height: widget.style.resolvedItemHeight,
      onTap: (itemContext) =>
          widget.callbacks.onEntryActivated(index, _itemRectOf(itemContext)),
      onHover: (itemContext, inside) =>
          _handleEntryHover(itemContext, index, inside),
    );
  }

  Widget _buildSubmenuTile(ContextMenuSubmenu entry, int index) {
    return _EntryTile(
      label: entry.label,
      icon: entry.icon,
      enabled: entry.enabled,
      trailing: Icons.chevron_right,
      active: widget.activeIndex == index,
      height: widget.style.resolvedItemHeight,
      onTap: (itemContext) =>
          widget.callbacks.onEntryActivated(index, _itemRectOf(itemContext)),
      onHover: (itemContext, inside) =>
          _handleEntryHover(itemContext, index, inside),
    );
  }
}

/// 一个条目行：图标 + 文本 + 行尾标记
///
/// [onTap] / [onHover] 都带自己的 context 出去：子菜单要按这个条目的
/// 实际矩形定位，而矩形只有布局完成后才拿得到
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.label,
    required this.height,
    this.icon,
    this.trailing,
    this.danger = false,
    this.enabled = true,
    this.active = false,
    this.accentTrailing = false,
    this.onTap,
    this.onHover,
  });

  final String label;
  final double height;
  final IconData? icon;
  final IconData? trailing;
  final bool danger;
  final bool enabled;
  final bool active;

  /// 行尾标记是否用主题色（打勾那种「已选中」用它，方向箭头不用）
  final bool accentTrailing;
  final void Function(BuildContext itemContext)? onTap;
  final void Function(BuildContext itemContext, bool inside)? onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final foreground = !enabled
        ? colors.itemHint
        : danger
        ? colors.error
        : colors.itemSecondary;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => onHover?.call(context, true),
      onExit: (_) => onHover?.call(context, false),
      child: SizedBox(
        height: height,
        child: ReboundButton(
          onTap: enabled ? () => onTap?.call(context) : null,
          pressedScale: 0.98,
          hoverElevation: 0,
          borderRadius: AppRadius.itemShape,
          backgroundColor: active
              ? colors.highBackgroundOnCard
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.related),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    // 尺寸由面板那层的 IconTheme 给，这里只改颜色
                    IconTheme(
                      data: IconTheme.of(context).copyWith(color: foreground),
                      child: Icon(icon),
                    ),
                    const SizedBox(width: AppSpacing.related),
                  ],
                  // 文字要可收缩：窄窗口放不下时靠它 ellipsis，否则整行会撑破
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    const SizedBox(
                      width: AppIconSize.inline + AppSpacing.tight,
                    ),
                ],
              ),
              if (trailing != null)
                Positioned(
                  right: 0,
                  child: Icon(
                    trailing,
                    color: accentTrailing
                        ? colors.interactive
                        : colors.itemHint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryDivider extends StatelessWidget {
  const _EntryDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.tight),
      child: SizedBox(
        height: AppBorderWidth.hairline,
        child: ColoredBox(color: AppColors.of(context).border),
      ),
    );
  }
}

class _EntryHeader extends StatelessWidget {
  const _EntryHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.related,
        AppSpacing.related,
        AppSpacing.related,
        AppSpacing.tight,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colors.itemSecondary,
        ),
      ),
    );
  }
}

/// 布局完成后回报自身尺寸
///
/// 挂在 AnimatedSize 内侧，量到的是内容的自然尺寸而不是动画中的中间值
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onMeasured, required super.child});

  final ValueChanged<Size> onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onMeasured);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) {
    renderObject.onMeasured = onMeasured;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onMeasured);

  ValueChanged<Size> onMeasured;

  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (_reported == measured) return;
    _reported = measured;
    // 布局阶段不能 setState，推迟到帧末
    SchedulerBinding.instance.addPostFrameCallback((_) => onMeasured(measured));
  }
}
