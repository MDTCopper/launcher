import 'package:copper_launcher/ui/util/framework/content_panel.dart';
import 'package:flutter/material.dart';

class MapViewPage extends StatelessWidget {
  const MapViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(title: '地图', child: Text('todo 地图浏览')),
      ],
    );
  }
}
