import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 可点击表面的统一反馈：**只变色、不变形**
///
/// 为什么不用 `ReboundContainer` 的缩放：整块缩小时，行内分隔线会跟着缩、
/// 行外分隔线会露缝，密集列表 / 表格 / 菜单也无法稳定排版。密集场景统一走
/// 这里的颜色反馈（悬停 +6~8%、按下 +10~14%、选中用强调色淡底），
/// 只有独立的主行动按钮才保留轻微回弹。
///
/// 状态优先级：禁用 > 按下 > 选中 > 悬停 > 常态
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongTap,
    this.onSecondaryTap,
    this.enabled = true,
    this.selected = false,
    this.borderRadius,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.hoverColor,
    this.pressedColor,
    this.selectedColor,
    this.duration = const Duration(milliseconds: 90),
    this.clipBehavior = Clip.none,
  });

  final Widget child;

  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final VoidCallback? onSecondaryTap;

  final bool enabled;
  final bool selected;

  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  final Color? backgroundColor;
  final Color? hoverColor;
  final Color? pressedColor;
  final Color? selectedColor;

  /// 变色过渡时长
  final Duration duration;

  final Clip clipBehavior;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = widget.enabled;
    final active =
        enabled && (widget.onTap != null || widget.onLongTap != null);

    final Color color;
    if (!enabled) {
      color = widget.backgroundColor ?? Colors.transparent;
    } else if (_pressed) {
      color = widget.pressedColor ?? colors.splash;
    } else if (widget.selected) {
      color = widget.selectedColor ?? colors.indicatorBackground;
    } else if (_hovered) {
      color = widget.hoverColor ?? colors.highBackgroundOnCard;
    } else {
      color = widget.backgroundColor ?? Colors.transparent;
    }

    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: active ? (_) => setState(() => _hovered = true) : null,
      onExit: active ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? widget.onTap : null,
        onLongPress: active ? widget.onLongTap : null,
        onSecondaryTap: active ? widget.onSecondaryTap : null,
        onTapDown: active ? (_) => setState(() => _pressed = true) : null,
        onTapUp: active ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: active ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: widget.duration,
          curve: Curves.easeOut,
          margin: widget.margin,
          clipBehavior: widget.clipBehavior,
          decoration: BoxDecoration(
            color: color,
            borderRadius: widget.borderRadius,
          ),
          child: Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
