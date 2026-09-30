import 'package:copper_launcher/ui/components/copper_card.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 分类面板模块：纯装饰外壳，用于区分不同区域
///
/// 不做动画、不承载列表——内容多时用 [ContentListPanelModule] / [ContentGridPanelModule]
class ContentPanelModule extends StatelessWidget {
  final Widget? child;
  final String? title;

  const ContentPanelModule({super.key, this.child, this.title});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final colors = AppColors.of(context);

    return CopperCard(
      margin: const EdgeInsets.all(0),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          if (title != null)
            Text(
              title!,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colors.interactive,
              ),
            ),
          if (child != null)
            DefaultTextStyle(
              style: theme.textTheme.bodyMedium ?? TextStyle(),
              child: IconTheme(data: theme.iconTheme, child: child!),
            ),
        ],
      ),
    );
  }
}
