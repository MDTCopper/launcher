import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class PageNavigationRailItem {}

class PageNavigationRail extends StatefulWidget {
  final bool collapse;

  final double width;

  final double collapseWidth;

  final List<Widget> items;

  final bool showCollapseButton;

  const PageNavigationRail({
    super.key,
    required this.collapse,
    required this.width,
    this.collapseWidth = 57,
    required this.items,
    this.showCollapseButton = true,
  });

  @override
  State<StatefulWidget> createState() => _PageNavigationRailState();
}

class _PageNavigationRailState extends State<PageNavigationRail> {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    throw UnimplementedError();
  }
}
