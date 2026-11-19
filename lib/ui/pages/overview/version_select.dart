import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/local_game_importer.dart';
import 'package:copper_launcher/domain/steam_library.dart';
import 'package:copper_launcher/domain/steam_version.dart';
import 'package:copper_launcher/domain/version_variant.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/ui/components/animation/appear_item.dart';
import 'package:copper_launcher/ui/components/core/cu_button.dart';
import 'package:copper_launcher/ui/components/core/cu_list_panel.dart';
import 'package:copper_launcher/ui/components/cu_card.dart';
import 'package:copper_launcher/ui/components/core/cu_list_tile.dart';
import 'package:copper_launcher/ui/components/core/cu_menu.dart';
import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/core/cu_tab_bar.dart';
import 'package:copper_launcher/ui/components/scroll/list_view.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/util/route/route_trail.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';

import 'package:copper_launcher/ui/components/input/tag_input_dialog.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/format/path_format.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/material.dart';
import '../../feature/version_icon.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

////version_select
const versionSelectPageRouteKey = '/version_select';

class VersionSelectPage extends StatefulWidget {
  const VersionSelectPage({super.key});
  @override
  State<StatefulWidget> createState() => _VersionSelectPageState();
}

//选择版本页面
class _VersionSelectPageState extends State<VersionSelectPage> {
  final List<VersionFold> _versionFolds = config.versionOptions.versionFolds;

  static int _index = 0;

  /// 分类：0 全部 / 1 原版 / 2 Copper / 3 测试
  int _category = 0;

  /// 只看收藏
  bool _likeOnly = false;

  /// 当前目录是页内分项：作为顶栏在「版本选择」段之后追加的方框
  void _reportFold() {
    if (!mounted) return;
    final folds = _versionFolds;
    if (folds.isEmpty) {
      PageTopBar.of(context).setSections(const []);
      return;
    }
    final index = _index.clamp(0, folds.length - 1);
    PageTopBar.of(context).setSections([folds[index].tag]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reportFold();
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
      title: '确定删除 [$tag]？',
      content: '[$tag] 的游戏文件与它的存档 / mod / 整合包 / 蓝图 / 地图都会被删除',
      action: () async {
        // 统一删除逻辑（含共享 jar 检查：同一 jarPath 被其它版本引用时不删本体）
        final deleted = await config.versionOptions.deleteVersion(version);
        if (!deleted) {
          debugPrint('删除失败：无法删除游戏文件 $tag');
          return;
        }
        // 页面先退也要把删除结果落盘，所以只守重建这一步
        if (mounted) setState(() {});
        await config.save();
        _updateView();
      },
    );
  }

