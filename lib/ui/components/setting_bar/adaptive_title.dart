import 'package:flutter/material.dart';

/// 设置条标题列：宽窗口下固定 [titleWide] 宽，窄窗口下自动收缩 + 省略号。
///
/// 用 [Flexible] + [ConstrainedBox] 实现"优先固定宽、空间不足时让位"：
/// - 空间充足：标题最宽 [titleWide]，与旧版固定列观感一致
/// - 空间不足：标题收缩、文本 ellipsis，把剩余空间让给右侧控件区
class AdaptiveTitle extends StatelessWidget {
  final String title;
  final double titleWide;
  final TextStyle? style;
  final EdgeInsetsGeometry? margin;

  const AdaptiveTitle({
    super.key,
    required this.title,
    this.titleWide = 150,
    this.style,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );

    final constrained = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: titleWide),
      child: text,
    );

    return Flexible(child: Padding(padding: margin ?? EdgeInsets.zero, child: constrained));
  }
}