import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/domain/preview/blueprint_asset_pack.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/mindustry_save_file/save_file_codec.dart';
import 'package:copper_launcher/util/io/mindustry_save_file/schematic_file.dart';
import 'package:path/path.dart' as p;

/// 蓝图库中的一个本地蓝图
class BlueprintLibraryEntry {
  BlueprintLibraryEntry({
    required this.version,
    required this.path,
    required this.name,
    required this.author,
    required this.width,
    required this.height,
    required this.fileSize,
    required this.modifiedAt,
    required this.cacheKey,
    this.hasModContent,
  });

  /// 所属游戏版本；本机共享数据目录里的条目为 null
  final Mindustry? version;

  /// `.msch` 完整路径
  final String path;

  final String name;

  /// `.msch` 没有 author tag 时为空串
  final String author;

  final int width;
  final int height;
  final int fileSize;
  final DateTime modifiedAt;

  /// 文件内容指纹：路径 + mtime + 大小 + 缓存格式版本
  final String cacheKey;

  /// 含资产包内容表里没有的方块（mod / 旧版本）；null 表示尚未与资产包比对
  bool? hasModContent;

  /// 版本标签；共享目录条目落到 [BlueprintLibrary.sharedVersionTag]
  String get versionTag => version?.tag ?? BlueprintLibrary.sharedVersionTag;
}

/// 本地蓝图索引
///
/// 扫所有版本的 `schematics` 目录，外加本机共享数据目录（`%APPDATA%\Mindustry` 那类）的同名目录；
/// 同一路径只保留第一条，按修改时间倒序
class BlueprintLibrary {
  BlueprintLibrary._();

  /// 不属于任何版本记录的蓝图（来自本机共享数据目录）
  static const String sharedVersionTag = '全局';

  /// 缓存格式版本：渲染规则或缓存布局变化时 +1，让旧预览 PNG 失效
  static const int cacheFormatVersion = 1;

  /// 扫描本地全部蓝图
  ///
  /// [versions] 不传时取当前配置里的全部版本记录；离屏脚本可显式传入
  /// [assetPacks] 传入已经加载的资产包（按版本标签索引）时顺带判定 [BlueprintLibraryEntry.hasModContent]；
  /// 没传的版本保持 null
  static Future<List<BlueprintLibraryEntry>> scan({
    List<Mindustry>? versions,
    Map<String, BlueprintAssetPack> assetPacks = const {},
  }) async {
    final entries = <BlueprintLibraryEntry>[];
    final visitedPaths = <String>{};
    for (final version in versions ?? _versions().toList()) {
      await _scanDirectory(
        version.schematicsPath,
        version: version,
        entries: entries,
        visitedPaths: visitedPaths,
        assetPacks: assetPacks,
      );
    }
    final sharedDataPath = AppPaths.defaultGameData;
    if (sharedDataPath != null) {
      await _scanDirectory(
        p.join(sharedDataPath, 'schematics'),
        version: null,
        entries: entries,
        visitedPaths: visitedPaths,
        assetPacks: assetPacks,
      );
    }
    entries.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return entries;
  }

  /// 资产包里找不到这些方块名即视为含 mod 内容
  static bool hasUnknownBlocks(
    Iterable<String> blockNames,
    BlueprintAssetPack assets,
  ) {
    for (final name in blockNames) {
      if (assets.block(name) == null) return true;
    }
    return false;
  }

  static Iterable<Mindustry> _versions() sync* {
    for (final fold in config.versionOptions.versionFolds) {
      yield* fold.versions;
    }
  }

  static Future<void> _scanDirectory(
    String dirPath, {
    required Mindustry? version,
    required List<BlueprintLibraryEntry> entries,
    required Set<String> visitedPaths,
    required Map<String, BlueprintAssetPack> assetPacks,
  }) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) return;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.msch')) {
          continue;
        }
        final normalizedPath = p
            .normalize(p.absolute(entity.path))
            .toLowerCase();
        if (!visitedPaths.add(normalizedPath)) continue;
        final entry = await _readEntry(entity, version, assetPacks);
        if (entry != null) entries.add(entry);
      }
    } on FileSystemException catch (error) {
      addLog(
        .warning,
        '扫描蓝图目录失败 [$dirPath]：${error.message}',
        tag: 'BlueprintPreview',
      );
    }
  }

  static Future<BlueprintLibraryEntry?> _readEntry(
    File file,
    Mindustry? version,
    Map<String, BlueprintAssetPack> assetPacks,
  ) async {
    try {
      final bytes = await file.readAsBytes();
      final meta = SaveFileCodec.decodeSchematic(bytes);
      final stat = await file.stat();
      final rawName = (meta['name'] as String?)?.trim() ?? '';
      final entry = BlueprintLibraryEntry(
        version: version,
        path: file.path,
        name: rawName.isEmpty ? p.basenameWithoutExtension(file.path) : rawName,
        author: (meta['author'] as String?)?.trim() ?? '',
        width: (meta['width'] as num?)?.toInt() ?? 0,
        height: (meta['height'] as num?)?.toInt() ?? 0,
        fileSize: bytes.length,
        modifiedAt: stat.modified,
        cacheKey: _cacheKey(file.path, stat.modified, bytes.length),
      );
      final assets = assetPacks[entry.versionTag];
      if (assets != null) {
        entry.hasModContent = _detectModContent(bytes, assets);
      }
      return entry;
    } catch (error) {
      // 目录里可能混入坏文件 / 半截下载，跳过而不是中断整次扫描
      addLog(
        .warning,
        '跳过无法解析的蓝图 [${p.basename(file.path)}]：$error',
        tag: 'BlueprintPreview',
      );
      return null;
    }
  }

  static bool? _detectModContent(Uint8List bytes, BlueprintAssetPack assets) {
    try {
      final schematic = SchematicFile.fromBytes(bytes);
      return hasUnknownBlocks(schematic.blockNames, assets);
    } on FormatException {
      return null;
    }
  }

  static String _cacheKey(String path, DateTime modifiedAt, int fileSize) {
    final input =
        '$path|${modifiedAt.millisecondsSinceEpoch}|$fileSize|$cacheFormatVersion';
    final first = _fnv32(input, 0x811C9DC5);
    final second = _fnv32(input, 0x01000193);
    return first.toRadixString(16).padLeft(8, '0') +
        second.toRadixString(16).padLeft(8, '0');
  }

  static int _fnv32(String input, int seed) {
    var hash = seed;
    for (final unit in input.codeUnits) {
      hash = (hash ^ unit) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