  /// 重命名目录（fold 项）的 tag，路径不变
  void _renameFold(int index) async {
    if (index < 0 || index >= _versionFolds.length) return;
    final fold = _versionFolds[index];
    final tag = await showAnimatedDialog<String>(
      context: context,
      pageBuilder: (_, _, _) => TagInputDialog(
        title: '重命名目录',
        label: '目录名称',
        defaultText: fold.tag,
        validate: (tag) {
          final e = WindowsFileNameValidator.tagValidate(tag);
          if (e != null) return e;
          if (_versionFolds.any((other) => other != fold && other.tag == tag)) {
            return '名称已存在';
          }
          return null;
        },
      ),
    );
    if (tag == null || tag == fold.tag || !mounted) return;
    setState(() => fold.tag = tag);
    await config.save();
    _updateView();
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
    addLog(.info, '切换版本 [${version.tag}]：${version.release}', tag: 'Version');
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

  /// 数据变更后的刷新：调用点已通过 setState 更新数据，这里兜底重建
  ///
  /// 不用 pushReplacementNamed 整页替换——整页替换会打断上级页面（launch）
  /// 的 await 路由语义（await 绑定旧 route，替换后提前完成导致列表刷新失联），
  /// 且使局部状态（滚动 / 折叠）重置；本页数据源是 config 引用，setState 足够
  void _updateView() {
    if (!mounted) return;
    setState(() {});
    _reportFold();
  }

  void _popToSettingOf(Mindustry version) {
    final index = _versionFolds[_index].versions.indexWhere(
      (v) => v == version,
    );
    if (index == -1) return;
    Navigator.pushNamed(
      context,
      '/version_setting',
      arguments: {'version': version},
    );
  }

  /// 添加目录 / 分类：
  /// - 桌面端：选一个游戏目录，命名后加入版本折叠，目录下已有版本自动扫描进去
  /// - 移动端：新建分类——权限受限无法自由选目录，改为在应用目录下创建同名文件夹
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
      pageBuilder: (_, _, _) => TagInputDialog(
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
    addLog(.info, '已添加目录：$path', tag: 'Version');
    if (scanned.isNotEmpty) {
      addLog(.info, '扫描目录 [$path]：${scanned.length} 个游戏版本', tag: 'Version');
    }
    addNotice(
      icon: Icons.search,
      title: '成功添加目录',
      content: scanned.isNotEmpty ? '在目录中找到${scanned.length} 个游戏版本' : null,
    );
    setState(() {
      _versionFolds.add(
        VersionFold(
          tag: tag,
          path: AppPaths.toStoredPath(path),
          versions: scanned,
        ),
      );
      _index = _versionFolds.length - 1;
    });
    await config.save();
    _updateView();
  }

  /// 新建分类（移动端）：在 [AppPaths.versionsFolds] 下创建与 tag 同名的文件夹
  ///
  /// 手机权限受限，无法自由选择管理目录，只能在应用自己的目录下建文件夹，
  /// 因此「添加目录」在移动端表现为「新建分类」，路径固定在应用目录内
  Future<void> _addNewCategory() async {
    final tag = await showAnimatedDialog<String>(
      context: context,
      pageBuilder: (_, _, _) => TagInputDialog(
        title: '新建分类',
        label: '分类名称',
        defaultText: '新的分类',
        validate: (tag) {
          final e = WindowsFileNameValidator.tagValidate(tag);
          if (e != null) return e;
          if (_versionFolds.any((fold) => fold.tag == tag)) return '名称已存在';
          return null;
        },
      ),
    );
    if (tag == null || !mounted) return;

    final folderPath = p.join(AppPaths.versionsFolds, tag);
    try {
      await Directory(folderPath).create(recursive: true);
    } catch (e) {
      addLog(
        .error,
        '创建分类文件夹失败：$folderPath，${removeNewlines('$e')}',
        tag: 'Version',
      );
      if (mounted) {
        addNotice(icon: Icons.close, title: '新建失败', content: '无法在应用目录下创建分类文件夹');
      }
      return;
    }

    addLog(.info, '已新建分类 [$tag]：路径 $folderPath', tag: 'Version');
    setState(() {
      _versionFolds.add(
        VersionFold(
          tag: tag,
          path: AppPaths.toStoredPath(folderPath),
          versions: [],
        ),
      );
      _index = _versionFolds.length - 1;
    });
    await config.save();
    _updateView();
  }

  /// 扫描目录内可能的游戏版本：直接 .jar 文件与子目录内的 .jar
  Future<List<Mindustry>> _scanGameVersions(String folderPath) async {
    final result = <Mindustry>[];
    final root = Directory(folderPath);
    if (!await root.exists()) return result;

    await for (final entity in root.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.jar')) {
        final version = await _recognizeJar(folderPath, entity.path);
        if (version != null) result.add(version);
        continue;
      }
      if (entity is Directory) {
        await for (final sub in entity.list()) {
          if (sub is File && sub.path.toLowerCase().endsWith('.jar')) {
            final version = await _recognizeJar(folderPath, sub.path);
            if (version != null) result.add(version);
            break;
          }
        }
      }
    }
    return result;
  }

