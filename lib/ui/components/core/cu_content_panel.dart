import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 标准内容卡：**标题在卡片之外**（设计层 `TemplateSection` 的口径），
/// 卡体 = 卡面底 + 圆角 + 1px 描边 + 12 模糊阴影；标题左缩进 4、与卡相距 8。
///
/// 页面里「一块内容」统一用它：
/// - 标题行在卡外（[title] / [subtitle] / [trailing]）
/// - 卡内默认内衬 12（[padding]），多条内容用 [children] + [spacing]
/// - [flush]：列表整块贴边（内衬归零，[headerDivider] 在标题行下加线需要卡内标题）
class CuContentPanel extends StatelessWidget {
  const CuContentPanel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.child,
    this.children = const [],
    this.padding = const EdgeInsets.all(TemplateSpace.md),
    this.spacing = TemplateSpace.sm,
    this.divider = false,
    this.flush = false,
    this.margin = const EdgeInsets.only(bottom: TemplateSpace.md),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final bool divider;
  final bool flush;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final skin = cuSkinOf(context);

    Widget? body;
    if (child != null) {
      body = flush ? child : Padding(padding: padding, child: child);
    } else if (children.isNotEmpty) {
      final column = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: divider ? 0 : spacing,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (divider && i > 0)
              Divider(height: 1, thickness: 1, color: skin.border),
            children[i],
          ],
        ],
      );
      body = flush ? column : Padding(padding: padding, child: column);
    }

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          if (title != null || subtitle != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: TemplateSpace.xs),
              child: Row(
                spacing: TemplateSpace.sm,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: TemplateSpace.xxs,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TemplateType.section.copyWith(
                              color: skin.textPrimary,
                            ),
                          ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TemplateType.caption.copyWith(
                              color: skin.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(TemplateRadius.card),
              border: Border.all(color: skin.border),
              boxShadow: [
                BoxShadow(
                  color: skin.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TemplateRadius.card),
              child: body ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
