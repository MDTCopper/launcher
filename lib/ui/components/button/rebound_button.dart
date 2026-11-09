import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 兼容入口：历史调用点很多，内部已改为 [CuPressable]（变色、不缩放）
///
/// 保留原来的参数签名，避免大范围改调用点；`pressedScale` / `elevation` /
/// `hoverElevation` / `shadowColor` 只做兼容，不再生效。
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
    final backgroundColor =
        this.backgroundColor ?? AppColors.of(context).highBackgroundOnCard;

    return CuPressable(
      borderRadius: borderRadius ?? BorderRadius.circular(4),
      padding: padding,
      margin: margin,
      backgroundColor: backgroundColor,
      hoverColor: hoverColor,
      pressedColor: splashColor,
      onTap: onTap,
      onLongTap: onLongTap,
      child: child,
    );
  }
}
