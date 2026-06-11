import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/util/io/mindustry_save_file/save_file_codec.dart';
import 'package:copperlauncher_main/util/io/mindustry_save_file/settings_bin_codec.dart';
import 'package:hjson_dart/hjson_dart.dart';
import 'package:path/path.dart' as p;
import 'package:properties/properties.dart';

/// 可识别的资源类型。
enum ResourceType {
  /// Mindustry 游戏 jar/apk
  mindustry,

  /// Mod (jar/zip 内含 mod.json 或 mod.hjson)
  mod,

  /// 地图存档 (.msav)
  mapSave,

  /// 蓝图 (.msch)
  schematic,

  /// 设置文件 (settings.bin)
  settings,
}

/// 底层文件格式。
enum FileFormat {
  /// ZIP/JAR 压缩包
  zip,

  /// zlib 压缩的 MSAV 地图存档
  msav,

  /// msch 蓝图文件
  msch,

  /// 二进制文件 (settings.bin 等)
  bin,

  /// 未知格式
  other,
}

/// 统一文件读取器 — 通过文件头字节识别类型，解析元数据，支持导入。
///
/// ```dart
/// final reader = await FileReader.fromPath(path);
/// print(reader.type);   // ResourceType.mod
/// print(reader.meta);   // {displayName: ..., version: ...}
/// await reader.importTo('/dest/dir');
/// ```
class FileReader {
  /// 源文件路径。
  final String path;

  /// 文件名（含扩展名）。
  final String fileName;

  /// 识别出的资源类型，无法识别时为 null。
  final ResourceType? type;

  /// 底层文件格式。
  final FileFormat fileFormat;

  /// 解析出的元数据。
  final Map<String, dynamic>? meta;

  FileReader._({
    required this.path,
    required this.fileName,
    required this.type,
    required this.fileFormat,
    required this.meta,
  }) {
    meta?['path'] = path;
  }

  // ── 工厂：从路径创建 ──

