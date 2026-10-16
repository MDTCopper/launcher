import 'dart:io';

import 'package:copper_launcher/util/app_paths.dart';
import 'package:path/path.dart' as p;

/// 数据根「从应用内部目录搬进外部应用专属目录」的一次性迁移
///
/// 背景：Android 的数据根 2026-10-16 起改到 `/sdcard/Android/data/<包名>/files`，
/// 老安装的版本 / 存档 / 配置还留在应用内部 ⇒ 界面看起来像全新安装。
/// 这里把它们搬到新根，**同名不覆盖、单条失败不影响其余、搬完才删源** ——
/// 没搬成的下次启动接着搬（每条都先看目标在不在，天然幂等）。
///
/// **三类不搬**：`bridge/`（exec / dlopen 只允许应用内部目录，它本来就该留在那儿）、
/// `logs/`（一次性的，且新根那份已经在写了）、`tmp/`（临时文件，别跟着搬）
class DataRootMigration {
  DataRootMigration._();

  /// 留在原地、不进新根的目录名
  static const Set<String> keepInPlace = {'bridge', 'logs', 'tmp'};

  /// 生产入口：Android 上「数据根与内部目录不同、且内部还有东西」时才搬
  static Future<DataRootMigrationReport?> runIfNeeded() async {
    if (!Platform.isAndroid) return null;
    final from = AppPaths.internalRoot;
    final to = AppPaths.copperLauncher;
    if (p.equals(from, to)) return null;
    if (!Directory(from).existsSync()) return null;
    return migrate(from: from, to: to);
  }

  /// 真正搬一次；独立成一层是为了能在用例里对两个临时目录跑
  /// （生产那两个根都来自 path_provider，用例里拿不到）
  static Future<DataRootMigrationReport> migrate({
    required String from,
    required String to,
  }) async {
    final report = DataRootMigrationReport();
    final source = Directory(from);
    if (!source.existsSync()) return report;
    Directory(to).createSync(recursive: true);

    for (final entity in source.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (keepInPlace.contains(name)) continue;

      final target = p.join(to, name);
      if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
        report.skippedExisting.add(name);
        continue;
      }
      try {
        _move(entity, target);
        report.moved.add(name);
      } on Object catch (error) {
        // 半途失败要清掉没搬完的那半份：留着它，下次启动会当成「已经搬过了」
        _deleteQuietly(target);
        report.failed[name] = '$error';
      }
    }
    return report;
  }

  /// 先试 `rename`（同一个文件系统上是最省的重命名）；跨不过去就复制 + 删源
  ///
  /// 应用内部存储与外部存储是**两份文件系统**，真机上 rename 必然跨不过去 ⇒
  /// 走复制那条路，所以这份代码在 Android 上第一次跑会比较慢（一次性）
  static void _move(FileSystemEntity source, String target) {
    try {
      source.renameSync(target);
      return;
    } on FileSystemException {
      // 落到下面复制那条路
    }

    if (source is Directory) {
      _copyDirectorySync(source, Directory(target));
    } else if (source is File) {
      source.copySync(target);
    } else {
      throw FileSystemException('认不出的条目', source.path);
    }
    source.deleteSync(recursive: true);
  }

  /// 递归复制（**不跟随链接**，链接按链接复制）
  ///
  /// 不用 `Directory.copy`：它半途失败时的残留不好收，而这里失败要能整个删掉重来
  static void _copyDirectorySync(Directory source, Directory target) {
    target.createSync(recursive: true);
    for (final entity in source.listSync(followLinks: false)) {
      final child = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectorySync(entity, Directory(child));
      } else if (entity is File) {
        entity.copySync(child);
      } else if (entity is Link) {
        Link(child).createSync(entity.targetSync());
      } else {
        throw FileSystemException('认不出的条目', entity.path);
      }
    }
  }

  static void _deleteQuietly(String path) {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else if (type != FileSystemEntityType.notFound) {
        File(path).deleteSync();
      }
    } on Object {
      // 清理失败也不该盖住真正的错误
    }
  }
}

/// 一次迁移的结果（给启动日志用）
class DataRootMigrationReport {
  final List<String> moved = [];
  final List<String> skippedExisting = [];
  final Map<String, String> failed = {};

  bool get didAnything => moved.isNotEmpty;

  /// 一句话汇报；什么都没发生时返回 null（调用方据此决定记不记日志）
  String? describe() {
    if (moved.isEmpty && skippedExisting.isEmpty && failed.isEmpty) return null;
    final parts = <String>[
      if (moved.isNotEmpty) '已搬入 ${moved.join('、')}',
      if (skippedExisting.isNotEmpty) '目标已有跳过 ${skippedExisting.join('、')}',
      if (failed.isNotEmpty)
        '失败 ${failed.entries.map((it) => '${it.key}（${it.value}）').join('、')}',
    ];
    return parts.join('；');
  }
}
