import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/selection/drag_select_list.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/data/local_asset.dart' show Mindustry;
import 'package:copper_launcher/util/app_paths.dart';
import 'package:flutter/material.dart';

import '../../util/format/string_cleaner.dart';
import '../../util/io/file_reader.dart';
import '../../util/format/path_format.dart';
import '../feature/images.dart';

import 'package:copper_launcher/ui/components/button/rebound_button.dart';

bool isImporting = false;

///弹出本地资源导入对话框。
///
///返回是否成功导入了至少一个资源；同屏只允许一个导入流程
Future<bool> showResourceImporter(
  List<String> files, {
  Mindustry? mindustry,
}) async {
  if (isImporting) return true;
  if (files.isEmpty) return false;
  isImporting = true;

  final result = Completer<bool>();
  //等弹窗路由关闭（点遮罩 / Esc / 返回键同样算关闭）而不是只等 Completer，
  //否则非正常关闭时 onFinished 不会被调用，导入锁永远解不开
  await showDefaultDialogPopup(
    pageBuilder: (_, _, _) {
      return ResourceImporter(
        files: files,
        mindustry: mindustry,
        onFinished: (imported) {
          if (!result.isCompleted) result.complete(imported);
        },
      );
    },
  );
  isImporting = false;

  if (!result.isCompleted) return false;
  return await result.future;
}

class ResourceImporter extends StatefulWidget {
  const ResourceImporter({
    super.key,
    required this.files,
    required this.onFinished,
    this.mindustry,
  });

  final List<String> files;

  ///目标游戏版本：提供时导入到该版本的独立数据目录（版本隔离感知）
  final Mindustry? mindustry;

  ///导入流程结束时回调（是否成功导入至少一个资源）
  final ValueChanged<bool> onFinished;

  @override
  State<ResourceImporter> createState() => ResourceImporterState();
}

class ResourceImporterState extends State<ResourceImporter> {
  final List<FileReader> importList = [];

  ///每个资源的勾选状态（默认全选）
  final Set<int> _selected = {};

