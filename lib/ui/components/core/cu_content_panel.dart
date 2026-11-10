import 'package:copper_launcher/ui/components/cu_card.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 标准页面内容卡（ContentPanel 重构版）
///
/// 以 [CuCard] 为地基，统一「一块内容」的排版：
/// - 标题行：标题 + 可选说明 + 右侧动作
/// - 内容：`child` 单块，或 `children` 多条（按 [spacing] 排，[divider] 时插 1px 分隔线）
/// - [flush]：内容贴边（版本列表、设置列表这类整块列表用），标题行仍保留内衬
///
/// 页面里所有「分块内容」都用它，不要再各自拼 Card + Column。
class CuContentPanel extends StatelessWidget {
  const CuContentPanel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.child,
    this.children = const [],
    this.padding = const EdgeInsets.all(AppSpacing.section),
    this.spacing = AppSpacing.related,
    this.divider = false,
    this.flush = false,
    this.headerDivider = false,
    this.margin = EdgeInsets.zero,
  });

  final String? title;
  final String? subtitle;

  /// 标题行右侧动作（按钮 / 开关 / ⋯ 菜单）
  final Widget? trailing;

  /// 单块内容
  final Widget? child;

  /// 多条内容（与 [child] 二选一）
  final List<Widget> children;

  final EdgeInsetsGeometry padding;
  final double spacing;

  /// 多条内容之间插 1px 分隔线
  final bool divider;

  /// 内容贴边：内衬为 0，由内容自己排（列表 / 表格）
  final bool flush;

  /// 标题行与内容之间插 1px 分隔线
  final bool headerDivider;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final hasHeader = title != null || subtitle != null || trailing != null;

    Widget? header;
    if (hasHeader) {
      header = Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.section,
          AppSpacing.group,
          AppSpacing.related,
          AppSpacing.group,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: AppSpacing.related,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.inline,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: colors.itemPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.itemHint,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
    }

    Widget? body;
    if (child != null) {
      body = flush
          ? child
          : Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.section,
                0,
                AppSpacing.section,
                AppSpacing.section,
              ),
              child: child,
            );
    } else if (children.isNotEmpty) {
      final column = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: divider ? 0 : spacing,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (divider && i > 0)
              Divider(height: 1, thickness: 1, color: colors.border),
            children[i],
          ],
        ],
      );
      body = flush
          ? column
          : Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.section,
                0,
                AppSpacing.section,
                AppSpacing.section,
              ),
              child: column,
            );
    }

    return CuCard(
      margin: margin,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(AppRadius.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) header,
          if (headerDivider)
            Divider(height: 1, thickness: 1, color: colors.border),
          if (body != null) body,
        ],
      ),
    );
  }
}
