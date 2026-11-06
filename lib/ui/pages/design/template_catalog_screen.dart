import 'package:copper_launcher/ui/pages/design/template_catalog_page.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 组件目录（App 内页面，`/template_catalog`，仅 debug 可见）
///
/// 内容就是设计层的全部组件与状态；调样式时开着这一页最方便对照
class TemplateCatalogScreen extends StatelessWidget {
  const TemplateCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);
    return ColoredBox(
      color: skin.page,
      child: TemplateScrollView(
        skin: skin,
        padding: const EdgeInsets.all(TemplateSpace.xl),
        child: TemplateCatalogPage(skin: skin),
      ),
    );
  }
}
