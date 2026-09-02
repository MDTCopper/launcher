import 'dart:math' as math;

import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/util/animation/animated_opacity_size.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'popup_overlay.dart';

/// 下拉选项
class DropdownOption<T> {
  final T value;
  final Widget? leading;
  final String label;
  final Widget? labelWidget;
  final VoidCallback? onTap;
  final T? selectValue;

  const DropdownOption({
    required this.value,
    required this.label,
    this.leading,
    this.onTap,
    this.selectValue,
    this.labelWidget,
  });
}

/// 菜单顶部自定义区构建器（[DropdownLayer.topWidget]）
///
/// [controller] 提供选中集合与全选 / 重置能力，供场景自建“全选 / 重置”等工具栏
typedef DropdownTopWidgetBuilder<T> =
    Widget Function(BuildContext context, DropdownController<T> controller);

/// 头部展示文本构建器（[DropdownLayer.textBuilder]）
///
/// 返回自定义展示文本；返回 `null` 时回落内置 [DropdownLayer] 默认逻辑
/// （多选“已选 N 项” / 单选所选 label）。接收 [controller] 以读取选中集合
typedef DropdownTextBuilder<T> =
    String? Function(DropdownController<T> controller);

/// 下拉框菜单控制器：供菜单顶部自定义区（[DropdownLayer.topWidget]）使用
///
/// 场景可按需自建“全选 / 重置”等工具栏；状态变化触发重建时读取到的值始终最新
class DropdownController<T> {
  _DropdownLayerState<T>? _state;

  void _attach(_DropdownLayerState<T> state) => _state = state;
  void _detach() => _state = null;

  /// 当前是否已全选（空选项列表视为未全选）
  bool get isAllSelected {
    final state = _state;
    if (state == null) return false;
    return state.widget.options.isNotEmpty &&
        state.selectValues.length == state.widget.options.length;
  }

  /// 全选：选中全部选项
  void selectAll() => _state?._selectAll();

  /// 重置：清空全部选项
  void reset() => _state?._resetAll();

  /// 当前选中集合
  Set<T> get selectValues => Set.of(_state?.selectValues ?? <T>{});
  List<DropdownOption<T>> get options => _state?.widget.options ?? [];
}

/// 下拉选择 Field：点击头部在下方展开选项菜单
///
/// 基于 [PopupOverlay] 实现：
/// - 菜单尺寸由布局管道提供
/// - 无需手动管理 OverlayEntry
/// - 菜单从头部下方展开，超出屏幕自动翻转
class DropdownLayer<T> extends StatefulWidget {
  final List<DropdownOption<T>> options;

  final T? initialValue;
  final String hintText;
  final void Function(T value)? onSelect;

  /// 头部自定义区：显示在内置头部内容与下拉图标之间（下拉图标左侧）
  final Widget? headExtra;

  /// 菜单顶部自定义区：显示在菜单内容最上方
  ///
  /// 接收 [DropdownController]，场景可按需自建“全选 / 重置”等工具栏
  final DropdownTopWidgetBuilder<T>? topWidget;

  /// 头部展示文本自定义构建器。
  ///
  /// 返回非 null 时覆盖默认展示文本；返回 null 回落内置逻辑
  /// （多选“已选 N 项” / 单选所选 label / 未选显示 hintText）。
  final DropdownTextBuilder<T>? textBuilder;

  /// 多选模式：菜单项变为复选框，勾选不收起菜单，头部显示"已选 N 项"
  final bool multiSelection;

  /// 多选模式的初始选中集合
  final Set<T>? initialValues;

  /// 多选回调：勾选变化后携带当前选中集合
  final ValueChanged<Set<T>>? onMultiSelect;

  final double width;
  final double menuHeight;
  final Color? color;
  final Color? hoverColor;
  final Border? border;
  final Border? hoverBorder;

  const DropdownLayer({
    super.key,
    this.initialValue,
    required this.options,
    this.hintText = 'null',
    this.onSelect,
    this.multiSelection = false,
    this.initialValues,
    this.onMultiSelect,
    this.menuHeight = 200,
    this.headExtra,
    this.topWidget,
    this.textBuilder,
    this.width = double.infinity,
    this.color,
    this.hoverColor,
    this.border,
    this.hoverBorder,
  });

