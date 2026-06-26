import 'package:copperlauncher_main/ui/util/widget/setting_bar/input_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/option_setting_bar.dart';
import 'package:flutter/material.dart';

import '../../util/framework/content_panel.dart';
import '../../util/widget/setting_bar/slider_setting_bar.dart';

class OtherSettingPage extends StatefulWidget {
  const OtherSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _OtherSettingPage();
}

class _OtherSettingPage extends State<OtherSettingPage> {
  static double maxDownloadSpeed = 0.5;
  static double maxThread = 8;

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '下载',
          child: Column(
            spacing: 8,
            children: [
              SliderSettingBar(title: '最大下载速度', value: maxDownloadSpeed),
              SliderSettingBar(
                title: '最大线程数',
                label: maxThread.toStringAsFixed(0),
                value: maxThread,
                onChanged: (value) {
                  setState(() {
                    maxThread = value;
                  });
                },
                min: 1.0,
                max: 16.0,
                divisions: 15,
              ),
              // InputSettingBar(title: '自定义系统代理'),
              InputSettingBar(title: 'github访问Token'),
              OptionSettingBar(title: '资源获取优先级', options: []),
            ],
          ),
        ),
        ContentPanelModule(
          title: '存储',
          child: Column(
            children: [Text('todo 存储'), InputSettingBar(title: '默认存储路径')],
          ),
        ),
        ContentPanelModule(
          title: 'HTTP 代理',
          child: Column(children: [Text('todo 网络代理')]),
        ),
      ],
    );
  }
}
