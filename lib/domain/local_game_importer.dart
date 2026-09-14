import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/ui/components/input/tag_input_dialog.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

///把本地 Mindustry 游戏文件（jar / zip）导入为一个版本
///
/// 流程：让用户命名 tag（默认按 jar 里的版本信息给）→ 把本体拷进
/// `<fold.path>/<tag>/`（版本自包含）→ 按设置页的「游戏默认隔离设置」定隔离 →
/// 建版本记录并保存
///
/// [reader] 是已经识别过的文件（游戏本体动辄上百 MB，不重复读盘）
/// [targetFold] 不传时落到默认文件夹（[AppPaths.versions]，与下载落点一致）
///
/// 返回新建的版本；用户取消、不是游戏本体、写入失败时返回 null（失败会弹通知）
Future<Mindustry?> importLocalGame({
  required FileReader reader,
  VersionFold? targetFold,
  BuildContext? context,
}) async {
  final meta = reader.mindustry;
  if (reader.type != ResourceType.mindustry || meta == null) {
    addNotice(
      icon: Icons.close,
      title: '类型错误',
      content: '该文件不是有效的 Mindustry 游戏文件，请确认文件存在',
    );
    Log.add(.warning, '类型错误:文件[${reader.path}]不是有效的 Mindustry 游戏文件');
    return null;
  }

  final fold = targetFold ?? defaultVersionFold();
  final isBe = meta.type == 'bleeding-edge';
  final defaultTag = isBe
      ? 'Build ${meta.build}'
      : 'v${meta.version} Build ${meta.build}';
  final usedTags = versionTags();

  //识别文件读过盘，用调用方的 context 前先确认它还挂着
  if (context != null && !context.mounted) return null;

  final tag = await showAnimatedDialog<String>(
    context: context,
    pageBuilder: (_, _, _) => TagInputDialog(
      title: '导入游戏',
      label: '版本标签',
      defaultText: defaultTag,
      validate: (tag) {
        final error = WindowsFileNameValidator.tagValidate(tag);
        if (error != null) return error;
        if (usedTags.contains(tag)) return '名称已存在';
        return null;
      },
    ),
  );
  if (tag == null) return null;

  final targetDir = p.join(fold.path, tag);
  final jarPath = await reader.importTo(targetDir);
  if (jarPath == null) {
    addNotice(
      icon: Icons.close,
      title: '导入失败',
      content: '无法写入目标目录，请选择合适的路径',
    );
    Log.add(.warning, '导入失败:文件[${reader.path}]无法写入目标目录[$targetDir]');
    return null;
  }

  final version = Mindustry(
    id: const Uuid().v4(),
    launcher: LauncherType.mindustry, //TODO 等待后续接入Copper Loader
    tag: tag,
    jarPath: jarPath,
    isBe: isBe,
    path: fold.path,
    release: isBe ? meta.build : 'v${meta.build}',
    addTime: DateTime.now(),
    //隔离与否取设置页的「游戏默认隔离设置」，不再写死
    isolation: config.setting.launchOptions.isIsolatedByDefault(
      isBe: isBe,
      launcher: LauncherType.mindustry,
    ),
  );
  fold.versions.add(version);
  config.save();
  Log.add(
    .info,
    '导入本地游戏 [${version.tag}]：本体 $jarPath，存档隔离${version.isolation ? '开启' : '关闭'}',
  );
  return version;
}

///默认文件夹：与下载落点一致（[AppPaths.versions]）；配置里找不到就用第一个兜底
VersionFold defaultVersionFold() {
  final folds = config.versionOptions.versionFolds;
  for (final fold in folds) {
    if (fold.path == AppPaths.versions) return fold;
  }
  return folds.first;
}

///配置里已被占用的版本 tag（跨全部 fold），用于命名查重
Set<String> versionTags() => {
  for (final fold in config.versionOptions.versionFolds)
    for (final version in fold.versions) version.tag,
};
