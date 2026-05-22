import 'dart:async';
import 'dart:math';

import 'package:copperlauncher_main/ui/util/framework/page_skeleton.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_dropdown_menu.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:copperlauncher_main/ui/util/widget/percent_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/input_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/option_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:copperlauncher_main/util/format/byte_unit.dart';
import 'package:copperlauncher_main/util/system_info.dart';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../util/framework/content_panel.dart';
import '../util/framework/menu_bar.dart';
import '../util/widget/setting_bar/segment_setting_bar.dart';
import '../util/widget/setting_bar/slider_setting_bar.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingState();
}

class _SettingState extends State<SettingPage> {
  static int index = 0;

  final List<Widget> pageList = [
    LaunchSettingPage(),
    PersonalizationSettingPage(),
    OtherSettingPage(),
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PageSkeleton(
      body: pageList[index],
      menuBar: SideMenuBar(
        items: [
          MenuItem(
            selected: index == 0,
            onTap: () {
              setState(() {
                index = 0;
              });
            },
            leading: Icon(Icons.play_arrow_outlined),
            title: Text('启动'),
          ),
          MenuItem(
            selected: index == 1,
            onTap: () {
              setState(() {
                index = 1;
              });
            },
            leading: Icon(Icons.format_paint_outlined),
            title: Text('个性化'),
          ),
          MenuItem(
            selected: index == 2,
            onTap: () {
              setState(() {
                index = 2;
              });
            },
            leading: Icon(Icons.menu),
            title: Text('其他'),
          ),
        ],
      ),
    );
  }
}

class LaunchSettingPage extends StatefulWidget {
  const LaunchSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _LaunchSettingPageState();
}

class _LaunchSettingPageState extends State<LaunchSettingPage> {
  static VersionIsolation versionIsolation = VersionIsolation.none;
  static String javaSelect = 'auto';
  static GameWindowSizeSet gameWindowSizeSet = GameWindowSizeSet.gameDefault;
  static double ram = 0.4;

  static bool autoRam = false;
  static bool useGoodGPU = true;

  void _searchJava() {}

  void _addJava() {}

  int freeRam = 1;
  int totalRam = 1;

