import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 内核设置行：标题（可挤压）+ 右侧控件，多行之间标题对齐
///
/// 行为：
/// 1. 可用宽度足够时标题取 [titleWide]，控件占满剩余空间
/// 2. 宽度不足时控件保 [controlMinWidth]，标题从固有宽开始被挤压（ellipsis），可压到 0
///
/// [decoration] 透传给外层容器（行底分隔线 `Border(bottom: ...)` 由调用方传）。
class CuSettingRow extends StatelessWidget {
  const CuSettingRow({
    super.key,
    required this.title,
    required this.control,
    this.description,
    this.titleWide = 150,
    this.controlMinWidth = 100,
    this.gap = AppSpacing.related,
    this.titleStyle,
    this.decoration,
  });

  final String title;
  final Widget control;

  /// 标题下的说明（可选，跟着标题一起被挤压）
  final String? description;

  final double titleWide;
  final double controlMinWidth;
  final double gap;
  final TextStyle? titleStyle;

  /// 透传容器装饰（行底分隔线 / 描边等）
  final BoxDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final row = LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final titleBudget = available - controlMinWidth - gap;
        final width = titleBudget >= titleWide
            ? titleWide
            : titleBudget.clamp(0.0, titleWide);

        return Row(
          children: [
            SizedBox(
              width: width,
              child: description == null
                  ? Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          titleStyle ??
                          textTheme.bodyMedium?.copyWith(
                            color: colors.itemPrimary,
                          ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              titleStyle ??
                              textTheme.bodyMedium?.copyWith(
                                color: colors.itemPrimary,
                              ),
                        ),
                        Text(
                          description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.itemHint,
                          ),
                        ),
                      ],
                    ),
            ),
            SizedBox(width: gap),
            SizedBox(width: available - width - gap, child: control),
          ],
        );
      },
    );

    if (decoration == null) return row;
    return Container(decoration: decoration, child: row);
  }
}
