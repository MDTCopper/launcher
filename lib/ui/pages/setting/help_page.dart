import 'package:copper_launcher/ui/util/framework/content_panel.dart';
import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(title: '帮助', child: Text('todo 帮助')),
      ],
    );
  }
}