  late Timer _getRamTimer;
  void _getRam() async {
    freeRam = await SysInfo.getFreePhysicalMemory();
    totalRam = await SysInfo.getTotalPhysicalMemory();
    if (mounted) setState(() {});
    _getRamTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      freeRam = await SysInfo.getFreePhysicalMemory();
      if (mounted) setState(() {});
    });
  }

  String _formatRam(double ram) {
    return (ram / gb).toStringAsFixed(1);
  }

  void _routeToVersionSetting() {
    Navigator.pushNamed(
      context,
      '/version_setting',
      arguments: {
        'lead': '版本设置',
        'version': config.versionOptions.selectedVersion,
        'title': config.versionOptions.selectedVersion?.tag ?? 'null',
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _getRam();
  }

  @override
  void dispose() {
    _getRamTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '启动选项',
          child: Column(
            spacing: 8,
            children: [
              OptionSettingBar<VersionIsolation>(
                title: '默认版本隔离设置',
                initialValue: versionIsolation,
                onSelect: (value) {
                  setState(() {
                    versionIsolation = value;
                  });
                },
                options: [
                  DropdownOption<VersionIsolation>(
                    value: VersionIsolation.none,
                    label: '关闭隔离',
                  ),
                  DropdownOption<VersionIsolation>(
                    value: VersionIsolation.onlyBe,
                    label: '隔离非正式版',
                  ),
                  DropdownOption<VersionIsolation>(
                    value: VersionIsolation.onlyCopper,
                    label: '隔离CopperMod加载器',
                  ),
                  DropdownOption<VersionIsolation>(
                    value: VersionIsolation.all,
                    label: '隔离所有版本',
                  ),
                ],
              ),
              OptionSettingBar<GameWindowSizeSet>(
                title: '游戏窗口大小',
                initialValue: gameWindowSizeSet,
                onSelect: (value) {
                  setState(() {
                    gameWindowSizeSet = value;
                  });
                },
                options: [
                  DropdownOption<GameWindowSizeSet>(
                    value: GameWindowSizeSet.gameDefault,
                    label: '游戏默认',
                  ),
                  DropdownOption<GameWindowSizeSet>(
                    value: GameWindowSizeSet.maximize,
                    label: '最大化',
                  ),
                  DropdownOption<GameWindowSizeSet>(
                    value: GameWindowSizeSet.fullScreen,
                    label: '全屏',
                  ),
                  DropdownOption<GameWindowSizeSet>(
                    value: GameWindowSizeSet.custom,
                    label: '自定义',
                  ),
                ],
              ),
              //if (gameWindowSizeSet == GameWindowSizeSet.custom)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                alignment: Alignment.topCenter,
                child:
                    gameWindowSizeSet != GameWindowSizeSet.custom
                        ? SizedBox()
                        : Row(
                          children: [
                            SizedBox(width: 150),
                            Text('自定义窗口大小'),
                            SizedBox(width: 16),
                            Expanded(
                              child: Row(
                                spacing: 4,
                                children: [
                                  Expanded(child: OutlinedTextField()),
                                  Icon(
                                    Icons.close,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  Expanded(child: OutlinedTextField()),
                                ],
                              ),
                            ),
                          ],
                        ),
              ),
              OptionSettingBar<String>(
                title: '游戏java',
                initialValue: javaSelect,
                onSelect: (value) {
                  setState(() {
                    javaSelect = value;
                  });
                },
                options: [
                  DropdownOption<String>(value: 'auto', label: '自动选择合适的java'),
                  DropdownOption<String>(value: 'v8', label: 'v8'),
                  DropdownOption<String>(value: 'v9', label: 'v9'),
                  DropdownOption<String>(value: 'v21', label: 'v21'),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                spacing: 16,
                children: [
                  ReboundIconButton(
                    icon: Icons.folder_copy_outlined,
                    content: '手动添加',
                    onTap: () {},
                  ),
                  ReboundIconButton(
                    icon: Icons.search,
                    content: '自动搜索',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '游戏内存',
          child: Column(
            spacing: 8,
            children: [
              SwitchSettingBar(
                title: '内存自动分配',
                value: autoRam,
                onChanged: (value) {
                  setState(() {
                    autoRam = value;
                  });
                },
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                alignment: Alignment.topCenter,
                child:
                    autoRam
                        ? SizedBox()
                        : SliderSettingBar(
                          title:
                              '内存 ${(freeRam * ram / gb).toStringAsFixed(1)}GB',
                          label: '${(freeRam * ram / gb).toStringAsFixed(1)}GB',
                          onChanged: (value) {
                            setState(() {
                              ram = value;
                            });
                          },
                          value: ram,
                        ),
              ),
              PercentBar(
                total: totalRam.toDouble(),
                dataList: [
                  PercentBarData(value: (totalRam - freeRam).toDouble()),
                  PercentBarData(value: freeRam * min(ram, 1.0)),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前占用   ${_formatRam((totalRam - freeRam).toDouble())} / ${_formatRam(totalRam.toDouble())} GB (${((1 - freeRam / totalRam) * 100).toStringAsFixed(1)}%)', //todo内存占比描述和不均匀分配内存滑块
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '将为游戏分配   ${_formatRam(freeRam * min(ram, 1.0))}GB',
                ),
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '高级选项',
          child: Column(
            spacing: 8,
            children: [
              SwitchSettingBar(
                title: '使用高性能显卡',
                value: useGoodGPU,
                onChanged: (value) {
                  setState(() {
                    useGoodGPU = value;
                  });
                },
              ),
              InputSettingBar(title: 'jvm虚拟机参数'),
            ],
          ),
        ),
        SizedBox(height: 8),
        ReboundButton(
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          borderRadius: BorderRadius.circular(16),
          pressedScale: 0.9,
          elevation: 2,
          hoverElevation: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(Icons.swap_vert, size: 48),
              Text(
                '转到单独版本设置',
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ],
          ),
          onTap: () {
            _routeToVersionSetting();
          },
        ),
        SizedBox(height: 8),
      ],
    );
  }
}

class PersonalizationSettingPage extends StatefulWidget {
  const PersonalizationSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _PersonalizationSettingPageState();
}

class _PersonalizationSettingPageState
    extends State<PersonalizationSettingPage> {
  static Set<String> selected = {'选项1'};

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
              SegmentSettingBar<String>(
                title: '主题模式',
                segments: [
                  ReboundButtonSegment(
                    value: '选项1',
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('深色模式'),
                  ),
                  ReboundButtonSegment(
                    value: '选项2',
                    icon: Icon(Icons.settings),
                    label: Text('跟随系统'),
                  ),
                  ReboundButtonSegment(
                    value: '选项3',
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('浅色模式'),
                  ),
                ],
                //multiSelectionEnabled: true,
                onChange: (s) {
                  setState(() {
                    selected = s;
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
              OptionSettingBar(title: '资源获取优先级', options: [

              ]),
            ],
          ),
        ),
        ContentPanelModule(
          title: '存储',
          child: Column(
            children: [
              Text('todo 存储'),
              InputSettingBar(title: '默认存储路径'),
            ],
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
