import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/ui/util/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/util/framework/content_panel.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/ui/util/route/sub_route_register.dart';
import 'package:copper_launcher/ui/util/widget/animated_expansion.dart';
import 'package:copper_launcher/ui/util/widget/feature_button.dart';
import 'package:copper_launcher/ui/util/widget/feature_list_tile.dart';
import 'package:flutter/material.dart';

import '../../../feature/images.dart';
import '../../../shell/navigation_rail.dart';

////version_select
const versionSelectPageRouteKey = '/version_select';

class VersionSelectPage extends StatefulWidget {
  const VersionSelectPage({super.key});
  @override
  State<StatefulWidget> createState() => _VersionSelectPageState();
}

//选择版本页面
class _VersionSelectPageState extends State<VersionSelectPage>
    with SubRoute, RouteAware {
  final List<VersionFold> _versionFolds = config.versionOptions.versionFolds;

  static int _index = 0;

  @override
  void initState() {
    super.initState();
    register(versionSelectPageRouteKey, [
      SubRailSection(
        label: '版本管理',
        items: [
          for (int i = 0; i < _versionFolds.length; i++)
            SubRailItem(
              label: _versionFolds[i].tag,
              icon: Icons.folder_outlined,
              onTap: () {
                if (mounted) setState(() => _index = i);
              },
              selected: (_) => i == _index,
            ),
        ],
      ),
    ]);
  }

  @override
  void dispose() {
    final key = PageKeyProvider.shellKey;
    key.currentState?.routeWatcher.unsubscribe(this);
    print('object');
    super.dispose();
  }

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

  Widget _buildVersionTile(Mindustry version) {
    final isSelectVersion =
        version.id == config.versionOptions.selectedVersionId;

    final theme = Theme.of(context);

    return ReboundListTile(
      margin: EdgeInsets.all(8),
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
      trailing: IconTheme(
        data: theme.iconTheme,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (isSelectVersion)
              Icon(
                Icons.bookmark_border,
                color: Colors.yellow.shade700,
                size: 28,
              ),
            ReboundButton(
              child: Icon(Icons.delete_outline),
              onTap: () => _delete(version),
            ),
            ReboundButton(
              child: Icon(
                version.like ? Icons.favorite : Icons.favorite_border_rounded,
                color: version.like ? Colors.red : null,
              ),
              onTap: () => _collect(version),
            ),
            ReboundButton(
              child: Icon(Icons.settings),
              onTap: () => _popToSettingOf(version),
            ),
          ],
        ),
      ),
      onTap: () => _select(version),
    );
  }

  Widget _buildVersionViewPage(List<Mindustry> versions) {
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
      return _buildEmptyPage();
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
    return Material(
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
                  '/download',
                  (_) => false,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildVersionViewPage(_versionFolds[_index].versions);
  }
}
