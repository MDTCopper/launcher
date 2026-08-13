import 'package:flutter/material.dart';

import 'content_panel_module.dart';

/// 内容列表模块：便捷封装 —— [ContentPanelModule] 外观 + [Column] 条目。
///
/// 模块级惰性（页面滚动只构建可见模块）由 ListContentPanel 的
/// itemExtentBuilder 提供；模块内条目全量（模块可见时全部构建）。
class ContentListPanelModule extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const ContentListPanelModule({
    super.key,
    this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ContentPanelModule(
      title: title,
      child: Column(children: children),
    );
  }
}
