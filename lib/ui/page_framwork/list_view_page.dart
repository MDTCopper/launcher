import 'package:copper_launcher/ui/page_framwork/page_switcher.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class MainPageLayout extends StatelessWidget {
  final Widget page;

  /// 页内导航栏；不传就是满宽内容页（页头自带切换入口）
  final Widget? navigationRail;

  const MainPageLayout({super.key, required this.page, this.navigationRail});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rail = navigationRail;
    Widget child = Row(
      children: [
        Expanded(child: PageSwitcher(child: page)),
        if (rail != null) ...[VerticalDivider(color: colors.border), rail],
      ],
    );

    return child;
  }
}
