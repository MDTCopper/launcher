import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'rebound_button.dart';

/// 无状态的图标 + 文本按钮（基于 [ReboundButton]）。
///
/// 与 [ActionButton]（有选中态）区分：无选中状态，适合不持久的操作入口。
/// 图标与文本共色（[AppColors.itemPrimary]），尺寸按内容收缩。
class IconTextButton extends StatelessWidget {
  final IconData icon;
  final String content;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final double? pressedScale;
  final double hoverElevation;
  final Color? baseColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  const IconTextButton({
    super.key,
    required this.icon,
    required this.content,
    this.onTap,
    this.onLongTap,
    this.pressedScale,
    this.hoverElevation = 2,
    this.baseColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.margin,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemColor = AppColors.of(context).itemPrimary;

    return ReboundButton(
      pressedScale: pressedScale,
      hoverElevation: hoverElevation,
      baseColor: baseColor,
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      onTap: onTap,
      onLongTap: onLongTap,
      child: IconTheme(
        data: IconTheme.of(context).copyWith(color: itemColor),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              content,
              style: theme.textTheme.labelLarge?.copyWith(color: itemColor),
            ),
          ],
        ),
      ),
    );
  }
}
