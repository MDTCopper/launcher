import 'package:flutter/material.dart';

/// 分类面板模块：纯装饰外壳，用于区分不同区域（Material 卡片 + 可选标题）。
///
/// 不做动画、不承载列表——内容多时请用 [ContentListPanelModule] / [ContentGridPanelModule]。
class ContentPanelModule extends StatelessWidget {
  final Widget? child;
  final String? title;

  const ContentPanelModule({super.key, this.child, this.title});

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
              Text(
                title!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (child != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
