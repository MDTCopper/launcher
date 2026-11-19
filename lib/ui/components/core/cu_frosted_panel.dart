import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 磨砂浮层面板：搬运设计层 [TemplateFrostedPanel]，用于叠加在动态流光或自定义背景上的浮层
class CuFrostedPanel extends StatelessWidget {
  const CuFrostedPanel({
    super.key,
    required this.child,
    this.radius = TemplateRadius.card,
    this.padding = EdgeInsets.zero,
    this.blur = 18,
    this.opacity,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double? opacity;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return TemplateFrostedPanel(
      skin: cuSkinOf(context),
      radius: radius,
      padding: padding,
      blur: blur,
      opacity: opacity,
      shadow: shadow,
      child: child,
    );
  }
}