  /// 多选下拉独立构造器
  ///
  /// 单选用默认构造器，多选用本构造器，各参数含义与默认构造器一致
  factory DropdownLayer.multiSelect({
    Key? key,
    required List<DropdownOption<T>> options,
    required Set<T> initialValues,
    required ValueChanged<Set<T>> onMultiSelect,
    String hintText = '不限',
    double width = double.infinity,
    double menuHeight = 200,
    Widget? headExtra,
    DropdownTopWidgetBuilder<T>? topWidget,
    DropdownTextBuilder<T>? textBuilder,
    Color? color,
    Color? hoverColor,
    Border? border,
    Border? hoverBorder,
  }) {
    return DropdownLayer<T>(
      key: key,
      options: options,
      initialValues: initialValues,
      onMultiSelect: onMultiSelect,
      hintText: hintText,
      width: width,
      menuHeight: menuHeight,
      headExtra: headExtra,
      topWidget: topWidget,
      textBuilder: textBuilder,
      color: color,
      hoverColor: hoverColor,
      border: border,
      hoverBorder: hoverBorder,
      multiSelection: true,
    );
  }

  /// 头部展示「所有已选项 label」（用「、」拼接）的 [textBuilder]。
  ///
  /// 经 controller 读取选项与选中集合，头部直接列出已选 label
  /// （如“苹果、香蕉”），空选返回 null 回落默认（[hintText]）。适用于多选。
  ///
  /// 用法：`DropdownLayer.multiSelect(textBuilder: DropdownLayer.allLabelsText(), ...)`
  static DropdownTextBuilder allLabelsText() => (controller) {
    final options = controller.options;
    final labels = options
        .where((option) => controller.selectValues.contains(option.value))
        .map((option) => option.label)
        .toList();
    return labels.isEmpty ? null : labels.join('、');
  };

  static DropdownTopWidgetBuilder allSelectOrClearTopWidget() =>
      (_, controller) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacitySize(
            child: controller.selectValues.isNotEmpty
                ? IconTextButton(
                    padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    icon: Symbols.remove_selection_rounded,
                    content: '清空',
                    onTap: () => controller.reset(),
                  )
                : null,
          ),

          Expanded(child: SizedBox()),

          AnimatedOpacitySize(
            child: !controller.isAllSelected
                ? IconTextButton(
                    padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    icon: Icons.select_all,
                    content: '全选',
                    onTap: () => controller.selectAll(),
                  )
                : null,
          ),
        ],
      );

  @override
  State<StatefulWidget> createState() => _DropdownLayerState<T>();
}

