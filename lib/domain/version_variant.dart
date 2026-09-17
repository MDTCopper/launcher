import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/local_game_importer.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// 变体可以从源版本继承的数据（数据目录下的条目）
enum VersionDataKind {
  mods('模组', 'mods'),
  saves('存档', 'saves'),
  maps('地图', 'maps'),
  schematics('蓝图', 'schematics'),
  settings('游戏设置', 'settings.bin');

  const VersionDataKind(this.label, this.entryName);

  final String label;

  ///数据目录里的条目名：前四项是目录，游戏设置是文件
  final String entryName;

  ///在某个数据目录下对应的路径
  String pathIn(String dataPath) => p.join(dataPath, entryName);

  bool get isDirectory => this != VersionDataKind.settings;
}

/// 以 [source] 为模板新建一个变体版本
///
/// - 与源版本**共用游戏本体**（同一个 `jarPath`，删除时由 [VersionOptions.deleteVersion]
///   按引用计数决定要不要删文件），新 tag + 新目录
/// - 默认**开隔离**：不隔离的话新版本会继续用全局数据目录，跟源版本混在一起，"区分"就不成立
/// - [inherit] 里的数据从源版本的数据目录**拷贝**过去（拷贝而非链接：Windows 下目录符号
///   链接要开发者模式或管理员权限）
///
/// 返回新建的版本；用户取消时返回 null
Future<Mindustry?> createVersionVariant({
  required Mindustry source,
  VersionFold? targetFold,
  BuildContext? context,
}) async {
  final options = await showAnimatedDialog<
    ({String tag, Set<VersionDataKind> inherit})
  >(
    context: context,
    pageBuilder: (_, _, _) => _VariantDialog(
      source: source,
      usedTags: versionTags(),
    ),
  );
  if (options == null) return null;

  final fold = targetFold ?? _foldOf(source);
  final version = Mindustry(
    id: const Uuid().v4(),
    launcher: source.launcher,
    tag: options.tag,
    jarPath: source.jarPath,
    isBe: source.isBe,
    path: fold.path,
    release: source.release,
    addTime: DateTime.now(),
    isolation: true,
    versionNumber: source.versionNumber,
  );

  //先把数据拷好再入账：拷一半失败时不会留下一个"记录已有、数据不全"的版本
  final copied = <String>[];
  for (final kind in options.inherit) {
    final count = await _inheritFrom(source, version, kind);
    if (count > 0) copied.add('${kind.label}（$count 项）');
  }

  fold.versions.add(version);
  config.save();
  addLog(
    .info,
    '新建变体 [${version.tag}]：游戏本体与 [${source.tag}] 共用，路径 ${version.jarPath}；'
    '数据目录 ${version.dataPath}；继承${copied.isEmpty ? '无' : copied.join('、')}',
    tag: 'Version',
  );
  addNotice(
    icon: Icons.check_box_outlined,
    title: '已新建变体',
    content: '[${version.tag}] 已创建（存档隔离已开启）'
        '${copied.isEmpty ? '' : '，继承 ${copied.join('、')}'}',
    duration: const Duration(seconds: 6),
  );
  return version;
}

/// [version] 所在的 fold：变体默认跟源版本放一起；找不到就用默认文件夹
VersionFold _foldOf(Mindustry version) {
  for (final fold in config.versionOptions.versionFolds) {
    if (fold.versions.any((it) => it.id == version.id)) return fold;
  }
  return defaultVersionFold();
}

/// 把 [kind] 对应的数据从源版本拷到新版本，返回拷进来的条目数
Future<int> _inheritFrom(
  Mindustry source,
  Mindustry target,
  VersionDataKind kind,
) async {
  final from = kind.pathIn(source.dataPath);
  final to = kind.pathIn(target.dataPath);

  if (kind.isDirectory) return _copyDirectory(from, to);

  final file = File(from);
  if (!await file.exists()) return 0;
  await Directory(target.dataPath).create(recursive: true);
  await file.copy(to);
  return 1;
}

/// 递归拷贝目录，返回拷贝的文件数（目标已存在的同名文件跳过，不覆盖）
Future<int> _copyDirectory(String from, String to) async {
  final source = Directory(from);
  if (!await source.exists()) return 0;

  var copied = 0;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final target = p.join(to, p.relative(entity.path, from: source.path));
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
      continue;
    }
    if (entity is! File) continue;
    final dest = File(target);
    if (await dest.exists()) continue;
    await dest.parent.create(recursive: true);
    await entity.copy(target);
    copied++;
  }
  return copied;
}

/// 新建变体的参数弹窗：新 tag + 要继承哪几类数据
class _VariantDialog extends StatefulWidget {
  const _VariantDialog({required this.source, required this.usedTags});

  final Mindustry source;

  ///已占用的版本 tag（跨 fold），用于查重
  final Set<String> usedTags;

  @override
  State<_VariantDialog> createState() => _VariantDialogState();
}

class _VariantDialogState extends State<_VariantDialog> {
  late final TextEditingController _tagController = TextEditingController(
    text: '${widget.source.tag} 副本',
  );

  late String? _error = _validate(_tagController.text);

  ///默认继承哪几类：模组体积大、也最可能故意不一样，默认不勾，其余勾上
  final Set<VersionDataKind> _inherit = {
    VersionDataKind.saves,
    VersionDataKind.maps,
    VersionDataKind.schematics,
    VersionDataKind.settings,
  };

  @override
  void initState() {
    super.initState();
    _tagController.addListener(
      () => setState(() => _error = _validate(_tagController.text)),
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  String? _validate(String tag) {
    final error = WindowsFileNameValidator.tagValidate(tag);
    if (error != null) return error;
    if (widget.usedTags.contains(tag)) return '名称已存在';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final screen = MediaQuery.of(context).size;

    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxWidth: screen.width * 0.5,
            maxHeight: screen.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              top: BorderSide(color: colors.border, width: 1.5),
              left: BorderSide(color: colors.border, width: 0.75),
              right: BorderSide(color: colors.border, width: 0.75),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('新建变体', style: theme.textTheme.titleLarge),
              Text(
                '游戏本体与 [${widget.source.tag}] 共用（不复制），新版本默认开启存档隔离',
                style: theme.textTheme.bodySmall,
              ),
              OutlinedTextField(
                label: '新版本标签',
                controller: _tagController,
                error: _error,
              ),
              Text('要继承的数据（点选切换）', style: theme.textTheme.bodySmall),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in VersionDataKind.values)
                    ActionButton(
                      content: Text(kind.label),
                      selected: _inherit.contains(kind),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      onTap: () => setState(() {
                        _inherit.contains(kind)
                            ? _inherit.remove(kind)
                            : _inherit.add(kind);
                      }),
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消',
                    onTap: () => Navigator.pop(context),
                  ),
                  IconTextButton(
                    icon: Icons.check,
                    content: '创建',
                    onTap: _error != null
                        ? null
                        : () => Navigator.pop(context, (
                            tag: _tagController.text.trim(),
                            inherit: {..._inherit},
                          )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
