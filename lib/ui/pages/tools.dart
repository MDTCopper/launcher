import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [ContentPanelModule(title: '神秘小工具', child: Text('todo 神秘小工具'))],
    );
  }
}
