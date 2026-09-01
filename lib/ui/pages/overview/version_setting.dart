import 'dart:async';

import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
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

  /// 删除当前版本：确认后删除 jar 本体并移除配置记录
  void _deleteVersion() {
    final tag = _mindustry.tag;
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '确定要删除 [$tag] ？',
      content: '[$tag] 游戏文件及其独立附属的存档，mod，整合包，蓝图，地图都会被删除！',
      action: () async {
        final jar = File(_mindustry.jarPath);
        if (await jar.exists()) {
          try {
            await jar.delete();
          } catch (e) {
            addNotice(icon: Icons.close, title: '删除失败', content: '无法删除游戏文件');
            debugPrint('删除失败：$e');
            return;
          }
        }
        // 从所有版本折叠中移除该版本记录
        for (final fold in config.versionOptions.versionFolds) {
          fold.versions.removeWhere((version) => version.id == _mindustry.id);
        }
        if (config.versionOptions.selectedVersionId == _mindustry.id) {
          config.versionOptions.selectedVersionId = null;
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
              //TODO 生成启动脚本
              if (isDesktop && kDebugMode)
                IconTextButton(
                  icon: Icons.build_circle,
                  content: '生成启动脚本',
                  onTap: () {},
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
