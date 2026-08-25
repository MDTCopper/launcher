import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 直接基于 [ReboundContainer]
/// - 双模式外观：
///   - 暗色：玻璃感——透明背景
///   - 浅色：云母片浮动感——不透明背景（[backgroundColor]），hover 浮出 [hoverElevation]
class ReboundButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final double? pressedScale;
  final double? elevation;
  final double hoverElevation;
  final Color? backgroundColor; // 浅色模式的云母片底色
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  final Color? hoverColor;
  final Color? splashColor;
  final Color? highlightColor;
  final Color? shadowColor;

  const ReboundButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongTap,
    this.pressedScale = 0.8,
    this.elevation,
    this.hoverElevation = 2,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(4),
    this.margin,
    this.borderRadius,
    this.hoverColor,
    this.splashColor,
    this.highlightColor,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = backgroundColor ?? AppColors.of(context).cardBackground;

    return ReboundContainer(
      pressedScale: pressedScale,
      elevation: elevation ?? 0.0,
      hoverElevation: hoverElevation,
      borderRadius: borderRadius ?? BorderRadius.circular(4),
      padding: padding,
      margin: margin,
      backgroundColor: baseColor,
      hoverColor: hoverColor,
      splashColor: splashColor,
      highlightColor: highlightColor,
      shadowColor: shadowColor,
      onTap: onTap,
      onLongTap: onLongTap,
      child: child,
    );
  }
}
