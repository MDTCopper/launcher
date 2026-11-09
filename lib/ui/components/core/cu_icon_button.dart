import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 纯图标按钮：方形热区 + 变色反馈，用于工具栏 / 侧栏 / 卡片右上角
class CuIconButton extends StatelessWidget {
  const CuIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.size = AppControlHeight.compact,
    this.plain = false,
    this.hint,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;

  /// 热区边长，默认 32
  final double size;

  /// 有底色（面）还是纯静音
  final bool plain;

  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget child = CuPressable(
      enabled: enabled,
      onTap: onTap,
      selected: selected,
      borderRadius: BorderRadius.circular(AppRadius.control),
      backgroundColor: plain ? colors.highBackgroundOnCard : Colors.transparent,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
          size: AppIconSize.inline,
          color: enabled
              ? (selected ? colors.interactive : colors.itemSecondary)
              : colors.itemHint,
        ),
      ),
    );

    final hint = this.hint;
    if (hint != null) {
      child = HintLayer(hint: hint, child: child);
    }
    return child;
  }
}
