import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

import 'package:copper_launcher/ui/vars.dart';

import 'package:flutter/material.dart';

class PageNavigationRail extends StatelessWidget {
  final Duration? collapseDuration;

  final bool collapse;

  final double width;

  final double collapseWidth;

  ///放入NavigationTile，也可放其他的，会以ScrollView的形式展示
  final List<Widget> items;

  ///itemsAtBottom显示在底部，显示优先于items，作为导航栏固定内容，放入页面工具
  final List<Widget> itemsAtBottom;

  const PageNavigationRail({
    super.key,
    required this.collapse,
    required this.width,
    this.collapseWidth = 57,
    required this.items,
    this.itemsAtBottom = const [],
    this.collapseDuration,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget top = CopperSingleChildScrollView(
      padding: EdgeInsets.all(8),
      child: Column(
        spacing: 4,
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: items,
      ),
    );

    final Widget child;
    if (itemsAtBottom.isNotEmpty) {
      final bottom = Column(
        spacing: 4,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: .start,
        children: itemsAtBottom,
      );
      child = Column(
        spacing: 4,
        crossAxisAlignment: .start,
        children: [
          Expanded(child: top),
          Padding(padding: EdgeInsets.all(8), child: bottom),
        ],
      );
    } else {
      child = top;
    }

    return AnimatedContainer(
      duration: animationDuration,
      curve: Curves.ease,
      width: collapse ? collapseWidth : width,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: child,
    );
  }
}
