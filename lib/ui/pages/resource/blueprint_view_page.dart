import 'package:copper_launcher/ui/util/framework/content_panel.dart';
import 'package:flutter/material.dart';

class BlueprintViewPage extends StatelessWidget {
  const BlueprintViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(title: '蓝图', child: Text('todo 蓝图浏览')),
      ],
    );
  }
}
