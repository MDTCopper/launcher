import 'dart:math' as math;

import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:flutter/material.dart';

import 'popup_overlay.dart';

/// 下拉选项。
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

/// 下拉选择 Field：点击头部在下方展开选项菜单。
///
/// 基于 [PopupOverlay] 实现：
/// - 菜单尺寸由布局管道提供，无需 Offstage 预测量
/// - 无需手动管理 OverlayEntry
/// - 菜单从头部下方展开，超出屏幕自动翻转，带高度展开动画
class DropdownLayer<T> extends StatefulWidget {
  final List<DropdownOption<T>> options;
  final Widget? child;
  final T? initialValue;
  final String hintText;
  final void Function(T value)? onSelect;

  /// 多选模式：菜单项变为复选框，勾选不收起菜单，头部显示"已选 N 项"。
  final bool multiSelection;

  /// 多选模式的初始选中集合。
  final Set<T>? initialValues;

  /// 多选回调：勾选变化后携带当前选中集合。
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
    this.child,
    this.width = double.infinity,
    this.color,
    this.hoverColor,
    this.border,
    this.hoverBorder,
  });

  @override
  State<StatefulWidget> createState() => _DropdownLayerState<T>();
}

class _DropdownLayerState<T> extends State<DropdownLayer<T>>
    with TickerProviderStateMixin {
  final PopupOverlayController _popupController = PopupOverlayController();

  bool onHover = false;
  bool expanded = false;

  T? selectValue;
  Set<T> selectValues = {};

  bool get _multiSelection => widget.multiSelection;

  /// 头部 hover 过渡（边框 / 背景）。
  late final AnimationController selectController;

  /// 箭头旋转。
  late final AnimationController arrowController;
  late final Animation<double> turns;

  @override
  void initState() {
    super.initState();
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
              children: [...widget.options.map(_buildOption)],
            ),
          ),
        ),
      ),
    );
  }

  /// 多选菜单顶部操作栏
  Widget _buildMultiActionBar() {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Expanded(child: Divider(height: 6, color: colors.border)),
        ReboundButton(
          pressedScale: 0.9,
          borderRadius: BorderRadius.circular(4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          onTap: () {
            setState(() => selectValues = {});
            widget.onMultiSelect?.call(<T>{});
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restart_alt, size: 14, color: colors.itemSecondary),
              const SizedBox(width: 4),
              Text(
                '重置',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.itemSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOption(DropdownOption<T> item) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    // 多选：复选框样式，勾选切换但不收起菜单
    if (_multiSelection) {
      final selected = selectValues.contains(item.value);
      return ReboundButton(
        pressedScale: 1.0,
        borderRadius: BorderRadius.circular(4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onTap: () => _toggleMultiSelect(item.value),
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
              // 装饰层：边框 + 背景，hover/展开变厚变色
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
              // 内容层：布局主体，尺寸恒定
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
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withAlpha(185),
                                ),
                        ),
                      ),
                    ),
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
      // 关闭菜单的瞬间立即复位箭头与外框高亮（不等退场动画结束）
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
      // 滚动外部时与点击外部一样自动关闭
      dismissOnScrollOutside: true,
      // 锚点区域（头部）的点击不触发关闭层：
      // 头部 onTap 的 _toggle 负责切换开合——否则 pointerDown 关闭层先关、
      // 随后头部 onTap 又因 expanded==false 重新打开，变成"关闭瞬间又打开"
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
