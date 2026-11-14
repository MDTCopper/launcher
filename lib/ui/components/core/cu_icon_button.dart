import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:flutter/material.dart';

/// 图标按钮：搬运设计层 [TemplateIconButton]（圆形热区 + 悬停反馈 + 提示）
class CuIconButton extends StatelessWidget {
  const CuIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.size = 32,
    this.iconSize = 18,
    this.plain = false,
    this.hint,
    this.rotationTurns = 0.0,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;

  /// 热区边长，默认 32
  final double size;

  final double iconSize;

  /// 是否带底色（设计层的 plain 由 TemplateIconButton 的 selected/背景表达）
  final bool plain;

  final String? hint;

  final double rotationTurns;

  @override
  Widget build(BuildContext context) {
    return TemplateIconButton(
      skin: cuSkinOf(context),
      icon: icon,
      onTap: onTap,
      tooltip: hint,
      iconSize: iconSize,
      size: size,
      selected: selected || plain,
      enabled: enabled,
      rotationTurns: rotationTurns,
    );
  }
}
