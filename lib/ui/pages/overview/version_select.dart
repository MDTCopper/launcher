import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_menu.dart';
import 'package:copper_launcher/ui/components/overlay_layer/menu_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';

import 'package:copper_launcher/ui/components/animation/animated_expansion.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';

import 'package:copper_launcher/ui/page_framwork/sub_navigation_state.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../feature/images.dart';

////version_select
const versionSelectPageRouteKey = '/version_select';

class VersionSelectPage extends StatefulWidget {
  const VersionSelectPage({super.key});
  @override
  State<StatefulWidget> createState() => _VersionSelectPageState();
}

//选择版本页面
class _VersionSelectPageState extends State<VersionSelectPage>
    with SubNavigationCollapseListener {
  final List<VersionFold> _versionFolds = config.versionOptions.versionFolds;

  static int _index = 0;

  void _delete(Mindustry version) {
    final index = _versionFolds[_index].versions.indexWhere(
      (v) => v == version,
    );
    if (index == -1) {
      debugPrint('没有找到配置信息');
      return;
    }
    final tag = version.tag;
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '确定要删除 [$tag] ？',
      content: '[$tag] 游戏文件及其独立附属的存档，mod，整合包，蓝图，地图都会被删除！',
      action: () async {
        final file = File(version.jarPath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (e) {
            debugPrint('删除失败');
            debugPrint(e.toString());
            return;
          }
        } else {
          debugPrint('游戏文件不存在,自动删除配置信息');
        }

        setState(() {
          //不管何种情况版本的配置信息肯定会被删除
          _versionFolds[_index].versions.removeAt(index);
          final selectedVersionId = config.versionOptions.selectedVersionId;
          if (selectedVersionId != null && version.id == selectedVersionId) {
            config.versionOptions.selectedVersionId = null;
          }
        });
        await config.save();
        _updateView();
      },
    );
  }

  /// 删除游戏目录（fold 项），移除其中的版本记录
  void _deleteFold(int index) {
    if (index < 0 || index >= _versionFolds.length) return;
    final fold = _versionFolds[index];
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '确定要删除目录 [${fold.tag}] ？',
      content: '将移除该目录下的所有版本记录',
      action: () async {
        setState(() {
          _versionFolds.removeAt(index);
          // 修正当前选中 fold 下标，避免越界
          if (_index >= _versionFolds.length) {
            _index = _versionFolds.isEmpty ? 0 : _versionFolds.length - 1;
          }
        });
        await config.save();
        _updateView();
      },
    );
  }

  void _select(Mindustry version) async {
    config.versionOptions.selectedVersion = version;
    Navigator.pop(context);
    await config.save();
  }

  //收藏
  void _collect(Mindustry version) async {
    final index = _versionFolds[_index].versions.indexWhere(
      (v) => v == version,
    );
    if (index == -1) return;
    _versionFolds[_index].versions[index].like =
        !_versionFolds[_index].versions[index].like;
    await config.save();
    _updateView();
  }

  void _updateView() {
    Navigator.pushReplacementNamed(
      context,
      '/version_select',
      arguments: {'lead': '版本选择'},
    );
  }

  void _popToSettingOf(Mindustry version) {
    final index = _versionFolds[_index].versions.indexWhere(
      (v) => v == version,
    );
    if (index == -1) return;
    Navigator.pushNamed(
      context,
      '/version_setting',
      arguments: {'lead': '版本设置', 'version': version, 'title': version.tag},
    );
  }

  /// 添加新目录：选一个游戏目录，命名后加入版本折叠；目录下已有游戏版本会被自动扫描进去
  Future<void> _addNewFold() async {
    final path = await PathSelector.selectDirectory();
    if (path == null || !mounted) return;

    // 检查是否为存在的文件夹
    if (!await Directory(path).exists()) {
      if (mounted) {
        addNotice(icon: Icons.close, title: '添加失败', content: '所选路径不是存在的文件夹');
      }
      return;
    }

    final defaultTag = path.split(Platform.pathSeparator).last;
    if (!mounted) return;
    final tag = await showAnimatedDialog<String>(
      context: context,
      pageBuilder: (_, _, _) => _TagInputDialog(
        title: '添加新目录',
        label: '目录名称',
        defaultText: defaultTag,
        validate: (tag) {
          final e = WindowsFileNameValidator.tagValidate(tag);
          if (e != null) return e;
          if (_versionFolds.any((fold) => fold.tag == tag)) return '名称已存在';
          return null;
        },
      ),
    );
    if (tag == null || !mounted) return;

    // 扫描目录内可能的游戏版本，作为新目录的初始版本
    final scanned = await _scanGameVersions(path);
    if (!mounted) return;
    Log.add(.info, '目录[$tag] 扫描到 ${scanned.length} 个游戏版本');
    addNotice(content: '在目录中找到${scanned.length} 个游戏版本');
    setState(() {
      _versionFolds.add(VersionFold(tag: tag, path: path, versions: scanned));
      _index = _versionFolds.length - 1;
    });
    await config.save();
    _updateView();
  }

  /// 扫描目录内可能的游戏版本：直接 .jar 文件与子目录内的 .jar（识别为 mindustry 的加入列表）
  Future<List<Mindustry>> _scanGameVersions(String folderPath) async {
    final result = <Mindustry>[];
    final root = Directory(folderPath);
    if (!await root.exists()) return result;

    await for (final entity in root.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.jar')) {
        final version = await _recognizeJar(
          folderPath,
          entity.path,
          p.basenameWithoutExtension(entity.path),
        );
        if (version != null) result.add(version);
        continue;
      }
      if (entity is Directory) {
        await for (final sub in entity.list()) {
          if (sub is File && sub.path.toLowerCase().endsWith('.jar')) {
            final version = await _recognizeJar(
              folderPath,
              sub.path,
              p.basenameWithoutExtension(entity.path),
            );
            if (version != null) result.add(version);
            break;
          }
        }
      }
    }
    return result;
  }

  /// 用 [FileReader] 识别 jar：是 mindustry 则构造版本（tag 去重）
  Future<Mindustry?> _recognizeJar(
    String folderPath,
    String jarPath,
    String tag,
  ) async {
    final reader = await FileReader.fromPath(jarPath);
    final meta = reader.mindustry;
    if (reader.type != ResourceType.mindustry || meta == null) {
      return null;
    }

    final isBe = meta.type == 'bleeding-edge';
    final name = !isBe
        ? 'v${meta.version} Build ${meta.build}'
        : 'Build ${meta.build}';

    return Mindustry(
      id: const Uuid().v4(),
      launcher: LauncherType.mindustry,
      tag: _uniqueTag(tag),
      jarPath: jarPath,
      isBe: isBe,
      path: folderPath,
      name: name,
      releaseNum: isBe ? meta.version : 'v${meta.version}',
      addTime: DateTime.now(),
      isolation: false,
    );
  }

  /// 保证 tag 不与已有目录 / 版本重名（重名时追加序号）
  String _uniqueTag(String tag) {
    final used =
        _versionFolds
            .expand((fold) => fold.versions)
            .map((version) => version.tag)
            .toSet()
          ..addAll(_versionFolds.map((fold) => fold.tag));
    var candidate = tag;
    var i = 1;
    while (used.contains(candidate)) {
      candidate = '$tag${i++}';
    }
    return candidate;
  }

  /// 导入本地游戏：选一个 Mindustry jar，识别后作为版本加入当前目录（桌面端）
  Future<void> _importLocalGame() async {
    if (!isDesktop) return;

    Log.add(.info, '导入外部游戏文件');

    final path = await PathSelector.selectFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Mindustry', extensions: ['jar', 'zip']),
      ],
    );
    if (path == null || !mounted) return;

    final reader = await FileReader.fromPath(path);
    if (!mounted) return;
    final meta = reader.mindustry;
    if (reader.type != ResourceType.mindustry || meta == null) {
      addNotice(
        icon: Icons.close,
        title: '类型错误',
        content: '该文件不是有效的 Mindustry 游戏文件，请确认文件存在',
      );
      Log.add(.warning, '类型错误:文件[$path]不是有效的 Mindustry 游戏文件');
      return;
    }

    final isBe = meta.type == 'bleeding-edge';
    final name = !isBe
        ? 'v${meta.version} Build ${meta.build}'
        : 'Build ${meta.build}';

    final fold = _versionFolds[_index];
    final versionTags = _versionFolds
        .expand((fold) => fold.versions)
        .map((version) => version.tag)
        .toSet();

    final tag = await showAnimatedDialog<String>(
      context: context,
      pageBuilder: (_, _, _) => _TagInputDialog(
        title: '导入游戏',
        label: '版本标签',
        defaultText: name,
        validate: (tag) {
          final e = WindowsFileNameValidator.tagValidate(tag);
          if (e != null) return e;
          if (versionTags.contains(tag)) return '名称已存在';
          return null;
        },
      ),
    );
    if (tag == null || !mounted) return;

    // 拷贝 jar 到当前目录的版本文件夹下（版本自包含）
    final jarPath = await reader.importTo(p.join(fold.path, tag));
    if (jarPath == null) {
      addNotice(icon: Icons.close, title: '导入失败', content: '无法写入目标目录，请选择合适的路径');
      Log.add(.warning, '导入失败:文件[$path]无法写入目标目录[$jarPath]');
      return;
    }

    final mindustry = Mindustry(
      id: const Uuid().v4(),
      launcher: LauncherType.mindustry, //TODO 等待后续接入Copper Loader
      tag: tag,
      jarPath: jarPath,
      isBe: isBe,
      path: fold.path,
      name: name,
      releaseNum: isBe ? meta.version : 'v${meta.version}',
      addTime: DateTime.now(),
      isolation: false,
    );
    if (mounted) setState(() => fold.versions.add(mindustry));
    config.save();
    Log.add(.info, '导入完成:$mindustry');
    if (mounted) _updateView();
  }

  Widget _buildVersionTile(Mindustry version) {
    final theme = Theme.of(context);

    final tile = ReboundListTile(
      padding: EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(4),
      leading: Image.asset(
        version.launcher == LauncherType.copper
            ? Images.copper
            : Images.mindustry,
        scale: 0.8,
        height: 48,
      ),
      title: Text(version.tag, style: theme.textTheme.bodyLarge),
      subtitle: Text(version.name, style: theme.textTheme.bodyMedium),
      onTap: () => _select(version),
    );

    // 右键 / 长按 + 左滑 组合菜单：删除 / 收藏 / 设置
    return ActionMenu(
      menuBuilder: (_, controller) => [
        MenuButton(
          icon: Icons.delete_outline,
          label: '删除',
          danger: true,
          onTap: () {
            controller.dismiss();
            _delete(version);
          },
        ),
        MenuButton(
          icon: version.like ? Icons.favorite : Icons.favorite_border_rounded,
          label: version.like ? '取消收藏' : '收藏',
          onTap: () {
            controller.dismiss();
            _collect(version);
          },
        ),
        MenuButton(
          icon: Icons.settings,
          label: '设置',
          onTap: () {
            controller.dismiss();
            _popToSettingOf(version);
          },
        ),
      ],
      actions: [
        SlideActionButton(
          icon: Icon(Icons.delete_outline),
          label: '删除',
          onTap: () => _delete(version),
        ),
        const SizedBox(width: 4),
        SlideActionButton(
          icon: Icon(
            version.like ? Icons.favorite : Icons.favorite_border_rounded,
            color: version.like ? Colors.red : null,
          ),
          label: version.like ? '已收藏' : '收藏',
          onTap: () => _collect(version),
        ),
        const SizedBox(width: 4),
        SlideActionButton(
          icon: Icon(Icons.settings),
          label: '设置',
          onTap: () => _popToSettingOf(version),
        ),
      ],
      child: tile,
    );
  }

  Widget _buildVersionViewPage(List<Mindustry> versions) {
    versions.sort((a, b) => -a.addTime.compareTo(b.addTime));
    final List<Widget> likes = [];
    final List<Widget> mindustrys = [];
    final List<Widget> coppers = [];
    final List<Widget> betas = [];

    for (int i = 0; i < versions.length; i++) {
      final version = versions[i];

      final child = _buildVersionTile(version);

      if (version.like) likes.add(child);

      if (version.launcher == LauncherType.copper) {
        coppers.add(child);
        continue;
      }
      if (version.isBe) {
        betas.add(child);
        continue;
      }
      mindustrys.add(child);
    }

    if (likes.isEmpty &&
        mindustrys.isEmpty &&
        coppers.isEmpty &&
        betas.isEmpty) {
      return KeyedSubtree(
        key: Key(_versionFolds[_index].path),
        child: _buildEmptyPage(),
      );
    }

    return KeyedSubtree(
      key: Key(_versionFolds[_index].path),
      child: ListContentPanel(
        delay: 250,
        items: [
          if (likes.isNotEmpty)
            AnimatedExpansion(
              initExpanded: true,
              title: Text('收藏(${likes.length})'),
              children: likes,
            ),
          if (mindustrys.isNotEmpty)
            AnimatedExpansion(
              initExpanded: likes.isEmpty,
              title: Text('原版(${mindustrys.length})'),
              children: mindustrys,
            ),
          if (coppers.isNotEmpty)
            AnimatedExpansion(
              title: Text('Copper(${coppers.length})'),
              children: coppers,
            ),
          if (betas.isNotEmpty)
            AnimatedExpansion(
              title: Text('预览版(${betas.length})'),
              children: betas,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyPage() {
    final theme = Theme.of(context);
    return _EmptyPageEntrance(
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            spacing: 4,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('~(～￣▽￣)～', style: theme.textTheme.bodyLarge),
              Text('没有找到任何游戏版本', style: theme.textTheme.headlineLarge),

              Text('可以添加其他游戏目录或者直接下载游戏', style: theme.textTheme.labelLarge),
              SizedBox(height: 2),
              ReboundButton(
                elevation: 2,
                hoverElevation: 4,
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                onTap: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/mindustry_download',
                    (_) => false,
                    arguments: {'lead': 'Mindustry'},
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Icon(Icons.download, color: theme.colorScheme.onSurface),
                    Text(
                      '下载游戏',
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainPageLayout(
      navigationRail: PageNavigationRail(
        collapseDuration: animationDuration * 1.5,
        collapse: collapse,
        width: 230,
        items: [
          ..._versionFolds.map((fold) {
            final index = _versionFolds.indexOf(fold);
            final tile = NavigationTile(
              icon: Icon(Icons.folder_outlined),
              content: '${fold.tag} (${fold.versions.length})',
              lable: fold.path,
              selected: index == _index,
              collapse: collapse,
              onTap: () {
                setState(() => _index = index);
              },
            );
            // 侧边栏项：右键 / 长按 + 左滑 → 可删除该目录
            return ActionMenu(
              enableSwipe:
                  !config.setting.personalizationOptions.subNavigationCollapse,
              menuBuilder: (_, controller) => [
                MenuButton(
                  icon: Icons.delete_outline,
                  label: '删除',
                  danger: true,
                  onTap: () {
                    controller.dismiss();
                    _deleteFold(index);
                  },
                ),
              ],
              actions: [
                const SizedBox(width: 2),
                SlideActionButton(
                  icon: Icon(Icons.delete_outline),
                  backgroundColor: Colors.transparent,
                  onTap: () => _deleteFold(index),
                ),
              ],
              child: tile,
            );
          }),
        ],
        itemsAtBottom: [
          NavigationTile(
            icon: Icon(Icons.create_new_folder_outlined),
            content: '添加新目录',
            collapse: collapse,
            onTap: _addNewFold,
          ),
          if (isDesktop)
            NavigationTile(
              icon: Icon(Symbols.deployed_code_update),
              content: '导入本地游戏',
              collapse: collapse,
              onTap: _importLocalGame,
            ),
        ],
      ),
      page: _buildVersionViewPage(_versionFolds[_index].versions),
    );
  }
}

/// 通用标签输入对话框：title / label / 默认值 / 校验器（返回错误文案或 null）
class _TagInputDialog extends StatefulWidget {
  final String title;
  final String label;
  final String defaultText;
  final String? Function(String tag) validate;

  const _TagInputDialog({
    required this.title,
    required this.label,
    required this.defaultText,
    required this.validate,
  });

  @override
  State<_TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<_TagInputDialog> {
  late final TextEditingController controller;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.defaultText);
    error = widget.validate(controller.text);
    controller.addListener(() {
      setState(() => error = widget.validate(controller.text));
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black,
        child: Container(
          width: 400,
          padding: EdgeInsets.all(8),
          constraints: BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                spacing: 8,
                children: [
                  ReboundButton(
                    child: Icon(Icons.arrow_back_ios_new),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              OutlinedTextField(
                label: widget.label,
                error: error,
                controller: controller,
              ),
              IconTextButton(
                icon: Icons.check,
                content: '确定',
                onTap: () {
                  if (error != null) return;
                  Navigator.of(context).pop(controller.text);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空页面入场动画：淡入 + 缩放浮现
class _EmptyPageEntrance extends StatefulWidget {
  final Widget child;

  const _EmptyPageEntrance({required this.child});

  @override
  State<_EmptyPageEntrance> createState() => _EmptyPageEntranceState();
}

class _EmptyPageEntranceState extends State<_EmptyPageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> fade;
  late final Animation<double> scale;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: animationDuration);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutBack,
    );
    fade = curved;
    scale = Tween<double>(begin: 0.6, end: 1.0).animate(curved);
    Future.delayed(const Duration(milliseconds: 200)).whenComplete(() {
      controller.forward();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: scale, child: widget.child),
    );
  }
}
