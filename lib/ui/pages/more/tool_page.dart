import 'package:copper_launcher/ui/util/framework/content_panel.dart';
import 'package:flutter/material.dart';

class ToolPage extends StatelessWidget {
  const ToolPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(title: '神秘小工具', child: Text('todo 神秘小工具')),
      ],
    );
  }
}