  /// 读取并解析文件，返回带元数据的 [FileReader]。
  ///
  /// 若文件不存在或无法读取，返回 `type=null, meta=null` 的空实例。
  static Future<FileReader> fromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return FileReader._(
        path: path,
        fileName: p.basename(path),
        type: null,
        fileFormat: FileFormat.other,
        meta: null,
      );
    }

    final bytes = await file.readAsBytes();
    return _fromBytes(bytes, path);
  }

  /// 从字节数组解析。
  static FileReader _fromBytes(Uint8List bytes, String path) {
    final fileName = p.basename(path);
    final header = bytes.length >= 8 ? bytes.sublist(0, 8) : bytes;

    // 优先检查 MSAV（zlib 头）
    final mapMeta = _tryMapMeta(bytes, header);
    if (mapMeta != null) {
      return FileReader._(
        path: path,
        fileName: fileName,
        type: ResourceType.mapSave,
        fileFormat: FileFormat.msav,
        meta: mapMeta,
      );
    }

    // 检查 msch 蓝图
    final schemMeta = _trySchematicMeta(bytes, header);
    if (schemMeta != null) {
      return FileReader._(
        path: path,
        fileName: fileName,
        type: ResourceType.schematic,
        fileFormat: FileFormat.msch,
        meta: schemMeta,
      );
    }

    // 检查 settings.bin
    final settingsMeta = _trySettingsMeta(bytes, header);
    if (settingsMeta != null) {
      return FileReader._(
        path: path,
        fileName: fileName,
        type: ResourceType.settings,
        fileFormat: FileFormat.bin,
        meta: settingsMeta,
      );
    }

    // 检查 ZIP/JAR
    if (_isZip(header)) {
      final modMeta = _tryModMeta(bytes);
      if (modMeta != null) {
        return FileReader._(
          path: path,
          fileName: fileName,
          type: ResourceType.mod,
          fileFormat: FileFormat.zip,
          meta: modMeta,
        );
      }

      final gameMeta = _tryGameMeta(bytes);
      if (gameMeta != null) {
        return FileReader._(
          path: path,
          fileName: fileName,
          type: ResourceType.mindustry,
          fileFormat: FileFormat.zip,
          meta: gameMeta,
        );
      }
    }

    // 无法识别
    return FileReader._(
      path: path,
      fileName: fileName,
      type: null,
      fileFormat: FileFormat.other,
      meta: null,
    );
  }

  // ── 导入操作 ──

  /// 将文件复制到目标目录。
  /// [destDir] 目标目录路径。
  /// [overwrite] 是否覆盖同名文件，默认 false。
  /// 返回复制后的完整路径，若不成功返回 null。
  Future<String?> importTo(String destDir, {bool overwrite = false}) async {
    try {
      final dir = Directory(destDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final destPath = p.join(destDir, fileName);
      final destFile = File(destPath);

      if (await destFile.exists()) {
        if (!overwrite) return null;
        await destFile.delete();
      }

      await File(path).copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // 头部检测
  // ═══════════════════════════════════════════

  static bool _isZip(Uint8List header) {
    // PK\x03\x04
    return header.length >= 4 &&
        header[0] == 0x50 &&
        header[1] == 0x4B &&
        header[2] == 0x03 &&
        header[3] == 0x04;
  }

  static bool _isZlib(Uint8List header) {
    // 78 01 / 78 5E / 78 9C / 78 DA
    return header.length >= 2 &&
        header[0] == 0x78 &&
        (header[1] == 0x01 ||
            header[1] == 0x5E ||
            header[1] == 0x9C ||
            header[1] == 0xDA);
  }

  static bool _isMsch(Uint8List header) {
    // 'msch' = 6D 73 63 68
    return header.length >= 4 &&
        header[0] == 0x6D &&
        header[1] == 0x73 &&
        header[2] == 0x63 &&
        header[3] == 0x68;
  }

  // ═══════════════════════════════════════════
  // 各类型解析
  // ═══════════════════════════════════════════

  /// 尝试解析为 .msav 地图存档。
  static Map<String, dynamic>? _tryMapMeta(Uint8List bytes, Uint8List header) {
    if (!_isZlib(header)) return null;
    try {
      return SaveFileCodec.decodeMapMeta(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 尝试解析为 .msch 蓝图。
  static Map<String, dynamic>? _trySchematicMeta(
    Uint8List bytes,
    Uint8List header,
  ) {
    if (!_isMsch(header)) return null;
    try {
      return SaveFileCodec.decodeSchematic(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 尝试解析为 settings.bin。
  static Map<String, dynamic>? _trySettingsMeta(
    Uint8List bytes,
    Uint8List header,
  ) {
    // settings.bin 前 2 字节可能是 00 00 或 zlib 头 (78 xx)
    if (!_isZlib(header) && !(header[0] == 0x00 && header[1] == 0x00)) {
      return null;
    }
    try {
      final data = SettingsBinCodec.decode(bytes);
      // 只提取常见的用户可读设置项作为元数据
      return {
        'locale': data['locale'] ?? 'default',
        'uiscale': data['uiscale'] ?? 100,
        'fpscap': data['fpscap'] ?? 240,
        'lastBuild': data['lastBuild'] ?? 0,
      };
    } catch (_) {
      return null;
    }
  }

  /// 从 ZIP 中解析 mod 元数据（查找 mod.json 或 mod.hjson）。
  static Map<String, dynamic>? _tryModMeta(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final modFile = archive.files.cast<ArchiveFile?>().firstWhere((f) {
        if (f == null) return false;
        final parts = f.name.split('/');
        if (parts.length > 2) return false;
        final name = parts.last;
        return name == 'mod.json' || name == 'mod.hjson';
      }, orElse: () => null);

      if (modFile == null) return null;

      final content = utf8.decode(
        modFile.content as List<int>,
        allowMalformed: true,
      );
      final map = hjsonDecode(content, strict: false) as Map<String, dynamic>;
      map['type'] = 'mod';

      // 检测 Java mod：有 META-INF/ 目录，或有 .class 文件，或 mod.json 中有 main 字段
      final isJava =
          archive.files.cast<ArchiveFile?>().any((f) {
            if (f == null) return false;
            final name = f.name;
            return name.startsWith('META-INF/') || name.endsWith('.class');
          }) &&
          map.containsKey('main');

      if (isJava) map['java'] = true;

      return map;
    } catch (_) {
      return null;
    }
  }

  /// 从 ZIP/JAR 中解析游戏版本元数据（查找 version.properties）。
  static Map<String, dynamic>? _tryGameMeta(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // 先找根目录的 version.properties
      var file = archive.findFile('version.properties');
      // 再找 assets/version.properties
      file ??= archive.findFile('assets/version.properties');

      if (file == null) return null;

      final p = Properties.fromString(utf8.decode(file.content as List<int>));
      final meta = jsonDecode(p.toJSON()) as Map<String, dynamic>;
      meta['type'] = 'mindustry';
      return meta;
    } catch (_) {
      return null;
    }
  }

  // ── 类型化 getter ──

  /// 转为 [MapSave]，仅在 type 为 mapSave 时有效。
  MapSave? get mapSave =>
      type == ResourceType.mapSave && meta != null
          ? MapSave.fromJson(meta!)
          : null;

  /// 转为 [Schematic]，仅在 type 为 schematic 时有效。
  Schematic? get schematic =>
      type == ResourceType.schematic && meta != null
          ? Schematic.fromJson(meta!)
          : null;

  Mod? get mod =>
      type == ResourceType.mod && meta != null ? Mod.fromJson(meta!) : null;

  MindustryMeta? get mindustry =>
      type == ResourceType.mindustry && meta != null
          ? MindustryMeta.fromJson(meta!)
          : null;

  @override
  String toString() =>
      'FileReader($fileName, type=$type, meta=${meta?.keys.join(',')})';
}
