import 'package:copper_launcher/ui/util/framework/content_panel.dart';
import 'package:flutter/material.dart';

class PackageViewPage extends StatelessWidget {
  const PackageViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(title: '整合包', child: Text('todo 整合包浏览')),
      ],
    );
  }
}
