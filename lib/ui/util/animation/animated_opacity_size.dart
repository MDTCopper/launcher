import 'package:flutter/material.dart';

///child为空时child也不会立刻消失，而是经历一段淡出
class AnimatedOpacitySize extends StatefulWidget {
  final Widget? child;
  final Duration duration;

  final Curve curve;
  final Alignment alignment;

  ///child为空时的不透明度
  final double opacity;
  final double existsOpacity;

  //淡入淡出时回调
  final VoidCallback? fadeOnEnd;

  //缩放结束时回调
  final VoidCallback? sizeOnEnd;

  const AnimatedOpacitySize({
    super.key,
    this.child,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.ease,
    this.opacity = 0.0,
    this.existsOpacity = 1.0,
    this.fadeOnEnd,
    this.sizeOnEnd,
    this.alignment = Alignment.center,
  });

  @override
  State<StatefulWidget> createState() => AnimatedOpacitySizeState();
}

class AnimatedOpacitySizeState extends State<AnimatedOpacitySize> {
  Widget? currentChild;

  @override
  void initState() {
    super.initState();
    currentChild = widget.child;
  }

  @override
  void didUpdateWidget(covariant AnimatedOpacitySize oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child != null) {
      currentChild = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.child == null ? widget.opacity : widget.existsOpacity,
      curve: widget.curve,
      duration: widget.duration,
      onEnd: () {
        widget.fadeOnEnd?.call();
        if (widget.child == null) {
          setState(() {
            currentChild = null;
          });
        }
      },
      child: AnimatedSize(
        duration: widget.duration,
        alignment: widget.alignment,
        curve: widget.curve,
        onEnd: widget.sizeOnEnd,
        child: currentChild ?? SizedBox(),
      ),
    );
  }
}
