import 'package:flutter/material.dart';

import '../widget/appear_grid_view.dart';
import '../widget/appear_list_view.dart';

class ListContentPanel extends StatelessWidget {
  final List<Widget?> items;
  final int delay;
  final double itemSpacing;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  const ListContentPanel({
    super.key,
    required this.items,
    this.delay = 200,
    this.itemSpacing = 12.0,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AppearListView(
      scrollController: controller,
      padding: padding,
      delay: delay,
      itemSpacing: itemSpacing,
      offset: Offset(-0.05, 0.0),
      appearDuration: const Duration(milliseconds: 300),
      items: items,
    );
  }
}

class ContentPanelModule extends StatelessWidget {
  final Widget? child;
  final String? title;
  const ContentPanelModule({super.key, this.child, this.title});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      //给item套上一层壳，表示一层分类
      elevation: 4.0,
      color: theme.colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            if (title != null)
              Text(
                title!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (child != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: DefaultTextStyle(
                  style: theme.textTheme.bodyMedium ?? TextStyle(),
                  child: IconTheme(data: theme.iconTheme, child: child!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

//暂时没用
class GridContentPanel extends StatelessWidget {
  final List<Widget?> items;
  final int delay;
  final double itemSpacing;
  final EdgeInsetsGeometry? padding;
  final Widget? header;
  final Widget? trailing;
  final SliverGridDelegate? gridDelegate;

  const GridContentPanel({
    super.key,
    required this.items,
    this.delay = 200,
    this.itemSpacing = 8.0,
    this.padding,
    this.header,
    this.trailing,
    this.gridDelegate,
  });

  @override
  Widget build(BuildContext context) {
    int gridDelay = delay;

    if (header != null) gridDelay += 300;

    Widget child = AppearGirdView(
      items: items,
      delay: gridDelay,
      gridDelegate: gridDelegate,
    );

    if (header != null || trailing != null) {
      child = AppearListView(
        padding: padding,
        items: [header, child, trailing],
        delay: delay,
        itemSpacing: itemSpacing,
        offset: Offset(-0.05, 0.0),
        appearDuration: const Duration(milliseconds: 300),
      );
    }

    return child;
  }
}
