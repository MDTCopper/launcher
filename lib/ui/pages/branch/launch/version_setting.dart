import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/ui/util/framework/content_panel.dart';
import 'package:copperlauncher_main/ui/util/framework/menu_bar.dart';
import 'package:copperlauncher_main/ui/util/framework/page_skeleton.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_dropdown_menu.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_list_tile.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/option_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:copperlauncher_main/util/io/file_reader.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';

import '../../../../util/format/byte_unit.dart';
import '../../../../util/system_info.dart';
import '../../../feature/images.dart';
import '../../../util/widget/percent_bar.dart';
import '../../../util/widget/setting_bar/input_setting_bar.dart';
import '../../../util/widget/setting_bar/slider_setting_bar.dart';

late Mindustry? _mindustry;

class VersionSettingPage extends StatefulWidget {
  const VersionSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _VersionSettingState();
}

class _VersionSettingState extends State<VersionSettingPage> {
  static int index = 0;

  late final List<Widget> pages = [_About(), _Setting(), _Mods(), _Package()];

  void moveTo(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _mindustry = args?['version'];
    return PageSkeleton(
      body: pages[index],
      menuBar: SideMenuBar(
        items: [
          MenuItem(
            leading: Icon(Icons.view_in_ar),
            title: Text('概况'),
            selected: index == 0,
            onTap: () => moveTo(0),
          ),
          MenuItem(
            leading: Icon(Icons.settings),
            title: Text('设置'),
            selected: index == 1,
            onTap: () => moveTo(1),
          ),
          MenuItem(
            leading: Icon(LineIcons.puzzlePiece, fontWeight: FontWeight.w500),
            title: Text('模组'),
            selected: index == 2,
            onTap: () => moveTo(2),
          ),
          MenuItem(
            leading: Icon(Icons.outbox_sharp),
            title: Text('资源打包'),
            selected: index == 3,
            onTap: () => moveTo(3),
          ),
        ],
      ),
    );
  }
}

class _About extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  Future<void> _openFolder(String folderPath) async {
    if (!(await Directory(folderPath).exists())) {
      folderPath = _mindustry!.dataPath!;
      if (!(await Directory(folderPath).exists())) {
        folderPath = _mindustry!.foldPath!;
      }
    }
    FileReader.openFolder(folderPath);
  }

  void _changeVersionTag() {}

  Widget _buildIconButton(IconData icon, String content, VoidCallback onTap) {
    return ReboundButton(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      child: Row(
        spacing: 4,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), Text(content)],
      ),
    );
  }

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
            _mindustry?.launcher == LauncherType.copper
                ? Images.copper
                : Images.mindustry,
            height: 64,
            fit: BoxFit.fitHeight,
          ),
          title: Text(_mindustry?.tag ?? 'null'),
          subtitle: Text(_mindustry?.releaseNum ?? 'null'),
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
                      _openFolder(_mindustry!.savesPath);
                    },
                  ),
                  ReboundIconButton(
                    icon: Icons.map_outlined,
                    content: '地图文件夹',
                    onTap: () {
                      _openFolder(_mindustry!.mapsPath);
                    },
                  ),
                  ReboundIconButton(
                    icon: Icons.paste,
                    content: '蓝图文件夹',
                    onTap: () {
                      _openFolder(_mindustry!.schematicsPath);
                    },
                  ),
                  ReboundIconButton(
                    icon: LineIcons.puzzlePiece,
                    content: '模组文件夹',
                    onTap: () {
                      _openFolder(_mindustry!.modsPath);
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
  bool? useGreatGPU;
  static double ram = 0.4;

  static bool? autoRam;
  String _formatRam(double ram) {
    return (ram / gb).toStringAsFixed(1);
  }

  int freeRam = 1;
  int totalRam = 1;

  late Timer _getRamTimer;
  void _getRam() async {
    freeRam = await SysInfo.getFreePhysicalMemory();
    totalRam = await SysInfo.getTotalPhysicalMemory();
    setState(() {});
    _getRamTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      freeRam = await SysInfo.getFreePhysicalMemory();
      setState(() {});
    });
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
              SwitchSettingBar(
                title: '版本隔离',
                value: _mindustry?.isolation ?? false,
                onChanged: (value) {
                  setState(() {
                    _mindustry?.isolation = value;
                    config.save();
                  });
                },
              ),
              OptionSettingBar<String?>(
                title: '游戏java',
                initialValue: null,
                hintText: '跟随全局',
                options: [
                  DropdownOption<String?>(value: null, label: '跟随全局'),
                  DropdownOption<String?>(value: 'auto', label: '自动选择合适的java'),
                  DropdownOption<String?>(value: 'v8', label: 'v8'),
                  DropdownOption<String?>(value: 'v9', label: 'v9'),
                  DropdownOption<String?>(value: 'v21', label: 'v21'),
                ],
                onSelect: (value) {},
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '游戏内存',
          child: Column(
            spacing: 8,
            children: [
              OptionSettingBar<bool?>(
                title: '内存分配',
                initialValue: autoRam,
                hintText: '跟随全局',
                options: [
                  DropdownOption<bool?>(value: null, label: '跟随全局'),
                  DropdownOption<bool?>(value: true, label: '自动分配'),
                  DropdownOption<bool?>(value: false, label: '自定义'),
                ],
                onSelect: (value) {
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
                    autoRam ?? true
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
              OptionSettingBar<bool?>(
                title: '使用高性能显卡',
                initialValue: useGreatGPU,
                hintText: '跟随全局',
                options: [
                  DropdownOption<bool?>(value: null, label: '跟随全局'),
                  DropdownOption<bool?>(value: true, label: '开'),
                  DropdownOption<bool?>(value: false, label: '关'),
                ],
                onSelect: (value) {
                  setState(() {
                    useGreatGPU = value;
                  });
                },
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
