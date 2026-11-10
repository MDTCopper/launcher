import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 可点击表面的统一反馈：**只变色、不变形**
///
/// 为什么不用 `ReboundContainer` 的缩放：整块缩小时，行内分隔线会跟着缩、
/// 行外分隔线会露缝，密集列表 / 表格 / 菜单也无法稳定排版；密集场景统一走
/// 这里的颜色反馈（悬停 +6~8%、按下 +10~14%、选中用强调色淡底），
/// 只有独立的主行动按钮才保留轻微回弹
///
/// 状态优先级：禁用 > 按下 > 选中 > 悬停 > 常态
///
/// 颜色**瞬间切换**，不做隐式插值：隐式动画（AnimatedContainer 一类）在换主题时
/// 会从旧色缓动到新色，看起来慢半拍
class CuPressable extends StatefulWidget {
  const CuPressable({
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
    this.decoration,
    this.clipBehavior = Clip.none,
    this.onPressedChanged,
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

  /// 透传给底层的容器装饰（边框 / 描边等）；颜色与圆角仍由本组件接管
  /// 行底分隔线一类的事情由调用方在这里传，不在组件内部特判
  final BoxDecoration? decoration;

  final Clip clipBehavior;

  /// 按下状态变化（给需要轻微回弹的主按钮用；不要在回调里改颜色做动画）
  final ValueChanged<bool>? onPressedChanged;

  @override
  State<CuPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<CuPressable>
    with TickerProviderStateMixin {
  /// 悬停 / 按下的插值进度（0~1）
  ///
  /// 只插值这两个交互态；颜色端点每次 build 从 [AppColors] 重新取，
  /// 所以换主题时颜色**立刻**变成新色，不会被这两条曲线拖慢
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
  );

  bool _hovered = false;
  bool _pressed = false;

  @override
  void dispose() {
    _hover.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CuPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _hovered = false;
      _pressed = false;
      _hover.stop();
      _press.stop();
      _hover.value = 0;
      _press.value = 0;
    }
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    if (value) {
      _hover.forward();
    } else {
      _hover.reverse();
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    if (value) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = widget.enabled;
    final active =
        enabled && (widget.onTap != null || widget.onLongTap != null);

    final base = !enabled
        ? (widget.backgroundColor ?? Colors.transparent)
        : widget.selected
        ? (widget.selectedColor ?? colors.indicatorBackground)
        : (widget.backgroundColor ?? Colors.transparent);

    // 悬停 / 按下都画成**叠在底上的半透明层**，只动画各层自己的 alpha：
    // - 底色始终不变，不会出现「底色忽明忽暗」
    // - 悬停层 → 按下层是相加关系，按下时只是在悬停结果上再压一档，不会互相顶掉
    // - 颜色端点每帧从 AppColors 重取，换主题仍然瞬切
    final hoverColor = widget.hoverColor ?? colors.highBackgroundOnCard;
    final pressColor = widget.pressedColor ?? colors.splash;

    Widget overlay(Color color, double t) {
      final alpha = (color.a * t).clamp(0.0, 1.0);
      if (alpha <= 0) return const SizedBox.shrink();
      return IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withAlpha((alpha * 255).round()),
            borderRadius: widget.borderRadius,
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: active ? (_) => _setHovered(true) : null,
      onExit: active ? (_) => _setHovered(false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? widget.onTap : null,
        onLongPress: active ? widget.onLongTap : null,
        onSecondaryTap: active ? widget.onSecondaryTap : null,
        onTapDown: active
            ? (_) {
                _setPressed(true);
                widget.onPressedChanged?.call(true);
              }
            : null,
        onTapUp: active
            ? (_) {
                _setPressed(false);
                widget.onPressedChanged?.call(false);
              }
            : null,
        onTapCancel: active
            ? () {
                _setPressed(false);
                widget.onPressedChanged?.call(false);
              }
            : null,
        child: AnimatedBuilder(
          animation: Listenable.merge([_hover, _press]),
          builder: (context, child) {
            return Container(
              margin: widget.margin,
              clipBehavior: widget.clipBehavior,
              decoration: (widget.decoration ?? const BoxDecoration()).copyWith(
                color: base,
                borderRadius: widget.borderRadius,
              ),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  // 反馈层必须画在内容**下面**：悬停色是不透明面（raised）时
                  // 画在上面会把文字/图标整块盖住
                  if (enabled)
                    Positioned.fill(child: overlay(hoverColor, _hover.value)),
                  if (enabled)
                    Positioned.fill(child: overlay(pressColor, _press.value)),
                  Padding(
                    padding: widget.padding ?? EdgeInsets.zero,
                    child: widget.child,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
