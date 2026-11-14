import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 复选：搬运设计层 [TemplateCheckbox]，可带文字 / 图标 / 提示
class CuCheckbox extends StatelessWidget {
  const CuCheckbox({
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
  final String? hint;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final skin = cuSkinOf(context);
    final canTap = enabled && onChanged != null;

    Widget check = TemplateCheckbox(
      skin: skin,
      value: value,
      enabled: enabled,
      onTap: canTap ? () => onChanged!(!value) : null,
    );

    if (label != null || icon != null) {
      check = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TemplateSpace.sm,
        children: [
          check,
          if (label != null)
            Text(
              label!,
              style: TemplateType.item.copyWith(
                color: enabled ? skin.textPrimary : skin.textDisabled,
              ),
            ),
          if (icon != null)
            Icon(
              icon,
              size: TemplateSpace.sm * 2 + 2,
              color: enabled
                  ? (iconColor ?? skin.textSecondary)
                  : skin.textDisabled,
            ),
        ],
      );
    }

    final hintText = hint;
    if (hintText != null) {
      check = HintLayer(hint: hintText, child: check);
    }
    return check;
  }
}
