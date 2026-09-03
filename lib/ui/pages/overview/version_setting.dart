import 'dart:async';

import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/mindustry_settings.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/dialog/resource_importer.dart';

import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/components/input/tag_input_dialog.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';

import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/setting_bar/option_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:copper_launcher/util/format/path_format.dart';
import 'package:copper_launcher/util/math/range.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:line_icons/line_icons.dart';

import '../../../util/format/byte_unit.dart';
import '../../../util/format/ram_rank_list.dart';
import '../../../util/system_info.dart';
import '../../components/rebound/rebound_checkbox.dart';
import '../../feature/images.dart';
import '../../page_framwork/sub_navigation_state.dart';
import '../../components/percent_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/checkbox_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/input_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:path/path.dart' as p;

late Mindustry _mindustry;

////version_setting
const versionSettingPageRouteKey = '/version_setting';

class VersionSettingPage extends StatefulWidget {
  const VersionSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _VersionSettingState();
}

class _VersionSettingState extends State<VersionSettingPage>
    with SubNavigationCollapseListener {
  static int _index = 0;

  late final List<Widget> pages = [_About(), _Setting(), _Mods(), _Package()];

  void moveTo(int i) {
    if (mounted) setState(() => _index = i);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _mindustry = args?['version'];

    if (args?['index'] is int) {
      final index = args?['index'];
      final r = Range(0, pages.length);
      if (r.contains(index)) {
        _index = index;
      } else {
        debugPrint('页面参数index需要在 ${r.toString()} 内');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainPageLayout(
      navigationRail: PageNavigationRail(
        collapse: collapse,
        width: 137,
        items: [
          NavigationTile(
            icon: Icon(Icons.view_in_ar),
            content: '概况',
            onTap: () => moveTo(0),
            selected: _index == 0,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.settings),
            content: '设置',
            onTap: () => moveTo(1),
            selected: _index == 1,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(LineIcons.puzzlePiece),
            content: '模组',
            onTap: () => moveTo(2),
            selected: _index == 2,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.outbox_outlined),
            content: '资源打包',
            onTap: () => moveTo(3),
            selected: _index == 3,
            collapse: collapse,
          ),
        ],
      ),
      page: pages[_index],
    );
  }
}

