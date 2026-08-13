import 'package:flutter/material.dart';

import 'content_panel_module.dart';

/// 内容网格模块：便捷封装 —— [ContentPanelModule] 外观 + [Wrap] 条目。
///
/// 模块级惰性（页面滚动只构建可见模块）由 ListContentPanel 的
/// itemExtentBuilder 提供；模块内条目全量（模块可见时全部构建）。
class ContentGridPanelModule extends StatelessWidget {
  final String? title;
  final List<Widget> items;

  const ContentGridPanelModule({
    super.key,
    this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return ContentPanelModule(
      title: title,
      child: Wrap(children: items),
    );
  }
}
