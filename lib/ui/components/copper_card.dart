import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CopperCard extends StatelessWidget {
  final Color? color;
  final double? elevation;
  final BorderRadius? borderRadius;
  final Alignment? alignment;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Widget child;

  const CopperCard({
    super.key,
    this.color,
    this.elevation,
    this.borderRadius,
    this.alignment,
    this.padding = const EdgeInsets.all(8),
    this.margin = const EdgeInsets.all(4),
    required this.child,
  });

  List<BoxShadow> _materialShadow(Color color, double elevation) {
    final alpha = (0.05 + elevation * 0.025).clamp(0.05, 0.25);

    return [
      BoxShadow(
        color: color.withAlpha((alpha * 0.6 * 255).round()),
        offset: Offset(0, elevation * 0.5),
        blurRadius: elevation * 1.5,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: color.withAlpha((alpha * 255).round()),
        offset: Offset(0, elevation * 0.25),
        blurRadius: elevation * 0.75,
        spreadRadius: 0,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == .dark;
    final colors = AppColors.of(context);

    return Container(
      padding: padding,
      margin: margin,
      alignment: alignment,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: isDark ? Border.all(color: colors.border) : null,
        borderRadius:
            borderRadius ?? const BorderRadius.all(Radius.circular(8)),
        boxShadow: isDark
            ? null
            : _materialShadow(colors.shadow, elevation ?? 4.0),
      ),

      child: child,
    );
  }
}
