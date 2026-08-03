import 'package:flutter/material.dart';

class PageSwitcher extends StatelessWidget {
  final Widget child;
  const PageSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (c, a) {
        final Animation<Offset> position;
        if (a.isForwardOrCompleted) {
          position = Tween(
            begin: Offset(0.033, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.ease));
        } else {
          position = Tween(
            begin: Offset.zero,
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.ease));
        }
        c = SlideTransition(position: position, child: c);
        return FadeTransition(opacity: a, child: c);
      },
      child: child,
    );
  }
}
