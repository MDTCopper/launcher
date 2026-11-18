import 'package:copper_launcher/ui/components/core/cu_content_panel.dart';
import 'package:flutter/material.dart';

/// 列表面板：一张卡里装多条 tile
///
/// - 圆角由卡片裁剪（tile 自己不带圆角、不裁剪）
/// - tile 之间的 1px 线由**面板**画，不由 tile 画
/// - tile 的点击水波走 [CuPressable]，卡片负责把水波裁在圆角内
class CuListPanel extends StatelessWidget {
  const CuListPanel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.divider = true,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;

  /// 一行一个；tile 自己不要再画分隔线 / 圆角
  final List<Widget> children;

  final EdgeInsets margin;

  /// 是否在 tile 之间画线
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return CuContentPanel(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      margin: margin,
      flush: true,
      divider: divider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
