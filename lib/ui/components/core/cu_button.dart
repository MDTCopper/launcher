import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 按钮观感：实心（主行动）/ 面（次级）/ 静音（弱化）
enum CuButtonKind { solid, plain, quiet }

/// 内核按钮：吃 `AppColors` + `DesignSystem` 几何，按压只变色
///
/// 只有 [CuButtonKind.solid] 带 0.97 的轻微回弹（主行动按钮的确认感），
/// 其余两档不做几何变化，方便放进列表 / 工具条 / 表单里
class CuButton extends StatefulWidget {
  const CuButton({
    super.key,
    required this.label,
    this.icon,
    this.kind = CuButtonKind.solid,
    this.danger = false,
    this.onTap,
    this.enabled = true,
    this.expanded = false,
    this.hint,
  });

  final String label;
  final IconData? icon;
  final CuButtonKind kind;

  /// 危险标识：底色 / 文字换成错误语义色
  final bool danger;

  final VoidCallback? onTap;
  final bool enabled;

  /// 撑满可用宽度、内容居中
  final bool expanded;

  /// 悬停提示（可选）
  final String? hint;

  @override
  State<CuButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<CuButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final (Color background, Color foreground) = switch (widget.kind) {
      CuButtonKind.solid =>
        widget.enabled
            ? (
                widget.danger ? colors.error : colors.interactive,
                colors.itemOnInteractive,
              )
            : (
                widget.danger
                    ? colors.error.withAlpha(30)
                    : colors.lowBackgroundOnCard,
                colors.itemHint,
              ),
      CuButtonKind.plain => (
        widget.enabled
            ? colors.highBackgroundOnCard
            : colors.lowBackgroundOnCard,
        widget.enabled
            ? (widget.danger ? colors.error : colors.itemPrimary)
            : colors.itemHint,
      ),
      CuButtonKind.quiet => (
        Colors.transparent,
        widget.enabled
            ? (widget.danger ? colors.error : colors.itemSecondary)
            : colors.itemHint,
      ),
    };

    final solid = widget.kind == CuButtonKind.solid && widget.enabled;
    final hoverColor = switch (widget.kind) {
      CuButtonKind.solid => Color.alphaBlend(
        Colors.black.withAlpha(18),
        background,
      ),
      _ => colors.highBackgroundOnCard,
    };
    final pressedColor = switch (widget.kind) {
      CuButtonKind.solid => Color.alphaBlend(
        Colors.black.withAlpha(30),
        background,
      ),
      _ => colors.splash,
    };

    Widget child = CuPressable(
      enabled: widget.enabled,
      onTap: widget.onTap,
      onPressedChanged: solid
          ? (value) => setState(() => _pressed = value)
          : null,
      borderRadius: BorderRadius.circular(AppRadius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.group,
        vertical: AppSpacing.related - 2,
      ),
      backgroundColor: background,
      hoverColor: widget.enabled ? hoverColor : Colors.transparent,
      pressedColor: widget.enabled ? pressedColor : Colors.transparent,
      child: IconTheme(
        data: IconThemeData(color: foreground, size: AppIconSize.inline),
        child: Row(
          mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: widget.expanded
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          spacing: AppSpacing.related,
          children: [
            if (widget.icon != null) Icon(widget.icon),
            Text(
              widget.label,
              style: textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    if (solid) {
      child = AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: child,
      );
    }

    final hint = widget.hint;
    if (hint != null) {
      child = HintLayer(hint: hint, child: child);
    }
    return child;
  }
}
