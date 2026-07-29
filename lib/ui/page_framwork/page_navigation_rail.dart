import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class PageNavigationRail extends StatefulWidget {
  final bool collapse;

  final double width;

  final double collapseWidth;

  ///放入NavigationTile，也可放其他的
  final List<Widget> items;

  const PageNavigationRail({
    super.key,
    required this.collapse,
    required this.width,
    this.collapseWidth = 57,
    required this.items,
  });

  @override
  State<StatefulWidget> createState() => _PageNavigationRailState();
}

class _PageNavigationRailState extends State<PageNavigationRail> {
  bool get collapse => widget.collapse;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
      width: collapse ? 57 : 137,
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        spacing: 8,
        crossAxisAlignment: .start,
        children: widget.items,
      ),
    );
  }
}