  bool _importing = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    for (var path in widget.files) {
      final reader = await FileReader.fromPath(path);
      if (reader.type == null) continue;
      importList.add(reader);
    }
    importList.sort((a, b) {
      if (a.type == ResourceType.mindustry) return -1;
      if (b.type == ResourceType.mindustry) return 1;
      if (a.type == ResourceType.mod) return -1;
      if (b.type == ResourceType.mod) return 1;
      if (a.type == ResourceType.mapSave) return -1;
      if (b.type == ResourceType.mapSave) return 1;
      if (a.type == ResourceType.schematic) return -1;
      if (b.type == ResourceType.schematic) return 1;
      return 0;
    });
    _selected.addAll([for (var i = 0; i < importList.length; i++) i]);
    setState(() {});
  }

  bool get _allSelected => _selected.length == importList.length;

  ///把 [source] 复制到 [dir]，同名文件自动加序号，不覆盖已有内容；
  ///返回 null 表示复制成功，否则为失败原因（与 [_importOne] 的返回值契约一致）
  Future<String?> _copyInto(String dir, String source) async {
    try {
      final target = Directory(dir);
      if (!target.existsSync()) target.createSync(recursive: true);

      final name = source.split(Platform.pathSeparator).last;
      final dot = name.lastIndexOf('.');
      final stem = dot < 0 ? name : name.substring(0, dot);
      final ext = dot < 0 ? '' : name.substring(dot);

      var dest = '$dir${Platform.pathSeparator}$name';
      var index = 1;
      while (File(dest).existsSync()) {
        dest = '$dir${Platform.pathSeparator}$stem ($index)$ext';
        index++;
      }
      await File(source).copy(dest);
      return null;
    } catch (error) {
      return '复制失败：$error';
    }
  }

  ///把单个资源导入对应目录，返回 null 表示成功，否则为失败原因
  Future<String?> _importOne(FileReader reader) async {
    //目标数据目录：指定版本 → 该版本的独立数据目录（版本隔离感知）；
    //未指定 → 默认游戏数据目录
    final gameData = widget.mindustry?.dataPath ?? AppPaths.defaultGameData;
    switch (reader.type) {
      case ResourceType.mod:
        if (reader.mod?.path == null || gameData == null) {
          return '未找到游戏数据目录';
        }
        return await _copyInto(
          '$gameData${Platform.pathSeparator}mods',
          reader.mod!.path!,
        );
      case ResourceType.mapSave:
        if (reader.mapSave?.path == null || gameData == null) {
          return '未找到游戏数据目录';
        }
        return await _copyInto(
          '$gameData${Platform.pathSeparator}maps',
          reader.mapSave!.path!,
        );
      case ResourceType.schematic:
        if (reader.schematic?.path == null || gameData == null) {
          return '未找到游戏数据目录';
        }
        return await _copyInto(
          '$gameData${Platform.pathSeparator}schematics',
          reader.schematic!.path!,
        );
      case ResourceType.mindustry:
        if (reader.mindustry?.path == null) return '未找到源文件';
        return await _copyInto(AppPaths.mindustrys, reader.mindustry!.path!);
      case ResourceType.settings:
        return '暂不支持导入设置文件';
      case null:
        return '无法识别的资源';
    }
  }

  Future<void> _importSelected() async {
    if (_importing || _selected.isEmpty) return;
    _importing = true;
    setState(() {});

    var ok = 0;
    final failures = <String>[];
    for (final index in _selected) {
      final reader = importList[index];
      final error = await _importOne(reader);
      if (error == null) {
        ok++;
      } else {
        failures.add('${reader.type?.name ?? '未知'}：$error');
      }
    }

    _importing = false;
    if (!mounted) return;

    addNotice(
      icon: ok > 0 ? Icons.check_circle_outline : Icons.error_outline,
      title: '资源导入',
      content: failures.isEmpty
          ? '成功导入 $ok 个资源'
          : '成功 $ok 个，失败 ${failures.length} 个：${failures.join('；')}',
      duration: const Duration(seconds: 6),
    );

    if (ok > 0) {
      widget.onFinished(true);
      Navigator.pop(context);
    } else {
      setState(() {});
    }
  }

  ///全选 / 取消全选（头部按钮）
  void _toggleAllSelected() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.addAll([for (var i = 0; i < importList.length; i++) i]);
      }
    });
  }

  ///点击瓦片切换该项的选中态（拖动连续选择走 [DragSelectList] 的 onToggle）
  void _toggleSelected(int index) {
    setState(() {
      _selected.contains(index)
          ? _selected.remove(index)
          : _selected.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Row(
          spacing: 8,
          children: [
            ReboundButton(
              onTap: () {
                widget.onFinished(false);
                Navigator.pop(context);
              },
              child: Icon(Icons.arrow_back),
            ),
            Text('导入本地资源', style: theme.textTheme.titleLarge),
            Spacer(),
            if (importList.isNotEmpty)
              ReboundButton(
                //次级操作：贴合对话框按钮的常规边距
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onTap: _toggleAllSelected,
                child: Text(_allSelected ? '取消全选' : '全选'),
              ),
          ],
        ),
        if (importList.isNotEmpty) ...[
          //列表自身不带滚动条：外套项目滚动容器（自研滚动条 + 渐隐遮罩）；
          //DragSelectList 拿到的高度无界 → 其内层滚动视图不滚动，滚轮与滚动条由外层接管
          Expanded(
            child: CopperSingleChildScrollView(
              child: DragSelectList(
                itemCount: importList.length,
                selected: _selected,
                itemSpacing: 4,
                onToggle: (index, selected) {
                  setState(() {
                    selected ? _selected.add(index) : _selected.remove(index);
                  });
                },
                itemBuilder: (context, index, _) => _buildResourceTile(index),
              ),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Text(
                '已选 ${_selected.length} / ${importList.length}',
                style: theme.textTheme.bodySmall,
              ),
              Spacer(),
              ReboundButton(
                //主操作：比次级操作厚一档，拉开层级
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                onTap: _importing || _selected.isEmpty ? null : _importSelected,
                child: Text(
                  _importing ? '导入中...' : '导入选中（${_selected.length}）',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  ///单个资源瓦片：按类型给图标与信息，选中态与列表联动
  Widget _buildResourceTile(int index) {
    final theme = Theme.of(context);
    final reader = importList[index];
    final checked = _selected.contains(index);

    switch (reader.type) {
      case null:
        return const SizedBox.shrink();
      case ResourceType.mindustry:
        final mindustry = reader.mindustry!;
        return ReboundListTile(
          selected: checked,
          elevation: checked ? 1 : 0,
          onTap: () => _toggleSelected(index),
          leading: Image.asset(Images.mindustry),
          title: Text(
            'Mindustry v${mindustry.version}',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'build ${mindustry.build}  (${mindustry.type})',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                formatPathForWrap(mindustry.path ?? ''),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      case ResourceType.mod:
        final mod = reader.mod!;

        Widget leading;
        final icon = mod.icon;
        if (icon == null) {
          leading = Icon(Icons.question_mark, size: 48);
        } else {
          leading = ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(icon, height: 48, width: 48),
          );
        }

        return ReboundListTile(
          selected: checked,
          elevation: checked ? 1 : 0,
          onTap: () => _toggleSelected(index),
          leading: leading,
          title: Text(
            '模组  ${generalizeText(mod.name)}  |  作者  ${generalizeText(mod.author)}',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '版本  ${mod.version}   |   minGameVersion ${mod.minGameVersion}',
                style: theme.textTheme.bodySmall,
              ),
              Text(formatPathForWrap(mod.path ?? '')),
            ],
          ),
        );
      case ResourceType.mapSave:
        final mapState = reader.mapSave!;
        return ReboundListTile(
          selected: checked,
          elevation: checked ? 1 : 0,
          onTap: () => _toggleSelected(index),
          leading: Icon(Icons.map_outlined, size: 48),
          title: Text(
            '地图  ${generalizeText(mapState.name)}  |  作者  ${generalizeText(mapState.author)}',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            formatPathForWrap(mapState.path ?? ''),
            style: theme.textTheme.bodySmall,
          ),
        );
      case ResourceType.schematic:
        final schematic = reader.schematic!;
        return ReboundListTile(
          selected: checked,
          elevation: checked ? 1 : 0,
          onTap: () => _toggleSelected(index),
          leading: Icon(Icons.paste, size: 48),
          title: Text(
            '蓝图  ${generalizeText(schematic.name)}  |  作者  ${generalizeText(schematic.author)}',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            formatPathForWrap(schematic.path ?? ''),
            style: theme.textTheme.bodySmall,
          ),
        );
      case ResourceType.settings:
        return ReboundListTile(
          leading: Icon(Icons.settings_outlined, size: 48),
          title: Text('设置文件（暂不支持导入）', style: theme.textTheme.bodyMedium),
          subtitle: Text(formatPathForWrap(reader.path)),
        );
    }
  }
}
