import 'dart:async';
import 'dart:math';

import 'package:copperlauncher_main/ui/util/framework/page_skeleton.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_dropdown_menu.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:copperlauncher_main/ui/util/widget/percent_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/rebound_checkbox.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/checkbox_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/input_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/option_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:copperlauncher_main/util/format/byte_unit.dart';
import 'package:copperlauncher_main/util/system_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../util/format/ram_rank_list.dart';
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
    InnerSettingPage(),
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
            onTap:
                () => setState(() {
                  index = 1;
                }),
            leading: Icon(Icons.gamepad),
            title: Text('游戏内'),
          ),
          MenuItem(
            selected: index == 2,
            onTap: () {
              setState(() {
                index = 2;
              });
            },
            leading: Icon(Icons.format_paint_outlined),
            title: Text('个性化'),
          ),
          MenuItem(
            selected: index == 3,
            onTap: () {
              setState(() {
                index = 3;
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
  LaunchOptions get launchOptions => config.setting.launchOptions;

  Set<VersionIsolation> get versionIsolationSet =>
      launchOptions.versionIsolationSet;

  GameWindowSizeSet get gameWindowSizeSet => launchOptions.gameWindowSizeSet;

  WindowSize get customWindowSize => launchOptions.customWindowSize;

  String get javaSelect => launchOptions.javaOptions.selectedJava;

  Memory get memory => launchOptions.memory;

  bool get autoMemory => launchOptions.autoMemory;

  bool get useGoodGPU => launchOptions.javaOptions.useBetterGPU;

  late final TextEditingController widthController;
  late final TextEditingController heightController;
  Memory freeMemory = Memory(gb: 128);
  Memory totalMemory = Memory(gb: 128);

  late Timer _getMemoryTimer;
  void _getRam() async {
    final free = await SysInfo.getFreePhysicalMemory();
    freeMemory = Memory(bytes: free);
    final total = await SysInfo.getTotalPhysicalMemory();
    totalMemory = Memory(bytes: total);
    if (mounted) setState(() {});
    _getMemoryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final free = await SysInfo.getFreePhysicalMemory();
      freeMemory = Memory(bytes: free);
      if (mounted) setState(() {});
    });
  }

  String _formatRam(double ram) {
    return (ram).toStringAsFixed(1);
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

  void _searchJava() {}

  void _addJava() {}

  @override
  void initState() {
    super.initState();
    _getRam();
    final size = launchOptions.customWindowSize;
    widthController = TextEditingController(text: '${size.width}')
      ..addListener(() => setState(() {}));
    heightController = TextEditingController(text: '${size.height}')
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _getMemoryTimer.cancel();
    widthController.dispose();
    heightController.dispose();
    super.dispose();
  }

  Widget _buildDefaultVersionIsolationSettingBar() {
    final theme = Theme.of(context);
    return CheckboxSettingBar(
      title: '游戏默认隔离设置',
      options: [
        ReboundCheckbox(
          value: versionIsolationSet.isEmpty,
          label: '无隔离',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.clear();
              } else {
                launchOptions.versionIsolationSet.addAll(
                  VersionIsolation.values,
                );
              }
              config.save();
            });
          },
        ),
        SizedBox(
          width: 1,
          height: 16,
          child: ColoredBox(color: theme.colorScheme.secondary),
        ),
        ReboundCheckbox(
          value: versionIsolationSet.contains(VersionIsolation.be),
          label: '测试版',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.add(VersionIsolation.be);
              } else {
                launchOptions.versionIsolationSet.remove(VersionIsolation.be);
              }
              config.save();
            });
          },
        ),
        ReboundCheckbox(
          value: launchOptions.versionIsolationSet.contains(
            VersionIsolation.mindustry,
          ),
          label: '正式版',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.add(
                  VersionIsolation.mindustry,
                );
              } else {
                launchOptions.versionIsolationSet.remove(
                  VersionIsolation.mindustry,
                );
              }
              config.save();
            });
          },
        ),
        ReboundCheckbox(
          value: launchOptions.versionIsolationSet.contains(
            VersionIsolation.copper,
          ),
          label: 'Copper',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.add(VersionIsolation.copper);
              } else {
                launchOptions.versionIsolationSet.remove(
                  VersionIsolation.copper,
                );
              }
              config.save();
            });
          },
        ),
      ],
    );
  }

  Widget _buildGameWindowSizeSettingBar() {
    Widget buildCustomWinSizeSetting() {
      if (gameWindowSizeSet != GameWindowSizeSet.custom) {
        return SizedBox();
      }
      final width = int.tryParse(widthController.text) ?? 0;
      final height = int.tryParse(heightController.text) ?? 0;
      final showB =
          width != customWindowSize.width || height != customWindowSize.height;
      Widget buildButton() {
        if (!showB) return SizedBox();
        return Row(
          spacing: 8,
          children: [
            SizedBox(width: 8),
            ReboundIconButton(
              icon: Icons.check,
              margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              content: '保存',
              onTap: () {
                setState(() {
                  if (width <= 320 || height <= 160) {
                    return; //todo 窗口过小警告
                  }
                  final winSize = WindowSize(width, height);
                  launchOptions.customWindowSize = winSize;
                  config.save();
                });
              },
            ),
            ReboundIconButton(
              icon: Icons.close,
              margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              content: '取消',
              onTap: () {
                setState(() {
                  widthController.text = customWindowSize.width.toString();
                  heightController.text = customWindowSize.height.toString();
                });
              },
            ),
          ],
        );
      }

      return Column(
        children: [
          SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 150, child: Text('自定义窗口大小')),
              Expanded(
                child: Row(
                  spacing: 4,
                  children: [
                    Expanded(
                      child: OutlinedTextField(
                        controller: widthController,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(5),
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    Expanded(
                      child: OutlinedTextField(
                        controller: heightController,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(5),
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.ease,
                child: buildButton(),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        OptionSettingBar<GameWindowSizeSet>(
          title: '游戏窗口大小',
          initialValue: gameWindowSizeSet,
          onSelect: (value) {
            setState(() {
              launchOptions.gameWindowSizeSet = value;
              config.save();
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
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.ease,
          alignment: Alignment.topCenter,
          child: buildCustomWinSizeSetting(),
        ),
      ],
    );
  }

  Widget _buildJavaSettingBar() {
    return Column(
      spacing: 8,
      children: [
        OptionSettingBar<String>(
          title: '游戏java',
          initialValue: javaSelect,
          onSelect: (value) {
            setState(() {
              launchOptions.javaOptions.selectedJava = value;
              config.save();
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
          mainAxisAlignment: MainAxisAlignment.end,
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
    );
  }

  Widget _buildAutoMemorySettingBar() {
    return SwitchSettingBar(
      title: '内存自动分配',
      value: autoMemory,
      onChanged: (value) {
        setState(() {
          launchOptions.autoMemory = value;
          config.save();
        });
      },
    );
  }

  Timer? saveTimer;

  Widget _buildMemorySettingBar() {
    var divisions =
        memoryRankList.indexWhere((element) => element >= totalMemory.inGB) - 1;

    if (divisions < 0) divisions = memoryRankList.length;

    final memoryRank = memoryRankList.indexWhere(
      (element) => element >= memory.inGB,
    );

    final memoryValue = memoryRank / divisions;

    return SliderSettingBar(
      title: '内存 ${(memory.inGB).toStringAsFixed(1)}GB',
      label: '${(memory.inGB).toStringAsFixed(1)}GB',
      divisions: divisions,
      onChanged: (value) {
        setState(() {
          final rank = (value * divisions).toInt();
          launchOptions.memory = Memory(
            bytes: (memoryRankList[rank] * gb).toInt(),
          );
          saveTimer?.cancel();
          saveTimer = Timer(const Duration(seconds: 1), () {
            config.save();
          });
        });
      },
      value: memoryValue,
    );
  }

  Widget _buildMemoryInfo() {
    final free = _formatRam(freeMemory.inGB);
    final total = _formatRam(totalMemory.inGB);
    final used = _formatRam((totalMemory - freeMemory).inGB);
    final allocation = _formatRam(memory.inGB);
    final occupy = ((1 - freeMemory.bytes / totalMemory.bytes) * 100)
        .toStringAsFixed(1);

    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PercentBar(
          total: totalMemory.bytes.toDouble(),
          dataList: [
            PercentBarData(value: (totalMemory - freeMemory).bytes.toDouble()),
            PercentBarData(
              value: min(memory.bytes.toDouble(), freeMemory.bytes.toDouble()),
            ),
          ],
        ),

        Row(
          children: [
            Text('当前占用  $used / $total GB ($occupy%)'),
            Expanded(child: SizedBox()),
            AnimatedOpacity(
              opacity: memory > freeMemory ? 1 : 0,
              curve: Curves.ease,
              duration: const Duration(milliseconds: 200),
              child: Text('( 当前可用内存仅 $free GB )'),
            ),
          ],
        ),
        Text('将为游戏分配   $allocation GB '),
      ],
    );
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
              _buildDefaultVersionIsolationSettingBar(),

              _buildGameWindowSizeSettingBar(),

              _buildJavaSettingBar(),
              //if (gameWindowSizeSet == GameWindowSizeSet.custom)
            ],
          ),
        ),
        ContentPanelModule(
          title: '游戏内存',
          child: Column(
            spacing: 8,
            children: [
              _buildAutoMemorySettingBar(),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                alignment: Alignment.topCenter,
                child: autoMemory ? SizedBox() : _buildMemorySettingBar(),
              ),
              _buildMemoryInfo(),
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
                    launchOptions.javaOptions.useBetterGPU = value;
                    config.save();
                  });
                },
              ),
              InputSettingBar(title: 'jvm虚拟机参数'),
            ],
          ),
        ),
        SizedBox(height: 8),
        if (config.versionOptions.selectedVersion != null)
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

class InnerSettingPage extends StatefulWidget {
  const InnerSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _InnerSettingPageState();
}

class _InnerSettingPageState extends State<InnerSettingPage> {
  @override
  Widget build(BuildContext context) {
    return ListContentPanel(items: [Text('todo 游戏内设置')]);
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
