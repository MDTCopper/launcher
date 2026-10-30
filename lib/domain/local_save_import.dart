import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/mod_install.dart';
import 'package:copper_launcher/domain/version_variant.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 「本机存档一键导入」：把**本机共享数据目录**（`%APPDATA%\Mindustry` 那类）里的
/// 存档 / 地图 / 蓝图 / 模组搬进某个**隔离版本**的数据目录，**同名直接覆盖**；
/// 模组按「同一个 mod 只留新文件」去重
///
/// 给隔离版本用：它第一次起来是空数据，玩家在本机（不隔离那份）攒的东西要能一键搬进来。
/// Steam 版、绑了外置数据目录的、以及非隔离版本（源就是它自己用的那份）都没有这个入口
class LocalSaveImport {
  LocalSaveImport._();

  /// 默认搬这五类（原版 `mods/` + Copper 原生 `copper/mods/` 都算）
  ///
  /// **游戏设置不在内**（有意）：键位 / 语言 / 显示这些按设备各留，与云存档口径一致
  static const defaultKinds = [
    VersionDataKind.saves,
    VersionDataKind.maps,
    VersionDataKind.schematics,
    VersionDataKind.mods,
    VersionDataKind.copperMods,
  ];

  /// 这个版本能不能用一键导入
  static bool canImport(Mindustry version) =>
      version.isolation && !version.steam && !version.hasExternalDataDir;

  /// 源：本机共享数据目录；拿不到返回 null
  static String? sourcePath() => AppPaths.defaultGameData;

  /// 跑一次导入：**同名覆盖**；模组按「同一个 mod 只留新文件」去重
  /// （不同名的旧存档 / 地图等文件保留，不做清理）
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

    //模组要去重：先扫一遍目标已装的模组，批量搬的时候复用
    final modsDirs = allModsDirsIn(to);
    final knownMods = kinds.any(_isModsKind)
        ? await scanInstalledMods(modsDirs)
        : null;

    final counts = <VersionDataKind, int>{};
    var bytes = 0;
    for (final kind in kinds) {
      final result = _isModsKind(kind)
          ? await _installMods(
              from: kind.pathIn(from),
              to: kind.pathIn(to),
              modsDirs: modsDirs,
              tempDir: p.join(to, 'tmp'),
              known: knownMods!,
            )
          : await _copyOverwrite(from: kind.pathIn(from), to: kind.pathIn(to));
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
      '本机存档一键导入 [${version.tag}]：${report.summary}'
      '（$from → $to，覆盖同名，模组只留新文件）',
      tag: 'Version',
    );
    return report;
  }

  static bool _isModsKind(VersionDataKind kind) =>
      kind == VersionDataKind.mods || kind == VersionDataKind.copperMods;

  /// 搬模组目录：能认出元数据的 mod 走 [installModFile]（同一个 mod 只留源这份，
  /// 目标已装的旧版本删掉），其余文件仍按同名覆盖拷过去
  static Future<({int files, int bytes})> _installMods({
    required String from,
    required String to,
    required List<String> modsDirs,
    required String tempDir,
    required List<InstalledModFile> known,
  }) async {
    final source = Directory(from);
    if (!await source.exists()) {
      //单项文件走原逻辑（正常不会遇到，模组类都是目录）
      return _copyOverwrite(from: from, to: to);
    }

    var files = 0;
    var bytes = 0;
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: from);
      if (entity is Directory) {
        await Directory(p.join(to, relative)).create(recursive: true);
        continue;
      }
      if (entity is! File) continue;

      try {
        final fileName = p.basename(entity.path);
        final baseName = stripDisabledModSuffix(fileName).toLowerCase();
        final isModArchive =
            baseName.endsWith('.jar') || baseName.endsWith('.zip');
        final mod = isModArchive
            ? (await FileReader.fromPath(entity.path)).mod
            : null;
        if (mod != null) {
          final installed = await installModFile(
            sourcePath: entity.path,
            mod: mod,
            targetDir: p.dirname(p.join(to, relative)),
            modsDirs: modsDirs,
            tempDir: tempDir,
            known: known,
          );
          files++;
          bytes += await File(installed.path).length();
        } else {
          final target = File(p.join(to, relative));
          await target.parent.create(recursive: true);
          await entity.copy(target.path);
          files++;
          bytes += await entity.length();
        }
      } catch (error) {
        addLog(.warning, '导入本机存档：跳过 $relative（$error）', tag: 'Version');
      }
    }
    return (files: files, bytes: bytes);
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
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
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
          addLog(.warning, '导入本机存档：跳过 $relative（$error）', tag: 'Version');
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
