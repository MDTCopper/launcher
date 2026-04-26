import 'package:flutter/material.dart';

class InkContainer extends StatelessWidget {
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Decoration? decoration;
  final double? width;
  final double? height;

  final AlignmentGeometry? alignment;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;

  final Widget? child;

  const InkContainer({
    super.key,
    this.alignment,
    this.constraints,
    this.margin,
    this.clipBehavior = Clip.hardEdge,
    this.child,
    this.padding,
    this.color,
    this.decoration,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    Widget? current = child;

    if (alignment != null) {
      current = Align(alignment: alignment!, child: current);
    }
    if (margin != null) current = Padding(padding: margin!, child: current);

    current = Ink(
      padding: padding,
      color: color,
      decoration: decoration,
      width: width,
      height: height,
      child: current,
    );

    if (constraints != null) {
      current = ConstrainedBox(constraints: constraints!, child: current);
    }
    current = ClipPath(clipBehavior: clipBehavior, child: current);

    return current;
  }
}
