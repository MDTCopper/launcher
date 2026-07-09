import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/ui/shell/navigation_rail.dart';
import 'package:copperlauncher_main/ui/util/framework/content_panel.dart';
import 'package:copperlauncher_main/ui/util/route/sub_route_register.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_dropdown_menu.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_list_tile.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/option_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:copperlauncher_main/util/io/path_selector.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';

import '../../../../util/format/byte_unit.dart';
import '../../../../util/format/ram_rank_list.dart';
import '../../../../util/system_info.dart';
import '../../../components/rebound/rebound_checkbox.dart';
import '../../../feature/images.dart';
import '../../../util/widget/percent_bar.dart';
import '../../../util/widget/setting_bar/checkbox_setting_bar.dart';
import '../../../util/widget/setting_bar/input_setting_bar.dart';
import '../../../util/widget/setting_bar/slider_setting_bar.dart';

late Mindustry _mindustry;

////version_setting
const versionSettingPageRouteKey = '/version_setting';

class VersionSettingPage extends StatefulWidget {
  const VersionSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _VersionSettingState();
}

class _VersionSettingState extends State<VersionSettingPage> with SubRoute {
  static int index = 0;

  late final List<Widget> pages = [_About(), _Setting(), _Mods(), _Package()];

  void moveTo(int i) {
    if (mounted) setState(() => index = i);
  }

  @override
  void initState() {
    super.initState();
    register(versionSettingPageRouteKey, [
      SubRailSection<int>(
        label: '版本设置',
        items: [
          SubRailItem<int>(
            label: '概况',
            icon: Icons.view_in_ar,
            onTap: () => moveTo(0),
            selected: (_) => index == 0,
          ),
          SubRailItem<int>(
            label: '设置',
            icon: Icons.settings,
            onTap: () => moveTo(1),
            selected: (_) => index == 1,
          ),
          SubRailItem<int>(
            label: '模组',
            icon: LineIcons.puzzlePiece,
            onTap: () => moveTo(2),
            selected: (_) => index == 2,
          ),
          SubRailItem<int>(
            label: '资源打包',
            icon: Icons.outbox_sharp,
            onTap: () => moveTo(3),
            selected: (_) => index == 3,
          ),
        ],
      ),
    ]);

  }


  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _mindustry = args?['version'];
    return pages[index];
  }
}

