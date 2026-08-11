import 'package:copper_launcher/ui/page_framwork/page_switcher.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
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
    final colors = AppColors.of(context);
    Widget child = Row(
      children: [
        Expanded(child: PageSwitcher(child: page)),
        VerticalDivider(color: colors.border),
        navigationRail,
      ],
    );

    return child;
  }
}
