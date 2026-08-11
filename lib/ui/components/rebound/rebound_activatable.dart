import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ReboundActivatableContainer extends StatefulWidget {
  final Duration duration;
  final bool value;
  final Color? backgroundColor;
  final Color? backgroundActiveColor;

  final Widget? child;
  final Widget? surfaceChild;
  final VoidCallback onTap;
  final VoidCallback? onLongTap;
  final ShapeBorder? shapeBorder;
  final BorderRadius? borderRadius;
  final double hoverElevation;
  final double elevation;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double pressedScale;

  const ReboundActivatableContainer({
    super.key,
    this.duration = const Duration(milliseconds: 300),
    this.value = false,
    this.backgroundColor,
    this.backgroundActiveColor,
    this.child,
    this.surfaceChild,
    required this.onTap,
    this.hoverElevation = 0,
    this.elevation = 0,
    this.padding,
    this.margin,
    this.onLongTap,
    this.shapeBorder,
    this.borderRadius,
    this.pressedScale = 0.9,
  });

  @override
  State<StatefulWidget> createState() => ReboundActivatableContainerState();
}

class ReboundActivatableContainerState
    extends State<ReboundActivatableContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.value) controller.animateTo(1.0);
  }

  @override
  void didUpdateWidget(covariant ReboundActivatableContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context);
    final bT = ColorTween(
      begin: widget.backgroundColor ?? color.cardBackground,
      end: widget.backgroundActiveColor ?? color.interactive.withAlpha(85),
    ).animate(controller);

    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return ReboundContainer(
          surfaceChild: widget.surfaceChild,
          backgroundColor: bT.value,
          hoverElevation: widget.hoverElevation,
          elevation: widget.elevation,
          padding: widget.padding,
          margin: widget.margin,
          shapeBorder: widget.shapeBorder,
          borderRadius: widget.borderRadius,
          pressedScale: widget.pressedScale,
          onTap: widget.onTap,
          onLongTap: widget.onLongTap,
          child: widget.child,
        );
      },
    );
  }
}
