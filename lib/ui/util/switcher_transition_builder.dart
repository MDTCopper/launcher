import 'package:flutter/cupertino.dart';

abstract class SwitcherBuilders {
  ///[offset]是滑动方向，如[Offset(1.0, 0.0)]代表了切换时组件向右滑动，旧组件向右淡出，新组件从左边滑入
  static Widget Function(Widget, Animation<double>) fadeSlide([
    Offset offset = const Offset(1.0, 0.0),
  ]) {
    Widget function(Widget child, Animation<double> animation) {
      final opacity = CurvedAnimation(
        parent: animation,
        curve: Interval(0.4, 1.0),
      );
      final isForward = animation.isForwardOrCompleted;
      final reverseOffset = Offset(-offset.dx, -offset.dy);
      final position = Tween<Offset>(
        begin: isForward ? offset : reverseOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.ease));

      return FadeTransition(
        opacity: opacity,
        child: SlideTransition(position: position, child: child),
      );
    }

    return function;
  }
}
