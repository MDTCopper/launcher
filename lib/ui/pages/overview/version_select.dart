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
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
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

  /// 添加新目录：选一个游戏目录，命名后加入版本折叠
  Future<void> _addNewFold() async {
    final path = await PathSelector.selectDirectory();
    if (path == null || !mounted) return;

    final defaultTag = path.split(Platform.pathSeparator).last;
    final tag = await showAnimatedDialog<String>(
      context: context,
      pageBuilder: (_, _, _) => _NewFolderDialog(
        defaultTag: defaultTag,
        existingTags: _versionFolds.map((fold) => fold.tag).toSet(),
      ),
    );
    if (tag == null || !mounted) return;

    setState(() {
      _versionFolds.add(VersionFold(tag: tag, path: path, versions: []));
      _index = _versionFolds.length - 1;
    });
    await config.save();
    _updateView();
  }

  // void _addNewSort() {}

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

    return ListContentPanel(
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
              Text('没有找到任何游戏版本', style: theme.textTheme.displayMedium),

              Text('可以添加其他游戏目录或者直接下载游戏', style: theme.textTheme.bodyMedium),
              SizedBox(height: 2),
              ReboundButton(
                elevation: 2,
                hoverElevation: 4,
                margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
          NavigationTile(
            icon: Icon(Symbols.deployed_code_update),
            content: '导入本地游戏',
            collapse: collapse,
            onTap: () {},
          ),
        ],
      ),
      page: _buildVersionViewPage(_versionFolds[_index].versions),
    );
  }
}

/// 添加新目录：输入目录名称（tag）的对话框
class _NewFolderDialog extends StatefulWidget {
  final String defaultTag;
  final Set<String> existingTags;

  const _NewFolderDialog({
    required this.defaultTag,
    required this.existingTags,
  });

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  late final TextEditingController controller;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.defaultTag);
    error = _computeError(controller.text);
    controller.addListener(() {
      setState(() => error = _computeError(controller.text));
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String? _computeError(String tag) {
    final e = WindowsFileNameValidator.tagValidate(tag);
    if (e != null) return e;
    if (widget.existingTags.contains(tag)) return '名称已存在';
    return null;
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
                    '添加新目录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              OutlinedTextField(
                label: '目录名称',
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
