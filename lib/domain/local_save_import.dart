import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/version_variant.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 「本机存档一键导入」：把**本机共享数据目录**（`%APPDATA%\Mindustry` 那类）里的
/// 存档 / 地图 / 蓝图搬进某个**隔离版本**的数据目录，**同名直接覆盖**
///
/// 为什么要它：隔离版本第一次起来是一份空数据，玩家在本机（不隔离那份）攒的东西要能
/// 一键搬进来，而不是自己去资源管理器翻目录。
///
/// **三种版本不给这个入口**：
/// - **Steam 版**：数据目录固定在 Steam 安装目录里、由 Steam 管（见 `SteamVersion`）
/// - **绑了外置数据目录的**：同上，那份目录不是我们说了算
/// - **非隔离版本**：它用的就是共享目录，源与目标同一份，没有可导入的
class LocalSaveImport {
  LocalSaveImport._();

  /// 默认搬这三类：玩家自己的内容
  ///
  /// **模组与游戏设置不在内**（有意）：模组可能跟目标版本不兼容、体积也可能很大
  /// （实测一台机器上 11 个模组 175MB），游戏设置按设备各留 —— 与云存档的口径一致；
  /// 真要搬，走「新建变体」那套继承选项
  static const defaultKinds = [
    VersionDataKind.saves,
    VersionDataKind.maps,
    VersionDataKind.schematics,
  ];

  /// 这个版本能不能用一键导入
  static bool canImport(Mindustry version) =>
      version.isolation && !version.steam && !version.hasExternalDataDir;

  /// 源：本机共享数据目录；拿不到返回 null
  static String? sourcePath() => AppPaths.defaultGameData;

  /// 跑一次导入：**同名覆盖**（不同名的旧文件保留，不做清理）
  ///
  /// 返回 null 表示这个版本不该/不能导（见 [canImport]）或源目录拿不到；
  /// 单个文件拷不动只记日志，不让整次导入失败
  static Future<LocalSaveImportReport?> run({
    required Mindustry version,
    String? sourceDataPath,
    List<VersionDataKind> kinds = defaultKinds,
  }) async {
    if (!canImport(version)) return null;

    final from = sourceDataPath ?? sourcePath();
    if (from == null || from.trim().isEmpty) return null;

    final to = version.dataPath;
    if (p.normalize(from).toLowerCase() == p.normalize(to).toLowerCase()) {
      return null;
    }

    final counts = <VersionDataKind, int>{};
    var bytes = 0;
    for (final kind in kinds) {
      final result = await _copyOverwrite(
        from: kind.pathIn(from),
        to: kind.pathIn(to),
      );
      if (result.files > 0) counts[kind] = result.files;
      bytes += result.bytes;
    }

    final report = LocalSaveImportReport(
      source: from,
      target: to,
      counts: counts,
      bytes: bytes,
    );
    addLog(
      .info,
      '本机存档一键导入 [${version.tag}]：${report.summary}（$from → $to，覆盖同名）',
      tag: 'Version',
    );
    return report;
  }

  /// 递归拷贝并**覆盖同名文件**（与变体继承那套「已存在就跳过」相反）
  static Future<({int files, int bytes})> _copyOverwrite({
    required String from,
    required String to,
  }) async {
    final source = Directory(from);
    if (await source.exists()) {
      var files = 0;
      var bytes = 0;
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: from);
        if (entity is Directory) {
          await Directory(p.join(to, relative)).create(recursive: true);
          continue;
        }
        if (entity is! File) continue;
        try {
          final target = File(p.join(to, relative));
          await target.parent.create(recursive: true);
          await entity.copy(target.path);
          files++;
          bytes += await entity.length();
        } catch (error) {
          addLog(
            .warning,
            '导入本机存档：跳过 $relative（$error）',
            tag: 'Version',
          );
        }
      }
      return (files: files, bytes: bytes);
    }

    // 单项文件（settings.bin 那类）
    final file = File(from);
    if (!await file.exists()) return (files: 0, bytes: 0);
    try {
      final target = File(to);
      await target.parent.create(recursive: true);
      await file.copy(target.path);
      return (files: 1, bytes: await file.length());
    } catch (error) {
      addLog(.warning, '导入本机存档：跳过 $from（$error）', tag: 'Version');
      return (files: 0, bytes: 0);
    }
  }
}

/// 一次一键导入的结果
class LocalSaveImportReport {
  const LocalSaveImportReport({
    required this.source,
    required this.target,
    required this.counts,
    required this.bytes,
  });

  final String source;
  final String target;

  /// 每类搬了几个文件（没搬的类不会出现在表里）
  final Map<VersionDataKind, int> counts;
  final int bytes;

  int get total => counts.values.fold(0, (sum, value) => sum + value);

  /// 给通知用的一句话：`存档 3 项 / 地图 1 项（1.2MB）`
  String get summary {
    if (total == 0) return '本机那份没有可导入的内容';
    final parts = [
      for (final entry in counts.entries) '${entry.key.label} ${entry.value} 项',
    ];
    return '${parts.join(' / ')}（${_size(bytes)}）';
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
