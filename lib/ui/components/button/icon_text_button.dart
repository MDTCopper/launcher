import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'rebound_button.dart';

/// 动作的重量：一个视图里只该有一个 [ActionWeight.primary]
///
/// 四级只差底色与前景，几何完全一样；依据见 `.project_status/components.md`
/// 的「视觉重心与动作分级」。注意 [danger] 是**语义**（破坏性）借了这一档表达，
/// 将来若要「轻量的危险」（红字不实心）再拆成独立的语义参数
enum ActionWeight { primary, secondary, tertiary, danger }

/// 无状态的图标 + 文本按钮（基于 [ReboundButton]）
///
/// 与 [ActionButton]（有选中态）区分：无选中状态，适合不持久的操作入口
/// 图标与文本共色（按 [weight] 取），尺寸按内容收缩
///
/// 禁用 = [onTap] 与 [onLongTap] 都不给：前景置灰、实心档丢掉底色、不再浮出
class IconTextButton extends StatelessWidget {
  final IconData icon;
  final String content;
  final double? width;
  final double? heigth;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final double? pressedScale;
  final double hoverElevation;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final ActionWeight weight;

  const IconTextButton({
    super.key,
    this.width,
    this.heigth,
    required this.icon,
    required this.content,
    this.onTap,
    this.onLongTap,
    this.pressedScale,
    this.hoverElevation = 2,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.margin,
    this.borderRadius,
    this.weight = ActionWeight.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final (weightBackground, weightForeground) = switch (weight) {
      ActionWeight.primary => (colors.interactive, colors.itemOnInteractive),
      ActionWeight.secondary => (
        colors.highBackgroundOnCard,
        colors.itemSecondary,
      ),
      ActionWeight.tertiary => (Colors.transparent, colors.interactive),
      ActionWeight.danger => (colors.error, colors.itemOnInteractive),
    };

    final enabled = onTap != null || onLongTap != null;
    // 实心档禁用时丢掉底色，免得一个点不动的按钮还在抢注意力
    final filled =
        weight == ActionWeight.primary || weight == ActionWeight.danger;
    final background = !enabled && filled
        ? colors.lowBackgroundOnCard
        : (backgroundColor ?? weightBackground);
    final itemColor = enabled ? weightForeground : colors.itemHint;

    Widget child = ReboundButton(
      pressedScale: pressedScale,
      hoverElevation: enabled ? hoverElevation : 0,
      backgroundColor: background,
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
              style: theme.textTheme.bodyMedium?.copyWith(color: itemColor),
            ),
          ],
        ),
      ),
    );

    if (width != null || heigth != null) {
      child = SizedBox(width: width, height: heigth, child: child);
    }

    return child;
  }
}
