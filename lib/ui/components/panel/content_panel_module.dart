import 'package:copper_launcher/ui/components/core/cu_content_panel.dart';
import 'package:flutter/material.dart';

/// 分类面板模块：纯装饰外壳，用于区分不同区域
///
/// 2026-11-10 重构：以 `CuContentPanel` 为标准（`CuCard` 地基 + 标题行 + 内衬规范），
/// 这里只做兼容外壳；新页面直接用 `CuContentPanel`，内容多时配合
/// `ContentListPanelModule` / `ContentGridPanelModule`
class ContentPanelModule extends StatelessWidget {
  final Widget? child;
  final String? title;

  const ContentPanelModule({super.key, this.child, this.title});

  @override
  Widget build(BuildContext context) {
    return CuContentPanel(title: title, child: child);
  }
}