class _About extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  /// 崩溃日志目录（游戏侧 默认数据目录/crashes）
  String get _crashesPath => _mindustry.crashesPath;

  /// 生成启动脚本：把当前版本的完整启动命令写成 .bat / .sh
  ///
  /// 内容对齐 [MindustryLauncher.start]：-Xmx 内存 + 隔离数据目录 +
  /// jvm 参数 + -jar，平台差异：Windows .bat（UTF-8 + chcp 65001），
  /// Linux/macOS .sh。保存位置由用户选择。
  Future<void> _generateLaunchScript() async {
    final target = await PathSelector.selectDirectory(
      confirmButtonText: '生成脚本到此',
    );
    if (target == null || !mounted) return;

    final launchOptions = config.setting.launchOptions;

    // 内存：单版本设置优先（autoMemory null = 跟随全局）
    final autoMemory = _mindustry.autoMemory ?? launchOptions.autoMemory;
    final memoryMb = autoMemory
        ? null
        : (_mindustry.memory ?? launchOptions.memory).mb;

    // jvm 参数：单版本优先，缺省用全局
    final jvmParameter =
        _mindustry.jvmParameter ?? launchOptions.javaOptions.jvmParameter;

    final args = <String>[
      if (memoryMb != null)
        '-Xmx${memoryMb}m'
      else
        '-Xmx512m',
      if (_mindustry.isolation) '-Dmindustry.data.dir=${_mindustry.dataPath}',
      ...jvmParameter.split(' ').where((arg) => arg.isNotEmpty),
      '-jar',
      _mindustry.jarPath,
    ];

    final isWindows = Platform.isWindows;
    final fileName = isWindows ? '启动游戏.bat' : '启动游戏.sh';
    final scriptFile = File(p.join(target, fileName));

    final script = isWindows
        ? _buildBatScript(args)
        : _buildShScript(args);

    try {
      await scriptFile.writeAsString(script);
      addNotice(
        icon: Icons.check_circle_outline,
        title: '脚本已生成',
        content: scriptFile.path,
      );
    } catch (e) {
      addNotice(icon: Icons.close, title: '生成失败', content: '无法写入启动脚本');
      debugPrint('生成启动脚本失败：$e');
    }
  }

  /// Windows .bat：UTF-8 + chcp 65001（兼容路径中文）+ 引号包裹含空格参数
  String _buildBatScript(List<String> args) {
    final argLine = args
        .map((arg) => arg.contains(' ') ? '"$arg"' : arg)
        .join(' ');
    return '''
@echo off
chcp 65001 >nul
java $argLine
pause
''';
  }

  /// Linux / macOS .sh
  String _buildShScript(List<String> args) {
    final argLine = args
        .map((arg) => arg.contains(' ') ? '"$arg"' : arg)
        .join(' ');
    return '#!/bin/sh\njava $argLine\n';
  }

  Future<void> _openFolder(String folderPath) async {
    if (!(await Directory(folderPath).exists())) {
      folderPath = _mindustry.dataPath;
      if (!(await Directory(folderPath).exists())) {
        folderPath = _mindustry.foldPath;
      }
    }
    PathSelector.openFolder(folderPath);
  }

  /// 导入资源：逐个识别 jar/mod/地图/蓝图 文件并导入
  Future<void> _importResources({required bool batch}) async {
    const typeGroups = [
      XTypeGroup(label: '支持的文件', extensions: ['jar', 'zip', 'msav', 'msch']),
    ];
    final paths = batch
        ? await PathSelector.selectFiles(acceptedTypeGroups: typeGroups)
        : [
            await PathSelector.selectFile(acceptedTypeGroups: typeGroups),
          ].whereType<String>().toList();
    if (paths.isEmpty) return;
    if (!mounted) return;
    showResourceImporter(paths);
  }

  /// 收藏 / 取消收藏当前版本
  void _toggleLike() {
    setState(() {
      _mindustry.like = !_mindustry.like;
      config.save();
    });
  }

  /// 删除当前版本：统一走 [VersionOptions.deleteVersion]（含共享 jar 检查）
  void _deleteVersion() {
    final tag = _mindustry.tag;
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '确定要删除 [$tag] ？',
      content: '[$tag] 游戏文件及其独立附属的存档，mod，整合包，蓝图，地图都会被删除！',
      action: () async {
        final deleted = await config.versionOptions.deleteVersion(_mindustry);
        if (!deleted) {
          addNotice(icon: Icons.close, title: '删除失败', content: '无法删除游戏文件');
          return;
        }
        await config.save();
        if (mounted) Navigator.pop(context); // 版本设置页关闭，回到版本列表
      },
    );
  }

  /// 查看崩溃日志：打开崩溃日志所在文件夹
  Future<void> _viewCrashLogs() async {
    if (!(await Directory(_crashesPath).exists())) {
      addNotice(
        icon: Icons.info_outline,
        title: '暂无崩溃日志',
        content: '崩溃日志目录尚不存在',
      );
      return;
    }
    PathSelector.openFolder(_crashesPath);
  }

  /// 导出崩溃日志：将崩溃日志目录复制到用户选择的位置
  Future<void> _exportCrashLogs() async {
    final source = Directory(_crashesPath);
    if (!(await source.exists())) {
      addNotice(
        icon: Icons.info_outline,
        title: '暂无崩溃日志',
        content: '崩溃日志目录尚不存在',
      );
      return;
    }
    final target = await PathSelector.selectDirectory(
      confirmButtonText: '导出到此',
    );
    if (target == null || !mounted) return;
    try {
      // 复制到目标下的 crashes 子目录，避免与目标目录内已有文件混在一起
      final targetCrashes = Directory(p.join(target, 'crashes'));
      if (!(await targetCrashes.exists())) {
        await targetCrashes.create(recursive: true);
      }
      await for (final entity in source.list()) {
        if (entity is File) {
          await entity.copy(
            p.join(targetCrashes.path, p.basename(entity.path)),
          );
        }
      }
      addNotice(
        icon: Icons.check_circle_outline,
        title: '导出成功',
        content: '已导出到 $target',
      );
    } catch (e) {
      addNotice(icon: Icons.close, title: '导出失败', content: '复制崩溃日志时出错');
      debugPrint('导出崩溃日志失败：$e');
    }
  }

  /// 导出资源目录：将某类资源（存档 / 地图 / 模组 / 蓝图）复制到用户选择的位置，
  /// 目标为所选目录下的同名子目录，避免与目标内已有文件混淆
  Future<void> _exportFolder(String sourcePath, String folderName) async {
    final source = Directory(sourcePath);
    if (!(await source.exists())) {
      addNotice(
        icon: Icons.info_outline,
        title: '暂无$folderName',
        content: '该版本还没有$folderName目录',
      );
      return;
    }
    final target = await PathSelector.selectDirectory(confirmButtonText: '导出');
    if (target == null || !mounted) return;
    try {
      final targetFolder = Directory(p.join(target, folderName));
      if (!(await targetFolder.exists())) {
        await targetFolder.create(recursive: true);
      }
      await for (final entity in source.list()) {
        if (entity is File) {
          await entity.copy(p.join(targetFolder.path, p.basename(entity.path)));
        }
      }
      addNotice(
        icon: Icons.check_circle_outline,
        title: '导出成功',
        content: '已导出到 $target',
      );
    } catch (e) {
      addNotice(icon: Icons.close, title: '导出失败', content: '复制$folderName时出错');
      debugPrint('导出$folderName失败：$e');
    }
  }

  Widget _buildVersionInfoPanel() {
    Widget buildInfo(String item, String content) {
      return Row(
        children: [
          Text(item),
          Expanded(child: SizedBox()),
          Text(content),
        ],
      );
    }

    return ContentPanelModule(
      title: '版本信息',
      child: Column(
        children: [
          HintLayer(
            hint: '点击重命名该版本',
            child: ReboundListTile(
              borderRadius: BorderRadius.circular(4),
              padding: EdgeInsets.all(4),
              elevation: 4,
              leading: Image.asset(
                _mindustry.launcher == LauncherType.copper
                    ? Images.copper
                    : Images.mindustry,
                height: 64,
                fit: BoxFit.fitHeight,
              ),
              title: Text(_mindustry.tag),
              subtitle: Text(_mindustry.release),
              onTap: _changeVersionTag, //点击修改版本名称
            ),
          ),
          const SizedBox(height: 4),
          buildInfo('添加时间', _mindustry.addTime.toString().split('.').first),
          buildInfo(
            '模组加载器',
            _mindustry.launcher == .mindustry ? '原版' : 'Copper Loader',
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              IconTextButton(
                icon: _mindustry.like ? Icons.star : Icons.star_outline,
                content: _mindustry.like ? '已收藏' : '未收藏',
                onTap: _toggleLike,
              ),
              //生成启动脚本
              if (isDesktop && kDebugMode)
                IconTextButton(
                  icon: Icons.build_circle,
                  content: '生成启动脚本',
                  onTap: _generateLaunchScript,
                ),
              IconTextButton(
                icon: Icons.delete,
                content: '删除版本',
                onTap: _deleteVersion,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _changeVersionTag() async {
    final tag = await showAnimatedDialog<String>(
      context: context,
      pageBuilder: (_, _, _) => TagInputDialog(
        title: '修改版本名称',
        label: '版本标签',
        defaultText: _mindustry.tag,
        validate: (tag) {
          final e = WindowsFileNameValidator.tagValidate(tag);
          if (e != null) return e;
          if (tag == _mindustry.tag) return null; // 原名不判重
          final fold = config.versionOptions.versionFolds.firstWhere(
            (fold) => fold.versions.contains(_mindustry),
            orElse: () => VersionFold(tag: '', path: '', versions: []),
          );
          if (fold.versions.any((v) => v != _mindustry && v.tag == tag)) {
            return '该版本名称已存在';
          }
          return null;
        },
      ),
    );
    if (tag == null || tag == _mindustry.tag || !mounted) return;

    final oldFolder = _mindustry.foldPath;
    final newFolder = p.join(_mindustry.path, tag);
    final folderExists = await Directory(oldFolder).exists();
    if (folderExists && oldFolder != newFolder) {
      final newFolderExists = await Directory(newFolder).exists();
      if (newFolderExists) {
        addNotice(icon: Icons.close, title: '重命名失败', content: '目标文件夹已存在');
        return;
      }
      try {
        await Directory(oldFolder).rename(newFolder);
      } catch (e) {
        addNotice(icon: Icons.close, title: '重命名失败', content: '无法重命名版本文件夹');
        debugPrint('重命名版本文件夹失败：$e');
        return;
      }
      // jar 在旧文件夹内时，jarPath 跟随新位置
      if (p.isWithin(oldFolder, _mindustry.jarPath)) {
        _mindustry.jarPath = p.join(
          newFolder,
          p.relative(_mindustry.jarPath, from: oldFolder),
        );
      }
    }

    setState(() => _mindustry.tag = tag);
    await config.save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListContentPanel(
      items: [
        _buildVersionInfoPanel(),

        ContentPanelModule(
          title: '快捷方式',
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text('快速打开对应文件夹', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: .start,
                children: [
                  IconTextButton(
                    width: 136,
                    icon: Icons.save,
                    content: '存档文件夹',
                    onTap: () {
                      _openFolder(_mindustry.savesPath);
                    },
                  ),
                  IconTextButton(
                    width: 136,
                    icon: Icons.map_outlined,
                    content: '地图文件夹',
                    onTap: () {
                      _openFolder(_mindustry.mapsPath);
                    },
                  ),
                  IconTextButton(
                    width: 136,
                    icon: Icons.paste,
                    content: '蓝图文件夹',
                    onTap: () {
                      _openFolder(_mindustry.schematicsPath);
                    },
                  ),
                  IconTextButton(
                    width: 136,
                    icon: LineIcons.puzzlePiece,
                    content: '模组文件夹',
                    onTap: () {
                      _openFolder(_mindustry.modsPath);
                    },
                  ),
                  IconTextButton(
                    width: 136,
                    icon: Icons.file_copy,
                    content: '导出崩溃日志',
                    onTap: _exportCrashLogs,
                  ),
                  IconTextButton(
                    width: 136,
                    icon: Icons.broken_image_outlined,
                    content: '查看崩溃日志',
                    onTap: _viewCrashLogs,
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
            crossAxisAlignment: .start,
            children: [
              Text('支持导入游戏地图、蓝图和模组', style: theme.textTheme.bodyMedium),
              Row(
                spacing: 8,
                mainAxisSize: MainAxisSize.max,
                children: [
                  IconTextButton(
                    icon: Icons.layers_outlined,
                    content: '导入资源',
                    onTap: () => _importResources(batch: false),
                  ),
                  IconTextButton(
                    icon: Icons.folder_outlined,
                    content: '批量导入',
                    onTap: () => _importResources(batch: true),
                  ),
                ],
              ),

              if (isDesktop)
                Center(
                  child: Text(
                    'tip:可以将资源或游戏本体拖动至copper快捷导入',
                    style: theme.textTheme.labelMedium,
                  ),
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
                  IconTextButton(
                    icon: Icons.save,
                    content: '存档',
                    onTap: () => _exportFolder(_mindustry.savesPath, 'saves'),
                  ),
                  IconTextButton(
                    icon: Icons.map_outlined,
                    content: '地图',
                    onTap: () => _exportFolder(_mindustry.mapsPath, 'maps'),
                  ),
                  IconTextButton(
                    icon: LineIcons.puzzlePiece,
                    content: '模组',
                    onTap: () => _exportFolder(_mindustry.modsPath, 'mods'),
                  ),
                  IconTextButton(
                    icon: Icons.paste,
                    content: '蓝图',
                    onTap: () =>
                        _exportFolder(_mindustry.schematicsPath, 'schematics'),
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

  /// jvm 参数输入框 controller：进入页面时以当前值为初值
  late final TextEditingController jvmParameterController =
      TextEditingController(text: _mindustry.jvmParameter ?? '');

  String _formatRam(double ram) {
    return (ram).toStringAsFixed(1);
  }

  /// jvm 参数输入完成后写回配置
  void _saveJvmParameter() {
    setState(() {
      _mindustry.jvmParameter = jvmParameterController.text;
      config.save();
    });
  }

  @override
  void initState() {
    super.initState();
    _getRam();
  }

  @override
  void dispose() {
    _getMemoryTimer?.cancel();
    jvmParameterController.dispose();
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

    final js = javas.toList()
      ..sort((a, b) {
        if (a.version == null || b.version == null) return 0;
        return (b.version ?? 0) - (a.version ?? 0);
      });

    for (var it in js) {
      if (!it.isValid) continue;

      final label = it.version == null ? '未知版本' : 'Java ${it.version}';

      list.add(
        DropdownOption<String>(
          value: it.path,
          label: '$label ( "${formatPathForWrap(it.path)}" )',
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
                child: (autoMemory ?? true)
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
              InputSettingBar(
                title: 'jvm虚拟机参数',
                controller: jvmParameterController,
                onEditingComplete: _saveJvmParameter,
              ),
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

/// 单个已安装模组条目
class _ModEntry {
  /// 模组文件实际路径（启用态为 mods/xx.jar，禁用态为 mods/xx.jar.disable）
  String filePath;

  /// 模组元数据（从 jar/zip 内 mod.json / mod.hjson 解析）
  final Mod mod;

  /// 是否启用（settings `mod-<name>-enabled`，缺省 true）
  bool enabled;

  _ModEntry({required this.filePath, required this.mod, required this.enabled});
}

class _ModsState extends State<_Mods> {
  List<_ModEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMods();
  }

  /// 模组目录：版本数据目录/mods
  String get _modsPath => _mindustry.modsPath;

  /// 扫描模组目录：jar/zip 为启用态，*.jar.disable / *.zip.disable 为禁用态
  Future<void> _loadMods() async {
    final entries = <_ModEntry>[];
    final dir = Directory(_modsPath);
    if (await dir.exists()) {
      // settings.bin 中的启用状态（键：mod-<internalName>-enabled）
      Map<String, bool> settingsStates = {};
      final settingsFile = File(_mindustry.settingPath);
      if (await settingsFile.exists()) {
        try {
          settingsStates =
              MindustrySettings.fromFile(settingsFile.path).modStates;
        } catch (e) {
          debugPrint('读取模组启用状态失败：$e');
        }
      }

      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        final disabled = name.endsWith('.disable');
        final baseName =
            disabled ? name.substring(0, name.length - '.disable'.length) : name;
        if (!baseName.endsWith('.jar') && !baseName.endsWith('.zip')) continue;

        final reader = await FileReader.fromPath(entity.path);
        final mod = reader.mod;
        if (mod == null) continue;

        // 启用状态：settings 键为准（缺省 true），禁用态文件名兜底为 false
        final enabled = settingsStates[mod.internalName] ?? !disabled;
        entries.add(_ModEntry(filePath: entity.path, mod: mod, enabled: enabled));
      }
    }
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  /// 切换模组启停：写 settings + 重命名文件（禁用 → 追加 .disable；启用 → 还原）
  ///
  /// 双保险：settings 控制游戏内状态；`.disable` 后缀让游戏 load() 直接
  /// 跳过该文件（官方 load 只扫 jar/zip，不识别 .disable），即使 settings
  /// 被改动也不会被加载
  Future<void> _toggleMod(_ModEntry entry, bool enabled) async {
    final file = File(entry.filePath);
    final modsDir = _modsPath;
    final baseName = p.basename(entry.filePath);

    // 计算目标文件名：启用 = 去掉 .disable；禁用 = 追加 .disable
    final targetName = enabled
        ? (baseName.endsWith('.disable')
            ? baseName.substring(0, baseName.length - '.disable'.length)
            : baseName)
        : '$baseName.disable';
    final targetPath = p.join(modsDir, targetName);

    if (entry.filePath != targetPath && await file.exists()) {
      try {
        await file.rename(targetPath);
        entry.filePath = targetPath;
      } catch (e) {
        addNotice(icon: Icons.close, title: '切换失败', content: '无法重命名模组文件');
        debugPrint('重命名模组失败：$e');
        return;
      }
    }

    // 写 settings.bin 启用状态并保存
    try {
      final settings = MindustrySettings.fromFile(_mindustry.settingPath);
      settings.setModEnabled(entry.mod.internalName, enabled);
      settings.saveAsync();
    } catch (e) {
      debugPrint('写入模组启用状态失败：$e');
    }

    setState(() => entry.enabled = enabled);
  }

  /// 删除模组：确认后删文件 + 移除 settings 记录
  void _deleteMod(_ModEntry entry) {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '确定要删除模组 [${entry.mod.name}] ？',
      content: '将删除模组文件及其启用状态记录',
      action: () async {
        final file = File(entry.filePath);
        try {
          if (await file.exists()) await file.delete();
          // 移除 settings 启用记录（恢复默认启用态）
          try {
            final settings = MindustrySettings.fromFile(_mindustry.settingPath);
            settings.setModEnabled(entry.mod.internalName, null);
            settings.saveAsync();
          } catch (e) {
            debugPrint('移除模组启用状态失败：$e');
          }
          if (mounted) {
            setState(() => _entries.remove(entry));
          }
        } catch (e) {
          addNotice(icon: Icons.close, title: '删除失败', content: '无法删除模组文件');
          debugPrint('删除模组失败：$e');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '模组列表 (${_entries.length})',
          child: _loading
              ? Text('加载中...')
              : _entries.isEmpty
                  ? Text('没有安装任何模组')
                  : Column(
                      spacing: 4,
                      children: [
                        for (final entry in _entries)
                          ReboundListTile(
                            padding: EdgeInsets.all(6),
                            borderRadius: BorderRadius.circular(4),
                            title: Text(entry.mod.name),
                            subtitle: Text(
                              '${entry.mod.author}  v${entry.mod.version}'
                              '${entry.enabled ? '' : '  (已禁用)'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ReboundButton(
                                  pressedScale: 0.9,
                                  borderRadius: BorderRadius.circular(4),
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    entry.enabled
                                        ? Icons.toggle_on
                                        : Icons.toggle_off,
                                    size: 28,
                                    color: entry.enabled
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : Theme.of(context).iconTheme.color,
                                  ),
                                  onTap: () =>
                                      _toggleMod(entry, !entry.enabled),
                                ),
                                const SizedBox(width: 4),
                                ReboundButton(
                                  pressedScale: 0.9,
                                  borderRadius: BorderRadius.circular(4),
                                  padding: EdgeInsets.all(6),
                                  child: const Icon(Icons.delete_outline),
                                  onTap: () => _deleteMod(entry),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
        ),
      ],
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
