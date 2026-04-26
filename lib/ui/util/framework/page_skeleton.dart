import 'package:copperlauncher_main/ui/util/framework/menu_bar.dart';
import 'package:flutter/cupertino.dart';

class PageSkeleton extends StatelessWidget {
  final Widget body;
  final SideMenuBar menuBar;

  const PageSkeleton({super.key, required this.body, required this.menuBar});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 200),
            switchInCurve: Interval(0.4, 1.0, curve: Curves.easeIn),
            switchOutCurve: Interval(0.6, 1.0, curve: Curves.easeIn),
            transitionBuilder: (child, animation) {
              final Animation<double> opacity = Tween(
                begin: 0.0,
                end: 1.0,
              ).animate(animation);

              return FadeTransition(opacity: opacity, child: child);
            },
            child: body,
          ),
        ),
        menuBar,
      ],
    );
  }
}
