import 'package:copper_launcher/ui/page_framwork/page_switcher.dart';
import 'package:flutter/material.dart';

class MainPageLayout extends StatelessWidget {
  final Widget page;
  final Widget navigationRail;

  const MainPageLayout({
    super.key,
    required this.navigationRail,
    required this.page,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = Row(
      children: [
        Expanded(child: PageSwitcher(child: page)),
        navigationRail,
      ],
    );

    return child;
  }
}