class _DropdownLayerState<T> extends State<DropdownLayer<T>>
    with TickerProviderStateMixin {
  final PopupOverlayController _popupController = PopupOverlayController();

  /// 供菜单顶部自定义区使用的控制器
  final DropdownController<T> controller = DropdownController<T>();

  bool onHover = false;
  bool expanded = false;

  T? selectValue;
  Set<T> selectValues = {};

  bool get _multiSelection => widget.multiSelection;

  /// 头部 hover 过渡
  late final AnimationController selectController;

  /// 箭头旋转
  late final AnimationController arrowController;
  late final Animation<double> turns;

  @override
  void initState() {
    super.initState();
    controller._attach(this);
    selectValue = widget.initialValue;
    selectValues = {...?widget.initialValues};

    selectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    turns = Tween(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(
        parent: arrowController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant DropdownLayer<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      selectValue = widget.initialValue;
    }
    if (oldWidget.initialValues != widget.initialValues) {
      selectValues = {...?widget.initialValues};
    }
  }

  @override
  void dispose() {
    controller._detach();
    selectController.dispose();
    arrowController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 交互
  // ------------------------------------------------------------------

  void _toggle() {
    if (expanded) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    expanded = true;
    arrowController.forward();
    _hoverChange();
    setState(() {});
    // 菜单由专用定位策略固定在头部下方展开
    _popupController.open();
  }

  void _closeMenu() {
    expanded = false;
    arrowController.reverse();
    _hoverChange();
    setState(() {});
    _popupController.dismiss();
  }

  void _onDismissStart() {
    if (!mounted || !expanded) return;
    expanded = false;
    arrowController.reverse();
    _hoverChange();
    setState(() {});
  }

  void _select(T value) {
    selectValue = value;
    _closeMenu();
    widget.onSelect?.call(value);
  }

  /// 多选切换：勾选/取消不收起菜单，变化后回调当前集合
  void _toggleMultiSelect(T value) {
    setState(() {
      if (selectValues.contains(value)) {
        selectValues.remove(value);
      } else {
        selectValues.add(value);
      }
    });
    widget.onMultiSelect?.call(Set.of(selectValues));
  }

  /// 多选全选
  void _selectAll() {
    setState(() {
      selectValues = {...widget.options.map((option) => option.value)};
    });
    widget.onMultiSelect?.call(Set.of(selectValues));
  }

  /// 多选重置
  void _resetAll() {
    setState(() => selectValues = {});
    widget.onMultiSelect?.call(<T>{});
  }

  void _hoverChange() {
    if (onHover || expanded) {
      selectController.forward();
    } else {
      selectController.reverse();
    }
  }

  // ------------------------------------------------------------------
  // 菜单
  // ------------------------------------------------------------------

  Widget _buildMenu(BuildContext context, double anchorWidth) {
    final colors = AppColors.of(context);

    final width = anchorWidth;
    // 菜单顶部自定义区：显示在菜单内容最上方
    final topWidget = widget.topWidget?.call(context, controller);

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.menuHeight),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.contentBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CopperSingleChildScrollView(
            fadeMask: false,
            child: Column(
              spacing: 2,
              children: [
                // 菜单顶部自定义区（场景按需提供，如 全选 / 重置 工具栏）
                ?topWidget,
                ...widget.options.map(_buildOption),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(DropdownOption<T> item) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    // 多选：复选框样式，勾选切换但不收起菜单；
    // 用 ActionButton 承载选中态（背景 / 前景 / 加粗）动画切换
    if (_multiSelection) {
      return ActionButton(
        icon: item.leading,
        content: Expanded(child: Text(item.label)),
        selected: selectValues.contains(item.value),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: colors.cardBackground,
        onTap: () => _toggleMultiSelect(item.value),
      );
    }

    final selected = item.value == selectValue;
    return ReboundButton(
      pressedScale: 1.0,
      borderRadius: BorderRadius.circular(4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: () {
        item.onTap?.call();
        _select(item.value);
      },
      backgroundColor: selected ? colors.interactive.withAlpha(30) : null,
      child: Row(
        children: [
          ?item.leading,
          if (item.leading != null) const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? colors.interactive : colors.itemPrimary,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 菜单动画：淡入 + 从锚点方向生长
  ///
  /// 生长方向跟随菜单实际方位（由 [PopupOverlayPlacement] 提供）：
  /// - 菜单在锚点下方 → 从菜单顶边（贴锚点）向下生长
  /// - 菜单在锚点上方 → 从菜单底边（贴锚点）向上生长（从下往上）
  /// - 沉底（上下都不够）→ 从锚点所在高度向外生长（锚点 = 触发组件位置）
  ///
  /// 用 [Transform.scale]（绘制层变换，不改布局尺寸）替代 SizeTransition /
  /// Align(heightFactor)：布局尺寸始终是菜单完整尺寸 → 浮层定位稳定，
  /// 不会出现动画结束偏移、收纳时偏移回去；也无 ClipRect 裁剪阴影问题。
  Widget _dropdownAnimation(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    PopupOverlayPlacement? placement,
  ) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        // 监听动画每帧重建 Transform（不改变布局尺寸，定位稳定）
        animation: animation,
        builder: (context, child) => Transform.scale(
          scaleY: animation.value,
          alignment: _growthAlignment(placement),
          child: child,
        ),
        child: child,
      ),
    );
  }

  /// 计算生长锚点：根据菜单与锚点的实际位置关系决定生长方向。
  Alignment _growthAlignment(PopupOverlayPlacement? placement) {
    if (placement == null) return Alignment.topCenter;
    final menuTop = placement.position.dy;
    final menuBottom = menuTop + placement.childSize.height;
    final anchorBottom = placement.anchorRect.bottom;
    // 菜单在锚点下方：贴锚点的是菜单顶边 → 从顶边向下生长
    if (anchorBottom <= menuTop) return Alignment.topCenter;
    // 菜单在锚点上方：贴锚点的是菜单底边 → 从底边向上生长（从下往上）
    if (anchorBottom >= menuBottom) return Alignment.bottomCenter;
    // 沉底（锚点在菜单范围内）：从锚点所在高度向外生长
    final ratio = ((anchorBottom - menuTop) / placement.childSize.height).clamp(
      0.0,
      1.0,
    );
    return Alignment(0, ratio * 2 - 1);
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  String get label {
    // 自定义文本构建器：返回非 null 则覆盖默认展示
    final custom = widget.textBuilder?.call(controller);
    if (custom != null) return custom;

    // 多选：空集 = 不限；否则显示已选数量
    if (_multiSelection) {
      if (selectValues.isEmpty) return widget.hintText;
      return '已选 ${selectValues.length} 项';
    }
    if (selectValue == null) return widget.hintText;
    final DropdownOption<T> o = widget.options.firstWhere(
      (o) => selectValue == o.value,
      orElse: () =>
          DropdownOption<T>(value: selectValue as T, label: widget.hintText),
    );
    return o.label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final head = MouseRegion(
      onExit: (_) {
        setState(() {
          onHover = false;
          _hoverChange();
        });
      },
      onEnter: (_) {
        setState(() {
          onHover = true;
          _hoverChange();
        });
      },
      child: GestureDetector(
        onTap: _toggle,

        child: SizedBox(
          width: widget.width,
          child: Stack(
            children: [
              // 装饰层
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: expanded
                          ? colors.contentBorderFocus
                          : onHover
                          ? colors.contentBorderHover
                          : colors.contentBorder,
                      width: expanded || onHover ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    color: expanded
                        ? colors.contentBackgroundFocus
                        : Colors.transparent,
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        switchInCurve: const Interval(0.5, 1.0),
                        switchOutCurve: const Interval(0.5, 1.0),
                        duration: const Duration(milliseconds: 300),
                        layoutBuilder: (oldChild, children) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: [?oldChild, ...children],
                          );
                        },
                        child: Text(
                          label,
                          key: ValueKey(label),
                          style: selectValue != null
                              ? TextStyle()
                              : theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                        ),
                      ),
                    ),
                    // 头部自定义区：位于下拉图标左侧
                    if (widget.headExtra case final headExtra?) ...[
                      const SizedBox(width: 8),
                      headExtra,
                    ],
                    RotationTransition(
                      turns: turns,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: colors.itemPrimary,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return PopupOverlay(
      controller: _popupController,
      animation: _dropdownAnimation,
      positionDelegate: const _DropdownPositionDelegate(gap: 4),
      animationDuration: const Duration(milliseconds: 200),
      // 关闭菜单的瞬间立即复位箭头与外框高亮
      onDismissStart: _onDismissStart,
      onClose: () {
        // 点击外部 / Esc 关闭时同步状态
        if (mounted && expanded) {
          expanded = false;
          arrowController.reverse();
          _hoverChange();
          setState(() {});
        }
      },

      dismissOnScrollOutside: true,

      dismissOnAnchorTap: false,
      overlayChildBuilder: (context, anchorRect) =>
          _buildMenu(context, anchorRect.width),
      child: head,
    );
  }
}

/// 下拉定位策略：
/// 1. 优先显示在锚点下方
/// 2. 下方没空间 → 显示在锚点上方
/// 3. 上下都不够（菜单比屏幕高）→ 沉底（菜单底边贴屏幕底部）
class _DropdownPositionDelegate extends PopupOverlayPositionDelegate {
  final double gap;

  const _DropdownPositionDelegate({required this.gap});

  @override
  Offset getPosition({
    required Rect anchorRect,
    required Offset? position,
    required Size overlaySize,
    required Size childSize,
    required EdgeInsets padding,
  }) {
    var left = anchorRect.left;
    var top = anchorRect.bottom + gap;

    // 1. 优先下方
    if (top + childSize.height > overlaySize.height - padding.bottom) {
      // 2. 下方放不下 → 上方
      top = anchorRect.top - childSize.height - gap;
      // 3. 上方也放不下（菜单比屏幕高）→ 沉底
      if (top < padding.top) {
        top = overlaySize.height - padding.bottom - childSize.height;
      }
    }
    // 水平收拢：菜单比锚点宽时限制在屏幕内
    if (left + childSize.width > overlaySize.width - padding.right) {
      left = overlaySize.width - padding.right - childSize.width;
    }

    left = left
        .clamp(
          padding.left,
          math.max(
            padding.left,
            overlaySize.width - padding.right - childSize.width,
          ),
        )
        .toDouble();
    top = top
        .clamp(
          padding.top,
          math.max(
            padding.top,
            overlaySize.height - padding.bottom - childSize.height,
          ),
        )
        .toDouble();

    return Offset(left, top);
  }

  @override
  bool shouldReposition(PopupOverlayPositionDelegate oldDelegate) =>
      oldDelegate is! _DropdownPositionDelegate || oldDelegate.gap != gap;
}
