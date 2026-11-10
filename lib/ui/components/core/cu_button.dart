import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 按钮观感：实心（主行动）/ 面（次级）/ 静音（弱化）
enum CuButtonKind { solid, plain, quiet }

/// 内核按钮：**直接复用设计层 [TemplateButton]**（视觉真源），
/// 保证实心/面/静音三档、悬停压暗、按下更深一档、禁用态与设计样张一致。
class CuButton extends StatelessWidget {
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
  final bool danger;
  final VoidCallback? onTap;
  final bool enabled;
  final bool expanded;

  /// 悬停提示（可选）
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final button = TemplateButton(
      skin: cuSkinOf(context),
      label: label,
      icon: icon ?? Icons.circle_outlined,
      kind: switch (kind) {
        CuButtonKind.solid => TemplateButtonKind.solid,
        CuButtonKind.plain => TemplateButtonKind.plain,
        CuButtonKind.quiet => TemplateButtonKind.quiet,
      },
      danger: danger,
      onTap: onTap,
      enabled: enabled,
      expanded: expanded,
    );

    final hintText = hint;
    if (hintText == null) return button;
    return Tooltip(message: hintText, child: button);
  }
}
