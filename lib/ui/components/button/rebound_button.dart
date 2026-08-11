import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 直接基于 [ReboundContainer]
/// - 双模式外观：
///   - 暗色：玻璃感——透明背景
///   - 浅色：云母片浮动感——不透明背景（[baseColor]），hover 浮出 [hoverElevation]
class ReboundButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final double? pressedScale;
  final double? elevation;
  final double hoverElevation;
  final Color? baseColor; // 浅色模式的云母片底色
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  const ReboundButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongTap,
    this.pressedScale,
    this.elevation,
    this.hoverElevation = 2,
    this.baseColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.margin,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = this.baseColor ?? AppColors.of(context).cardBackground;

    return ReboundContainer(
      pressedScale: pressedScale,
      elevation: elevation ?? 0.0,
      hoverElevation: hoverElevation,
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      padding: padding,
      margin: margin,
      backgroundColor: isDark ? Colors.transparent : baseColor,
      onTap: onTap,
      onLongTap: onLongTap,
      child: child,
    );
  }
}
