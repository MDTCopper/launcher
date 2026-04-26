import 'package:flutter/cupertino.dart';

class PixelSlideAnimation extends AnimatedWidget {

  final Widget? child;

  const PixelSlideAnimation({
    super.key,
    required Animation<Offset> position,
    required this.child,
  }):super(listenable: position);

  Animation<Offset> get position => listenable as Animation<Offset>;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(offset: position.value,child: child);
  }
}
