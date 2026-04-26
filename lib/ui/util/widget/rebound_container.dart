import 'package:flutter/material.dart';

import '../../feature/feature_curve.dart';

class ReboundContainer extends StatefulWidget {
  final double? pressedScale;
  final Duration? duration; //回弹持续时间
  final Widget? child;
  final Widget? surfaceChild; //组件非响应区

  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongTap;

  final BorderRadius? borderRadius;
  final ShapeBorder? shapeBorder; //高亮覆盖层修饰
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  final double hoverElevation;
  final double elevation;
  final Color? hoverColor;
  final Color? splashColor;
  final Color? highlightColor; //todo 缺少Inherited颜色传递
  final Color? backgroundColor;
  final Color? shadowColor;

  const ReboundContainer({
    super.key,
    this.pressedScale = 0.90,
    this.duration = const Duration(milliseconds: 160),
    this.child,
    this.surfaceChild,
    this.onTap,
    this.onLongTap,
    this.shapeBorder,
    this.borderRadius,

    this.hoverColor ,//= const Color.fromARGB(30, 255, 255, 255)
    this.splashColor ,//= const Color.fromARGB(30, 255, 255, 255),
    this.highlightColor ,//= const Color.fromARGB(30, 255, 255, 255),
    this.backgroundColor,
    this.shadowColor ,
    this.hoverElevation = 0.0,
    this.elevation = 0.0,
    this.padding = const EdgeInsets.all(0),
    this.margin = const EdgeInsets.all(0),
  });

  @override
  State<StatefulWidget> createState() => _ReboundContainer();
}

class _ReboundContainer extends State<ReboundContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> scale;

  bool isPressed = false;
  bool isHover = false;

  GestureTapDownCallback? onTapDown;
  GestureTapUpCallback? onTapUp;
  VoidCallback? onTapCancel;
  GestureLongPressCallback? onLongTap;
  ValueChanged<bool>? onHover;

  @override
  void initState() {
    if (widget.hoverElevation > 0.0) {
      onHover = (hover) {
        setState(() {
          isHover = hover;
        });
      };
    }
    if (widget.onTap != null) {
      onTapDown = (_) {
        setState(() {
          isPressed = true;
          if (!controller.isForwardOrCompleted) {
            controller.forward();
          }
        });
      };

      onTapUp = (_) {
        setState(() {
          isPressed = false;
          if (!controller.isAnimating) {
            controller.reverse();
          }
        });
        widget.onTap?.call();
      };

      onTapCancel = () {
        setState(() {
          isPressed = false;
          if (!controller.isAnimating) {
            controller.reverse();
          }
        });
      };
    }
    if (widget.onLongTap != null) {
      onLongTap = () {
        setState(() {
          isPressed = false;
          if (!controller.isForwardOrCompleted) {
            controller.forward();
          }
        });
        widget.onLongTap?.call();
      };
    }

    controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((state) {
        if (!isPressed && !state.isAnimating) {
          controller.reverse();
        }
      });
    scale = Tween(begin: 1.0, end: widget.pressedScale).animate(
      CurvedAnimation(
        parent: controller,
        curve: FeatureCurves.reboundIn,
        reverseCurve: FeatureCurves.reboundOut,
      ),
    );
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    return Padding(
      padding: widget.padding!,
      child: ScaleTransition(
        alignment: Alignment.center,
        scale: scale,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          children: [
            Material(
              borderRadius: widget.borderRadius,
              shape: widget.shapeBorder,
              color: widget.backgroundColor??Theme.of(context).colorScheme.secondaryContainer,
              shadowColor: widget.shadowColor,
              elevation:
                  isHover && !isPressed
                      ? widget.hoverElevation
                      : widget.elevation,
              child: InkWell(
                //todo 可以用WidgetStatesController优化代码
                autofocus: true,
                borderRadius: widget.borderRadius,
                customBorder: widget.shapeBorder,
                focusColor: Colors.transparent,
                hoverColor: widget.hoverColor,
                highlightColor: widget.highlightColor,
                splashColor: widget.splashColor,
                onTapDown: onTapDown,
                onTapUp: onTapUp,
                onTapCancel: onTapCancel,
                onHover: onHover,
                child: Padding(padding: widget.margin!, child: widget.child),
              ),
            ),
            if (widget.surfaceChild != null)
              Padding(padding: widget.margin!, child: widget.surfaceChild!),
          ],
        ),
      ),
    );
  }
}
