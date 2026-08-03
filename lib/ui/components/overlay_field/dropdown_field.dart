import 'dart:math' as math;

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/widget/feature_button.dart';
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
class DropdownField<T> extends StatefulWidget {
  final List<DropdownOption<T>> options;
  final Widget? child;
  final T? initialValue;
  final String hintText;
  final void Function(T value)? onSelect;
  final double width;
  final double menuHeight;
  final Color? color;
  final Color? hoverColor;
  final Border? border;
  final Border? hoverBorder;

  const DropdownField({
    super.key,
    this.initialValue,
    required this.options,
    this.hintText = 'null',
    this.onSelect,
    this.menuHeight = 200,
    this.child,
    this.width = double.infinity,
    this.color,
    this.hoverColor,
    this.border,
    this.hoverBorder,
  });

  @override
  State<StatefulWidget> createState() => _DropdownFieldState<T>();
}

class _DropdownFieldState<T> extends State<DropdownField<T>>
    with TickerProviderStateMixin {
  final PopupOverlayController _popupController = PopupOverlayController();

  bool onHover = false;
  bool expanded = false;

  T? selectValue;

  /// 头部 hover 过渡（边框 / 背景）。
  late final AnimationController selectController;

  /// 箭头旋转。
  late final AnimationController arrowController;
  late final Animation<double> turns;

  @override
  void initState() {
    super.initState();
    selectValue = widget.initialValue;

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
  void didUpdateWidget(covariant DropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      selectValue = widget.initialValue;
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

  void _select(T value) {
    selectValue = value;
    _closeMenu();
    widget.onSelect?.call(value);
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
    // 菜单与头部（锚点）同宽
    final width = anchorWidth;

    // 需要 Material ancestor 才能正常渲染 InkWell 的高亮 / 水波纹
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
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            children: widget.options.map(_buildOption).toList(),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildOption(DropdownOption<T> item) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final selected = item.value == selectValue;

    // 使用自带 Material + InkWell 的 ReboundButton，
    // 不依赖浮层外部的 Material 环境
    return ReboundButton(
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
                color: selected ? colors.interactive : colors.textPrimary,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 菜单动画：淡入 + 从头部方向展开高度。
  Widget _dropdownAnimation(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    PopupOverlayPlacement? placement,
  ) {
    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1.0,
        child: child,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  String get label {
    if (selectValue == null) return widget.hintText;
    final DropdownOption<T> o = widget.options.firstWhere(
      (o) => selectValue == o.value,
      orElse: () => DropdownOption<T>(
        value: selectValue as T,
        label: widget.hintText,
      ),
    );
    return o.label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        child: AnimatedBuilder(
          animation: selectController,
          builder: (context, child) {
            final Animation<Border?> border = BorderTween(
              begin:
                  widget.border ??
                  Border.all(
                    color: colorScheme.onSurface,
                    width: 0.9,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
              end:
                  widget.hoverBorder ??
                  Border.all(
                    color: colorScheme.secondary,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
            ).animate(selectController);

            final Animation<Color?> backgroundColor = ColorTween(
              begin: widget.color ?? colorScheme.secondary.withAlpha(0),
              end: widget.hoverColor ?? colorScheme.secondary.withAlpha(30),
            ).animate(selectController);

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              width: widget.width,
              decoration: BoxDecoration(
                border: border.value,
                borderRadius: BorderRadius.circular(4),
                color: backgroundColor.value,
              ),
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
                          children: [
                            ?oldChild,
                            ...children,
                          ],
                        );
                      },
                      child: Text(
                        label,
                        key: ValueKey(label),
                        style:
                            selectValue != null
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
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    return PopupOverlay(
      controller: _popupController,
      animation: _dropdownAnimation,
      positionDelegate: const _DropdownPositionDelegate(gap: 4),
      animationDuration: const Duration(milliseconds: 200),
      onClose: () {
        // 点击外部 / Esc 关闭时同步状态
        if (mounted && expanded) {
          expanded = false;
          arrowController.reverse();
          _hoverChange();
          setState(() {});
        }
      },
      overlayChildBuilder: (context, anchorRect) => _buildMenu(context, anchorRect.width),
      child: head,
    );
  }
}

/// 下拉定位策略：菜单固定在锚点左缘正下方展开，放不下时翻转到上方。
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

    // 垂直翻转：下方放不下则展开到上方
    if (top + childSize.height > overlaySize.height - padding.bottom) {
      top = anchorRect.top - childSize.height - gap;
    }
    // 水平收拢：菜单比锚点宽时限制在屏幕内
    if (left + childSize.width > overlaySize.width - padding.right) {
      left = overlaySize.width - padding.right - childSize.width;
    }

    left = left
        .clamp(
          padding.left,
          math.max(padding.left, overlaySize.width - padding.right - childSize.width),
        )
        .toDouble();
    top = top
        .clamp(
          padding.top,
          math.max(padding.top, overlaySize.height - padding.bottom - childSize.height),
        )
        .toDouble();

    return Offset(left, top);
  }

  @override
  bool shouldReposition(PopupOverlayPositionDelegate oldDelegate) =>
      oldDelegate is! _DropdownPositionDelegate || oldDelegate.gap != gap;
}
