import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/theme/app_theme.dart';
import 'package:copper_launcher/ui/util/widget/feature_button.dart';
import 'package:copper_launcher/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:flutter/material.dart';

import '../../util/framework/content_panel.dart';
import '../../util/widget/setting_bar/segment_setting_bar.dart';

class PersonalizationSettingPage extends StatefulWidget {
  const PersonalizationSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _PersonalizationSettingPageState();
}

class _PersonalizationSettingPageState
    extends State<PersonalizationSettingPage> {
  static Set<ThemeMode> selected = {};

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '主题',
          child: Column(
            spacing: 8,
            children: [
              Text('todo 主题色'),
              SizedBox(height: 20),
              SegmentSettingBar<ThemeMode>(
                title: '主题模式',
                segments: [
                  ReboundButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('深色模式'),
                  ),
                  ReboundButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.settings),
                    label: Text('跟随系统'),
                  ),
                  ReboundButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('浅色模式'),
                  ),
                ],
                //multiSelectionEnabled: true,
                onChange: (s) {
                  setState(() {
                    selected = s;
                    themeSwitchTo(s.first, ThemeColor.copper);
                  });
                },
                selected: selected,
              ),
              SwitchSettingBar(title: '特殊主题', value: false, onChanged: (_) {}),
            ],
          ),
        ),
        ContentPanelModule(
          title: '背景',
          child: Column(children: [Text('todo背景图片预设与自定义'), Text('背景图片不透明度')]),
        ),
        ContentPanelModule(
          title: '布局',
          child: Column(children: [Text('todo 软件UI显示'), Text('主页小工具布局设置')]),
        ),
      ],
    );
  }
}