  /// 用 [FileReader] 识别 jar：是 mindustry 则构造版本
  Future<Mindustry?> _recognizeJar(String folderPath, String jarPath) async {
    final reader = await FileReader.fromPath(jarPath);
    final meta = reader.mindustry;
    if (reader.type != ResourceType.mindustry || meta == null) {
      return null;
    }

    final isBe = meta.type == 'bleeding-edge';
    final tag = !isBe
        ? 'v${meta.version} Build ${meta.build}'
        : 'Build ${meta.build}';

    // 隔离与否取设置页的「游戏默认隔离设置」，不再写死
    final isolation = config.setting.launchOptions.isIsolatedByDefault(
      isBe: isBe,
      launcher: LauncherType.mindustry,
    );

    return Mindustry(
      id: const Uuid().v4(),
      launcher: LauncherType.mindustry,
      tag: _uniqueTag(tag),
      // 扫来的是用户自己的本体：数据根外的路径原样记（绝对），根内则记相对
      jarPath: AppPaths.toStoredPath(jarPath),
      path: AppPaths.toStoredPath(folderPath),
      isBe: isBe,
      release: isBe ? meta.build : 'v${meta.build}',
      addTime: DateTime.now(),
      isolation: isolation,
      // 扫来的是用户自己的本体：启动器不复制，删版本时也不碰文件
      bodyIsUserFile: true,
    );
  }

