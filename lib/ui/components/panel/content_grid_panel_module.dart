import 'package:copper_launcher/ui/components/animation/reveal_grid_view.dart';
import 'package:flutter/material.dart';

/// 内容网格模块：分类外壳 + **惰性网格**（游戏内设置等紧凑排列场景）。
///
/// - **生长式入场 + 滚动浮现**（由 [RevealGridView.builder] 提供，scale + fade）
/// - 惰性精确总长依赖 gridDelegate 的 mainAxisExtent（如
///   [SliverGridDelegateWithFixedCrossAxisCount.mainAxisExtent]）
class ContentGridPanelModule extends StatelessWidget {
  final String? title;

  // ── 惰性网格 ──
  final SliverGridDelegate gridDelegate;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  // ── 生长/浮现动画 ──
  final double interval;
  final int delay;
  final Duration appearDuration;
  final double startScale;

  // ── 布局 ──
  final double itemSpacing;

  const ContentGridPanelModule({
    super.key,
    this.title,
    required this.gridDelegate,
    required this.itemCount,
    required this.itemBuilder,
    this.interval = 0.15,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 300),
    this.startScale = 0.75,
    this.itemSpacing = 8,
  });

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
            RevealGridView.builder(
              gridDelegate: gridDelegate,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
              interval: interval,
              delay: delay,
              appearDuration: appearDuration,
              startScale: startScale,
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
