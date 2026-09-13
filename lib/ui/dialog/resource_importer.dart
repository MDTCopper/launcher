import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/ui/components/animation/reveal_list_view.dart';
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
Future<bool> showResourceImporter(List<String> files, {Mindustry? mindustry}) async {
  if (isImporting) return true;
  if (files.isEmpty) return false;
  isImporting = true;

  final result = Completer<bool>();
  showDefaultDialogPopup(
    pageBuilder: (_, _, _) {
      return ResourceImporter(
        files: files,
        mindustry: mindustry,
        onFinished: result.complete,
      );
    },
  );

  final ok = await result.future;
  isImporting = false;
  return ok;
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

  ///把 [source] 复制到 [dir]，同名文件自动加序号，不覆盖已有内容
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
      return dest;
    } catch (_) {
      return null;
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
        return await _copyInto('$gameData${Platform.pathSeparator}mods', reader.mod!.path!);
      case ResourceType.mapSave:
        if (reader.mapSave?.path == null || gameData == null) {
          return '未找到游戏数据目录';
        }
        return await _copyInto('$gameData${Platform.pathSeparator}maps', reader.mapSave!.path!);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ReboundButton(
              onTap: () {
                widget.onFinished(false);
                Navigator.pop(context);
              },
              child: Icon(Icons.arrow_back),
            ),
            SizedBox(width: 8),
            Text('导入本地资源', style: theme.textTheme.bodyLarge),
            Spacer(),
            if (importList.isNotEmpty)
              ReboundButton(
                onTap: () {
                  setState(() {
                    if (_allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll([
                        for (var i = 0; i < importList.length; i++) i,
                      ]);
                    }
                  });
                },
                child: Text(_allSelected ? '取消全选' : '全选'),
              ),
          ],
        ),
        SizedBox(height: 8),
        if (importList.isNotEmpty)
          Expanded(
            child: RevealListView(
              delay: 300,
              appearDuration: const Duration(milliseconds: 350),
              offset: Offset(-0.1, 0.0),
              items: importList.asMap().entries.map((entry) {
                final index = entry.key;
                final it = entry.value;
                final checked = _selected.contains(index);
                switch (it.type) {
                  case null:
                    return SizedBox();
                  case ResourceType.mindustry:
                    final m = it.mindustry!;
                    return ReboundListTile(
                      selected: checked,
                      elevation: checked ? 1 : 0,
                      onTap: () {
                        setState(() {
                          checked ? _selected.remove(index) : _selected.add(index);
                        });
                      },
                      leading: Image.asset(Images.mindustry),
                      title: Text('Mindustry v${m.version}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('build ${m.build}  (${m.type})'),
                          Text(formatPathForWrap(m.path ?? '')),
                        ],
                      ),
                    );
                  case ResourceType.mod:
                    final mod = it.mod!;

                    Widget leading;
                    final icon = mod.icon;
                    if (icon == null) {
                      leading = Icon(Icons.question_mark, size: 40);
                    } else {
                      leading = ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(icon, height: 40, width: 40),
                      );
                    }

                    return ReboundListTile(
                      selected: checked,
                      elevation: checked ? 1 : 0,
                      onTap: () {
                        setState(() {
                          checked ? _selected.remove(index) : _selected.add(index);
                        });
                      },
                      leading: leading,
                      title: Text(
                        '模组  ${generalizeText(mod.name)}  |  作者  ${generalizeText(mod.author)}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '版本  ${mod.version}   |   minGameVersion ${mod.minGameVersion}',
                          ),
                          Text(formatPathForWrap(mod.path ?? '')),
                        ],
                      ),
                    );
                  case ResourceType.mapSave:
                    final m = it.mapSave!;
                    return ReboundListTile(
                      selected: checked,
                      elevation: checked ? 1 : 0,
                      onTap: () {
                        setState(() {
                          checked ? _selected.remove(index) : _selected.add(index);
                        });
                      },
                      leading: Icon(Icons.map_outlined, size: 40),
                      title: Text(
                        '地图  ${generalizeText(m.name)}  |  作者  ${generalizeText(m.author)}',
                      ),
                      subtitle: Text(formatPathForWrap(m.path ?? '')),
                    );
                  case ResourceType.schematic:
                    final m = it.schematic!;
                    return ReboundListTile(
                      selected: checked,
                      elevation: checked ? 1 : 0,
                      onTap: () {
                        setState(() {
                          checked ? _selected.remove(index) : _selected.add(index);
                        });
                      },
                      leading: Icon(Icons.paste, size: 40),
                      title: Text(
                        '蓝图  ${generalizeText(m.name)}  |  作者  ${generalizeText(m.author)}',
                      ),
                      subtitle: Text(formatPathForWrap(m.path ?? '')),
                    );
                  case ResourceType.settings:
                    return ReboundListTile(
                      leading: Icon(Icons.settings_outlined, size: 64),
                      title: Text('设置文件（暂不支持导入）'),
                      subtitle: Text(formatPathForWrap(it.path)),
                    );
                }
              }).toList(),
            ),
          ),
        if (importList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Text(
                  '已选 ${_selected.length} / ${importList.length}',
                  style: theme.textTheme.bodySmall,
                ),
                Spacer(),
                ReboundButton(
                  onTap: _importing || _selected.isEmpty ? null : _importSelected,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _importing
                          ? '导入中...'
                          : '导入选中（${_selected.length}）',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
