import 'package:copper_launcher/ui/components/animation/reveal_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 内容列表模块：分类外壳 + **惰性条目列表**（条目多时性能好）。
///
/// - **错位入场 + 滚动浮现**（由 [RevealListView.builder] 提供）
/// - **必须提供高度预期**（[itemExtent] / [prototypeItem] / [itemExtentBuilder] 三选一），
///   让模块总长精确可预测 → 页面滚动条不乱跳
///
/// 用法：
/// ```dart
/// ContentListPanelModule(
///   title: '搜索结果',
///   itemCount: results.length,
///   itemBuilder: (context, i) => ResultTile(...),
///   itemExtent: 64,
/// )
/// ```
class ContentListPanelModule extends StatelessWidget {
  final String? title;

  // ── 惰性条目 ──
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  // ── 高度预期（三选一）──
  final double? itemExtent;
  final Widget? prototypeItem;
  final ItemExtentBuilder? itemExtentBuilder;

  // ── 错位/浮现动画 ──
  final double interval;
  final int delay;
  final Duration appearDuration;

  // ── 布局 ──
  final double itemSpacing;

  const ContentListPanelModule({
    super.key,
    this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.itemExtent,
    this.prototypeItem,
    this.itemExtentBuilder,
    this.interval = 0.2,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 200),
    this.itemSpacing = 8,
  }) : assert(
         (itemExtent != null ? 1 : 0) +
                 (prototypeItem != null ? 1 : 0) +
                 (itemExtentBuilder != null ? 1 : 0) ==
             1,
         '必须且只能提供 itemExtent / prototypeItem / itemExtentBuilder 之一',
       );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      elevation: 4.0,
      color: theme.colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  title!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            // shrinkWrap + NeverScrollable：模块跟随父滚动容器，不独立滚动
            RevealListView.builder(
              itemCount: itemCount,
              itemBuilder: itemBuilder,
              itemExtent: itemExtent,
              prototypeItem: prototypeItem,
              itemExtentBuilder: itemExtentBuilder,
              interval: interval,
              delay: delay,
              appearDuration: appearDuration,
              itemSpacing: itemSpacing,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ],
        ),
      ),
    );
  }
}
