import 'package:copper_launcher/ui/components/core/copper_pressable.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 内核复选：方框 + 勾，可带文字 / 图标
///
/// 点击整行都能切；按压只变色。
class CopperCheckbox extends StatelessWidget {
  const CopperCheckbox({
    super.key,
    required this.value,
    this.label,
    this.icon,
    this.onChanged,
    this.enabled = true,
    this.hint,
    this.iconColor,
  });

  final bool value;
  final String? label;
  final IconData? icon;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  /// 悬停提示
  final String? hint;

  /// 图标着色（默认取次要文字色）
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final canTap = enabled && onChanged != null;

    final box = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: !enabled
            ? colors.lowBackgroundOnCard
            : value
            ? colors.interactive
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          width: value ? 1 : 1.5,
          color: !enabled
              ? colors.lowBackgroundOnCard
              : value
              ? colors.interactive
              : colors.itemHint.withAlpha(170),
        ),
      ),
      child: value
          ? Icon(
              Icons.check,
              size: 14,
              color: enabled ? colors.itemOnInteractive : colors.itemHint,
            )
          : null,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.related,
      children: [
        box,
        if (label != null)
          Text(
            label!,
            style: textTheme.bodyMedium?.copyWith(
              color: enabled ? colors.itemPrimary : colors.itemHint,
            ),
          ),
        if (icon != null)
          Icon(
            icon,
            size: AppIconSize.inline,
            color: enabled
                ? (iconColor ?? colors.itemSecondary)
                : colors.itemHint,
          ),
      ],
    );

    Widget pressable = CopperPressable(
      enabled: canTap,
      onTap: canTap ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(AppRadius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tight,
        vertical: AppSpacing.tight,
      ),
      child: content,
    );

    final hint = this.hint;
    if (hint != null) {
      pressable = HintLayer(hint: hint, child: pressable);
    }
    return pressable;
  }
}