class _About extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  Future<void> _openFolder(String folderPath) async {
    if (!(await Directory(folderPath).exists())) {
      folderPath = _mindustry.dataPath;
      if (!(await Directory(folderPath).exists())) {
        folderPath = _mindustry.foldPath;
      }
    }
    PathSelector.openFolder(folderPath);
  }

  void _changeVersionTag() {}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListContentPanel(
      items: [
        ReboundListTile(
          borderRadius: BorderRadius.circular(4),
          margin: EdgeInsets.all(8),
          itemSpacing: 8,
          elevation: 4,
          leading: Image.asset(
            _mindustry.launcher == LauncherType.copper
                ? Images.copper
                : Images.mindustry,
            height: 64,
            fit: BoxFit.fitHeight,
          ),
          title: Text(_mindustry.tag),
          subtitle: Text(_mindustry.releaseNum),
          onTap: _changeVersionTag, //todo 修改版本名称
        ),
        ContentPanelModule(
          title: '快捷方式',
          child: Column(
            spacing: 8,
            children: [
              Row(
                spacing: 16,
                children: [
                  ReboundIconButton(
                    icon: Icons.save,
                    content: '存档文件夹',
                    onTap: () {
                      _openFolder(_mindustry.savesPath);
                    },
                  ),
                  ReboundIconButton(
                    icon: Icons.map_outlined,
                    content: '地图文件夹',
                    onTap: () {
                      _openFolder(_mindustry.mapsPath);
                    },
                  ),
                  ReboundIconButton(
                    icon: Icons.paste,
                    content: '蓝图文件夹',
                    onTap: () {
                      _openFolder(_mindustry.schematicsPath);
                    },
                  ),
                  ReboundIconButton(
                    icon: LineIcons.puzzlePiece,
                    content: '模组文件夹',
                    onTap: () {
                      _openFolder(_mindustry.modsPath);
                    },
                  ),
                ],
              ),
              Row(
                spacing: 16,
                children: [
                  ReboundIconButton(
                    icon: Icons.file_copy,
                    content: '导出崩溃日志',
                    onTap: () {},
                  ),
                  ReboundIconButton(
                    icon: Icons.broken_image_outlined,
                    content: '查看崩溃日志',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '导入资源',
          child: Column(
            spacing: 8,
            children: [
              Row(
                spacing: 8,
                mainAxisSize: MainAxisSize.max,
                children: [
                  ReboundIconButton(
                    icon: Icons.layers_outlined,
                    content: '导入资源',
                    onTap: () {},
                  ),
                  ReboundIconButton(
                    icon: Icons.folder_outlined,
                    content: '批量导入',
                    onTap: () {},
                  ),
                ],
              ),

              if (Platform.isWindows || Platform.isLinux)
                Text(
                  '可以将资源或游戏本体拖动至copper快捷导入',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '导出资源',
          child: Column(
            spacing: 8,
            children: [
              Row(
                spacing: 8,
                mainAxisSize: MainAxisSize.max,
                children: [
                  ReboundIconButton(
                    icon: Icons.save,
                    content: '存档',
                    onTap: () {},
                  ),
                  ReboundIconButton(
                    icon: Icons.map_outlined,
                    content: '地图',
                    onTap: () {},
                  ),
                  ReboundIconButton(
                    icon: LineIcons.puzzlePiece,
                    content: '模组',
                    onTap: () {},
                  ),
                  ReboundIconButton(
                    icon: Icons.paste,
                    content: '蓝图',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Setting extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SettingState();
}

class _SettingState extends State<_Setting> {
  LaunchOptions get launchOptions => config.setting.launchOptions;

  bool get isolation => _mindustry.isolation;

  JavaOptions get javaOptions => launchOptions.javaOptions;

  String? get javaSelect {
    final java = _mindustry.java;
    final exist = javas.any((it) => it.path == java);
    if (exist) {
      return java;
    } else {
      _mindustry.java = null;
      return null;
    }
  }

  List<JavaInfo> get javas => javaOptions.javas;

  Memory get memory {
    if (autoMemory == null) return launchOptions.memory;
    return _mindustry.memory ??= launchOptions.memory;
  }

  bool? get autoMemory => _mindustry.autoMemory;

  bool? get useGoodGPU => _mindustry.useBetterGPU;

  String? get jvmParameter => _mindustry.jvmParameter;

  static Memory freeMemory = Memory(gb: 128);
  static Memory totalMemory = Memory(gb: 128);

  Timer? _getMemoryTimer;
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

  @override
  void initState() {
    super.initState();
    _getRam();
  }

  @override
  void dispose() {
    _getMemoryTimer?.cancel();
    super.dispose();
  }

  Widget _buildIsolationSettingBar() {
    return SwitchSettingBar(
      title: '游戏存档隔离',
      value: isolation,
      onChanged: (value) {
        setState(() {
          _mindustry.isolation = value;
          config.save();
        });
      },
    );
  }

  Widget _buildJavaSettingBar() {
    final list = [];

    final js =
        javas.toList()..sort((a, b) {
          if (a.version == null || b.version == null) return 0;
          return (b.version ?? 0) - (a.version ?? 0);
        });

    for (var it in js) {
      if (!it.isValid) continue;

      final label = it.version == null ? '未知版本' : 'Java ${it.version}';

      list.add(
        DropdownOption<String>(
          value: it.path,
          label: '$label ( "${it.path}" )',
        ),
      );
    }

    return Column(
      spacing: 8,
      children: [
        OptionSettingBar<String?>(
          title: '游戏Java',
          initialValue: javaSelect,
          hintText: '跟随系统',
          onSelect: (value) {
            setState(() {
              _mindustry.java = value;
              config.save();
            });
          },
          options: [
            DropdownOption<String?>(value: null, label: '跟随系统'),
            ...list,
          ],
        ),
      ],
    );
  }

  Widget _buildAutoMemorySettingBar() {
    return CheckboxSettingBar(
      title: '内存分配',
      options: [
        ReboundCheckbox(
          value: autoMemory == null,
          label: '跟随全局',
          onChange: (_) {
            setState(() {
              _mindustry.autoMemory = null;
              config.save();
            });
          },
        ),

        ReboundCheckbox(
          value: autoMemory == true,
          label: '自动分配',
          onChange: (_) {
            setState(() {
              _mindustry.autoMemory = true;
              config.save();
            });
          },
        ),
        ReboundCheckbox(
          value: autoMemory == false,
          label: '自定义',
          onChange: (_) {
            setState(() {
              _mindustry.autoMemory = false;
              config.save();
            });
          },
        ),
      ],
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
          final rank = (value * divisions).round();
          _mindustry.memory = Memory(
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
            children: [_buildIsolationSettingBar(), _buildJavaSettingBar()],
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
                child:
                    (autoMemory ?? true)
                        ? SizedBox()
                        : _buildMemorySettingBar(),
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
              CheckboxSettingBar(
                title: '使用高性能显卡',
                options: [
                  ReboundCheckbox(
                    value: useGoodGPU == null,
                    label: '跟随全局',
                    onChange: (_) {
                      setState(() {
                        _mindustry.useBetterGPU = null;
                        config.save();
                      });
                    },
                  ),
                  ReboundCheckbox(
                    value: useGoodGPU == false,
                    label: '关闭',
                    onChange: (_) {
                      setState(() {
                        _mindustry.useBetterGPU = false;
                        config.save();
                      });
                    },
                  ),
                  ReboundCheckbox(
                    value: useGoodGPU == true,
                    label: '开启',
                    onChange: (_) {
                      setState(() {
                        _mindustry.useBetterGPU = true;
                        config.save();
                      });
                    },
                  ),
                ],
              ),
              InputSettingBar(title: 'jvm虚拟机参数'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Mods extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _ModsState();
}

class _ModsState extends State<_Mods> {
  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [ContentPanelModule(title: '模组列表', child: Text('todo 模组列表及其管理'))],
    );
  }
}

class _Package extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _PackageState();
}

class _PackageState extends State<_Package> {
  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(title: '打包游戏为整合包', child: Text('todo 打包游戏为整合包')),
      ],
    );
  }
}