  /// 保证 tag 不与已有目录 / 版本重名
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
      candidate = '$tag(${i++})';
    }
    return candidate;
  }

  /// 导入本地游戏：选一个 Mindustry jar，识别后作为版本加入当前目录（桌面端）
  Future<void> _importLocalGame() async {
    if (!isDesktop) return;

    addLog(.info, '导入外部游戏文件', tag: 'Version');

    final path = await PathSelector.selectFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Mindustry', extensions: ['jar', 'zip']),
      ],
    );
    if (path == null || !mounted) return;

    final reader = await FileReader.fromPath(path);
    if (!mounted) return;

    //具体流程见 importLocalGame（与启动器拖入共用同一套）
    final version = await importLocalGame(
      reader: reader,
      targetFold: _versionFolds[_index],
      context: context,
    );
    if (version == null || !mounted) return;

    _updateView();
  }

  /// 版本行副标题：版本号 + 来源标记
  ///
  /// Steam 版显示成 `Steam  steam v157.4`（[Mindustry.displayRelease]）——
  /// 记录本身是「一条就地刷新的版本」，具体是哪个 build 就看这里
  Widget _buildVersionSubtitle(Mindustry version) {
    final style = Theme.of(context).textTheme.bodyMedium;
    if (!version.steam) return Text(version.displayRelease, style: style);

    return Row(
      children: [
        Text(
          'Steam',
          style: style?.copyWith(color: AppColors.of(context).interactive),
        ),
        const SizedBox(width: 6),
        Text(version.displayRelease, style: style),
      ],
    );
  }

  /// 扫描 Steam 版：找出 Steam 库里装着的 Mindustry（本体 `modifier=steam`），
  /// 加进「Steam」专用分类
  ///
  /// 已有同一份本体的记录会被**归一成 Steam 形态**（补上数据目录绑定与 Steam 标记），
  /// 不再多建一条；Steam 装了但库里没有的，提示用户改用「添加新目录」手选
  Future<void> _scanSteamVersions() async {
    if (!isDesktop) return;

    addLog(.info, '扫描 Steam 版', tag: 'Steam');
    final installs = await SteamLibrary.detect();
    if (!mounted) return;

    if (installs.isEmpty) {
      addLog(.warning, '没有检测到 Steam 版 Mindustry', tag: 'Steam');
      addNotice(
        icon: Icons.search_off,
        title: '没找到 Steam 版',
        content: '确认 Steam 里装过 Mindustry；装在别处可以改用「添加新目录」指到它的安装目录',
      );
      return;
    }

    final added = <String>[];
    final refreshed = <String>[];
    for (final install in installs) {
      final result = await SteamVersion.addOrRefresh(install: install);
      (result.created ? added : refreshed).add(result.version.tag);
    }
    if (!mounted) return;

    setState(() {
      final index = _versionFolds.indexWhere(
        (fold) => fold.tag == SteamVersion.foldTag,
      );
      if (index != -1) _index = index;
    });
    _updateView();
    addNotice(
      icon: Icons.sports_esports,
      title: '找到 ${installs.length} 个 Steam 版',
      content: [
        if (added.isNotEmpty) '已加入：${added.join('、')}',
        if (refreshed.isNotEmpty) '已刷新：${refreshed.join('、')}',
      ].join('\n'),
    );
  }

  /// 当前分类 + 收藏过滤后的版本（按添加时间倒序）
  List<Mindustry> _visibleVersions() {
    final all = List<Mindustry>.of(_versionFolds[_index].versions)
      ..sort((a, b) => -a.addTime.compareTo(b.addTime));
    return all.where((version) {
      if (_likeOnly && !version.like) return false;
      return switch (_category) {
        1 => !version.isBe && version.launcher != LauncherType.copper,
        2 => version.launcher == LauncherType.copper,
        3 => version.isBe,
        _ => true,
      };
    }).toList();
  }

  int _countCategory(int category) {
    return _versionFolds[_index].versions.where((version) {
      return switch (category) {
        1 => !version.isBe && version.launcher != LauncherType.copper,
        2 => version.launcher == LauncherType.copper,
        3 => version.isBe,
        _ => true,
      };
    }).length;
  }

  /// 顶部信息条：当前文件夹的名称 / 路径 / 数量 / 来源 + 更换目录与新建入口
  Widget _buildFoldInfoBar() {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final fold = _versionFolds[_index];
    final liked = fold.versions.where((version) => version.like).length;
    final isDefault = _index == 0;

    return CuCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.elevatedBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 22,
              color: colors.itemSecondary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Flexible(
                      child: Text(
                        fold.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.itemPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isDefault)
                      _badge(colors, '默认', colors.interactive)
                    else
                      _badge(colors, '自定义', colors.itemSecondary),
                  ],
                ),
                Text(
                  formatPathForWrap(fold.resolvedPath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemHint,
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const ['Courier New', 'monospace'],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: [
              Text(
                '${fold.versions.length} 个版本',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.itemPrimary,
                ),
              ),
              Text(
                '${liked} 个收藏',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
            ],
          ),
          CuMenuButton(
            items: [
              CuMenuItem(
                icon: Icons.drive_file_rename_outline,
                label: '重命名目录',
                onSelected: () => _renameFold(_index),
              ),
              if (_index != 0)
                CuMenuItem(
                  icon: Icons.delete_outline,
                  label: '删除目录',
                  danger: true,
                  onSelected: () => _deleteFold(_index),
                ),
            ],
          ),
          _buildFoldSwitcher(),
        ],
      ),
    );
  }

  /// 更换目录：信息条末端的独立按钮；菜单里列目录 + 新建 / 导入 / 扫描
  Widget _buildFoldSwitcher() {
    return Builder(
      builder: (context) => CuButton(
        kind: CuButtonKind.plain,
        icon: Icons.swap_horiz,
        label: '切换目录',
        onTap: () => _openFoldMenu(context),
      ),
    );
  }

  void _openFoldMenu(BuildContext context) {
    ContextMenu.showBelow(
      context: context,
      entries: [
        for (var i = 0; i < _versionFolds.length; i++)
          ContextMenuAction(
            label:
                '${_versionFolds[i].tag} (${_versionFolds[i].versions.length})',
            icon: Icons.folder_outlined,
            checked: i == _index,
            onSelected: () {
              setState(() => _index = i);
              _reportFold();
            },
          ),
        const ContextMenuDivider(),
        ContextMenuAction(
          label: isDesktop ? '添加新目录' : '新建分类',
          icon: Icons.create_new_folder_outlined,
          onSelected: isDesktop ? _addNewFold : _addNewCategory,
        ),
        if (isDesktop) ...[
          ContextMenuAction(
            label: '导入本地游戏',
            icon: Icons.file_upload_outlined,
            onSelected: _importLocalGame,
          ),
          ContextMenuAction(
            label: '扫描 Steam 版',
            icon: Icons.sports_esports,
            onSelected: _scanSteamVersions,
          ),
        ],
      ],
    );
  }

  Widget _badge(AppColors colors, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  /// 分类切换：模组下载页同款横向标签（下划线）
  Widget _buildFilterBar() {
    return CuTabBar(
      tabs: [
        '全部 (${_countCategory(0)})',
        '原版 (${_countCategory(1)})',
        'Copper (${_countCategory(2)})',
        '测试 (${_countCategory(3)})',
      ],
      value: _category,
      onTap: (index) => setState(() => _category = index),
      trailing: _buildLikeToggle(),
    );
  }

  /// 收藏筛选开关（内容卡标题行右侧）
  Widget _buildLikeToggle() {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return CuPressable(
      selected: _likeOnly,
      onTap: () => setState(() => _likeOnly = !_likeOnly),
      borderRadius: BorderRadius.circular(4),

      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(
            _likeOnly ? Icons.star : Icons.star_outline,
            size: 16,
            color: _likeOnly ? colors.interactive : colors.itemSecondary,
          ),
          Text(
            '收藏',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _likeOnly ? colors.itemPrimary : colors.itemSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionRow(Mindustry version) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final isCurrent = config.versionOptions.selectedVersion == version;

    return CuListTile(
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: VersionIcon(
            version: version,
            height: 36,
            width: 36,
            fallbackScale: 1.0,
            fit: BoxFit.cover,
          ),
        ),
      ),
      title: Text(
        version.tag,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.itemPrimary,
          fontWeight: isCurrent ? FontWeight.w600 : null,
        ),
      ),
      subtitle: isDesktop
          ? DefaultTextStyle(
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.itemHint,
              ),
              child: _buildVersionSubtitle(version),
            )
          : null,
      onTap: () => _select(version),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colors.indicatorBackground,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '当前',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.interactive,
                ),
              ),
            ),
          CuPressable(
            onTap: () => _collect(version),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(
                version.like ? Icons.star : Icons.star_outline,
                size: 18,
                color: version.like ? colors.interactive : colors.itemHint,
              ),
            ),
          ),
          CuMenuButton(
            items: [
              CuMenuItem(
                icon: Icons.settings_outlined,
                label: '版本设置',
                onSelected: () => _popToSettingOf(version),
              ),
              CuMenuItem(
                icon: Icons.copy_all,
                label: '新建变体',
                onSelected: () async {
                  final created = await createVersionVariant(
                    source: version,
                    context: context,
                  );
                  if (created == null || !mounted) return;
                  _updateView();
                },
              ),
              CuMenuItem(
                icon: Icons.delete_outline,
                label: '删除版本',
                danger: true,
                onSelected: () => _delete(version),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVersionViewPage() {
    final versions = _visibleVersions();

    // 项目惯例：页头信息不钉在顶上，跟着内容一起滚；各区按路由时间轴槽位接力浮现
    return CuListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppearItem(
          slot: 0,
          followRouteDirection: true,
          scale: 0.99,
          child: _buildFoldInfoBar(),
        ),
        const SizedBox(height: 12),
        AppearItem(
          slot: 1,
          followRouteDirection: true,
          child: _buildFilterBar(),
        ),
        const SizedBox(height: 12),
        versions.isEmpty
            ? AppearItem(
                slot: 2,
                followRouteDirection: true,
                scale: 0.98,
                child: _buildEmptyPage(),
              )
            : AppearItem(
                slot: 2,
                followRouteDirection: true,
                scale: 0.99,
                child: CuListPanel(
                  title: '${const ['全部', '原版', 'Copper', '测试'][_category]}版本',
                  subtitle: '共 ${versions.length} 个 · 单击切换，右侧 ⋯ 做更多操作',
                  children: [
                    for (final version in versions) _buildVersionRow(version),
                  ],
                ),
              ),
      ],
    );
  }

  Widget _buildEmptyPage() {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          const SizedBox(height: 20),
          Icon(Icons.inbox_outlined, size: 40, color: colors.itemHint),
          Text(
            '这个分类下还没有版本',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.itemPrimary,
            ),
          ),
          Text(
            '可以导入本地游戏，或添加一个已有游戏目录',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              if (isDesktop)
                CuButton(
                  label: '导入本地游戏',
                  icon: Icons.file_upload_outlined,
                  onTap: _importLocalGame,
                ),
              CuButton(
                label: isDesktop ? '添加新目录' : '新建分类',
                icon: Icons.create_new_folder_outlined,
                kind: CuButtonKind.plain,
                onTap: isDesktop ? _addNewFold : _addNewCategory,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 页内导航栏并入页头：目录切换、新建 / 导入 / 扫描都在信息条里
    return MainPageLayout(page: _buildVersionViewPage());
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
