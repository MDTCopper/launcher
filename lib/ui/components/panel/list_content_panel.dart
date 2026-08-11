import 'package:copper_launcher/ui/components/animation/reveal_list_view.dart';
import 'package:flutter/material.dart';

/// 页面最基础骨架：负责滚动模块列表，带模块级错位入场动画。
///
/// 基于 [RevealListView]（全量构造：模块数量少，错位入场无浮现）。
/// 内容多的模块请用 [ContentListPanelModule] / [ContentGridPanelModule]
class ListContentPanel extends StatelessWidget {
  final List<Widget?> items;
  final int delay;
  final double interval;
  final double itemSpacing;
  final EdgeInsetsGeometry? padding;
  final Offset offset;
  final ScrollController? controller;

  const ListContentPanel({
    super.key,
    required this.items,
    this.delay = 200,
    this.interval = 0.3,
    this.itemSpacing = 12.0,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
    this.offset = const Offset(-0.05, 0.0),
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return RevealListView(
      items: items,
      delay: delay,
      interval: interval,
      itemSpacing: itemSpacing,
      padding: padding,
      offset: offset,
      scrollController: controller,
      appearDuration: const Duration(milliseconds: 300),
    );
  }
}
