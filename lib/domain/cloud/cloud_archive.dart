import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/util/io/mindustry_save_file/settings_bin_codec.dart';
import 'package:path/path.dart' as p;

/// 云包（zip 容器）：`copper-save.json` 清单 + 勾选的资源（+ 可选的模组字节）
///
/// 目录约定 —— 既是打包时的落点，也是解包时的**白名单**，清单一律说了算：
/// ```
/// copper-save.json          清单（唯一真相来源）
/// saves/<名字>.msav         存档（不含游戏自己写的 *-backup.msav）
/// maps/<名字>.msav          地图
/// schematics/<名字>.msch    蓝图
/// previews/<名字>.png       预览图（勾了才带）
/// settings/progress.json    只带模组启用状态，不整包搬 settings.bin
/// mods/manifest.json        模组清单的独立投影，方便单独看
/// mods/files/<sha256>.jar   只有「随包带字节」的模组才有（私有 / 已下架的那种）
/// ```
///
/// 存档 / 地图 / 蓝图本身已经是 zlib 压缩过的，zip 里**原样存**（不二次压缩）；
/// 模组 jar 是普通 zip，用 deflate 再压一次还有收益。
class CloudArchive {
  CloudArchive._();

  /// 清单文件名（包里的身份）
  static const manifestName = 'copper-save.json';

  /// 模组启用状态（settings.bin 的白名单投影）
  static const progressName = 'settings/progress.json';

  /// 模组清单的独立投影
  static const modsManifestName = 'mods/manifest.json';

  /// 模组字节在包里的位置（内容寻址：同一个模组只存一份）
  static String modBytesName(String sha256) => 'mods/files/$sha256.jar';

  /// 打包：扫一遍版本的数据目录，按清单勾选落成 zip
  ///
  /// [outputPath] 先写 `<outputPath>.importing` 再改名（中途出错不留半个包）；
  /// **别把云包存进游戏数据目录** —— Steam 云对 `saves/`、`maps`、`mods` 等的规则是
  /// `*`，临时文件也会被传上去占配额。
  /// 扫完到打包之间文件被改过（哈希对不上）就**宁可不打包**，记进
  /// [CloudArchiveExport.dropped]。
  static Future<CloudArchiveExport> export({
    required Mindustry version,
    required String outputPath,
    required String deviceName,
    String? account,
    bool includePreviews = false,
    bool includeModBytes = false,
    void Function(String status)? onStatus,
  }) async {
    final manifest = await CloudManifest.scan(
      version: version,
      deviceName: deviceName,
      account: account,
      includePreviews: includePreviews,
      includeModBytes: includeModBytes,
    );
    final dataPath = version.dataPath;
    final dropped = <String>[];
    final archive = Archive();

    // 清单放最前面：包读不动时也能先看出这是哪个版本的存档
    archive.add(_jsonFile(manifestName, manifest.toJson()));
    archive.add(
      _jsonFile(progressName, {
        'formatVersion': CloudManifest.formatVersion,
        'modStates': manifest.modStates,
      }),
    );
    archive.add(
      _jsonFile(modsManifestName, {
        'formatVersion': CloudManifest.formatVersion,
        'game': manifest.game.toJson(),
        'mods': [for (final mod in manifest.mods) mod.toJson()],
      }),
    );

    for (final entry in manifest.includedFiles) {
      onStatus?.call('打包 ${entry.name}');
      final source = File(p.join(dataPath, entry.category.folder, entry.name));
      final bytes = source.existsSync() ? source.readAsBytesSync() : null;
      if (bytes == null || sha256OfBytes(bytes) != entry.sha256) {
        entry.included = false;
        dropped.add('${entry.category.folder}/${entry.name}');
        continue;
      }
      archive.add(
        ArchiveFile.bytes('${entry.category.folder}/${entry.name}', bytes)
          ..compression = CompressionType.none,
      );
    }

    for (final mod in manifest.includedModBytes) {
      onStatus?.call('打包 ${mod.fileName}');
      final source = File(
        p.join(modsDirIn(dataPath, copper: mod.isCopper), mod.fileName),
      );
      final bytes = source.existsSync() ? source.readAsBytesSync() : null;
      if (bytes == null || sha256OfBytes(bytes) != mod.sha256) {
        mod.includeBytes = false;
        dropped.add('模组 ${mod.fileName}');
        continue;
      }
      archive.add(ArchiveFile.bytes(modBytesName(mod.sha256), bytes));
    }

    onStatus?.call('压缩云包');
    final zipBytes = ZipEncoder().encodeBytes(
      archive,
      level: DeflateLevel.defaultCompression,
    );
    await _writeAtomically(File(outputPath), zipBytes);

    return CloudArchiveExport(
      manifest: manifest,
      path: outputPath,
      bytes: zipBytes.length,
      includedFiles: manifest.includedFiles.map((file) => file.name).toList(),
      includedModBytes: manifest.includedModBytes
          .map((mod) => mod.fileName)
          .toList(),
      dropped: dropped,
    );
  }

  /// 只读清单，不解包（列表 / 冲突提示用）
  static Future<CloudManifest> readManifest(String archivePath) async =>
      (await CloudArchiveReader.open(archivePath)).manifest;

  static ArchiveFile _jsonFile(String name, Map<String, dynamic> content) =>
      ArchiveFile.string(name, jsonEncode(content));
}

/// 一次打包的结果
class CloudArchiveExport {
  CloudArchiveExport({
    required this.manifest,
    required this.path,
    required this.bytes,
    required this.includedFiles,
    required this.includedModBytes,
    required this.dropped,
  });

  final CloudManifest manifest;

  /// 包落在哪
  final String path;

  /// 包多大（zip 之后的体积，比 [CloudManifest.totalIncludedBytes] 小）
  final int bytes;

  final List<String> includedFiles;
  final List<String> includedModBytes;

  /// 扫完之后又变了的文件（没进包），要跟用户说一声
  final List<String> dropped;
}

/// 打开的云包：清单 + 里面的内容，按需解到本机
class CloudArchiveReader {
  CloudArchiveReader._(this.manifest, this._archive, this.bytes);

  final CloudManifest manifest;
  final Archive _archive;

  /// zip 里能认出来的资源条目（名字 + 大小），清单等三个元数据文件不算
  final Map<String, int> entries = {};
  final List<int> bytes;

  /// 随包带了字节的模组（私有模组才有可能）
  final List<CloudModEntry> carriedMods = [];

  /// 包里没有字节、得靠重新下载的模组（社区侧没有模组管理，所以只是提示）
  final List<CloudModEntry> missingMods = [];

  static Future<CloudArchiveReader> open(String archivePath) async {
    final file = File(archivePath);
    if (!file.existsSync()) throw CloudArchiveException('云包不存在：$archivePath');

    final List<int> raw;
    try {
      raw = file.readAsBytesSync();
    } catch (error) {
      throw CloudArchiveException('云包读不出来：$error');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(raw);
    } catch (error) {
      throw CloudArchiveException('不是能认的 zip：$error');
    }

    final manifestJson = _readJson(archive, CloudArchive.manifestName);
    if (manifestJson == null) {
      throw CloudArchiveException('包里没有 ${CloudArchive.manifestName}');
    }

    final manifest = CloudManifest.fromJson(manifestJson);
    // 清单里的模组启用状态是准的；万一包是别的工具写的，就从投影里补
    if (manifest.modStates.isEmpty) {
      final progress = _readJson(archive, CloudArchive.progressName);
      final states = progress?['modStates'];
      if (states is Map) {
        manifest.modStates.addAll(
          states.map((key, value) => MapEntry('$key', value == true)),
        );
      }
    }

    final reader = CloudArchiveReader._(manifest, archive, raw);
    reader._index();
    return reader;
  }

  void _index() {
    final available = <String>{};
    for (final entity in _archive) {
      if (!entity.isFile) continue;
      final name = _safeEntryName(entity.name);
      if (name == null) continue;
      available.add(name);
      if (!_metadataNames.contains(name)) {
        entries[name] = entity.size;
      }
    }

    for (final mod in manifest.mods) {
      final carried =
          mod.includeBytes &&
          available.contains(CloudArchive.modBytesName(mod.sha256));
      if (carried) {
        carriedMods.add(mod);
      } else {
        missingMods.add(mod);
      }
    }
  }

  /// 解到本机数据目录
  ///
  /// - 逐份校验 sha256，对不上的一律不落地（记进 [CloudImportReport.rejected]）；
  /// - 只写清单里点过名的东西，包里多出来的条目当没看见（也会记一笔）；
  /// - 同名文件按 [mode] 处理，**默认留两份**（`<名字>-cloud-<哈希前 8 位>.<扩展名>`）；
  /// 把云包记的模组启用状态合回本机 `settings.bin`，返回真正改动的条数
  ///
  /// **只动 `mod-<内部名>-enabled` 这几个键** —— 键位 / 画面 / 语言这些本机设置一个不碰
  /// （整份文件是「解了再编」，往返在 12 份真数据上逐字节一致）；写入走「临时文件 + 改名」，
  /// 不会留半份坏文件。本机没有 `settings.bin` 时按空文件起，游戏读不到的键用自己的默认值
  static int mergeModStates({
    required String dataPath,
    required Map<String, bool> states,
  }) {
    if (states.isEmpty) return 0;

    final path = p.join(dataPath, 'settings.bin');
    final settings = MindustrySettings.fromFile(path);

    var changed = 0;
    for (final entry in states.entries) {
      if (settings['mod-${entry.key}-enabled'] == entry.value) continue;
      settings.setModEnabled(entry.key, entry.value);
      changed++;
    }
    if (changed == 0) return 0;

    _writeAtomicallySync(
      File(path),
      SettingsBinCodec.encode(settings.data),
      // 与解包同一个理由：临时文件不能落在 Steam 云会扫的目录里
      tempDir: p.join(dataPath, 'tmp'),
    );
    return changed;
  }

  /// - 模组字节按 `isCopper` 落回 `mods/` 或 `copper/mods/`，**不认识的模组不代装**。
  Future<CloudImportReport> extractTo({
    required String dataPath,
    CloudImportMode mode = CloudImportMode.keepBoth,
  }) async {
    final report = CloudImportReport(manifest: manifest);

    // 清单点名的路径 → 该落哪儿、该是什么哈希
    final planned = <String, _PlannedFile>{};
    for (final entry in manifest.includedFiles) {
      final name = _safeName(entry.name);
      if (name == null) {
        report.rejected.add(
          CloudRejection('${entry.category.folder}/${entry.name}', '名字不合法'),
        );
        continue;
      }
      planned['${entry.category.folder}/$name'] = _PlannedFile(
        sha256: entry.sha256,
        destination: p.join(dataPath, entry.category.folder, name),
      );
    }
    for (final mod in carriedMods) {
      final name = _safeName(mod.fileName);
      if (name == null) {
        report.rejected.add(CloudRejection('模组 ${mod.fileName}', '名字不合法'));
        continue;
      }
      planned[CloudArchive.modBytesName(mod.sha256)] = _PlannedFile(
        sha256: mod.sha256,
        destination: p.join(modsDirIn(dataPath, copper: mod.isCopper), name),
      );
    }

    for (final entity in _archive) {
      if (!entity.isFile) continue;
      final name = _safeEntryName(entity.name);
      if (name == null) {
        report.rejected.add(CloudRejection(entity.name, '包里有个不安全的路径'));
        continue;
      }
      if (_metadataNames.contains(name)) continue;

      final target = planned[name];
      if (target == null) {
        report.rejected.add(CloudRejection(name, '不在清单里'));
        continue;
      }

      final Uint8List content;
      try {
        content = entity.content;
      } catch (error) {
        report.rejected.add(CloudRejection(name, '解压失败：$error'));
        continue;
      }
      if (sha256OfBytes(content) != target.sha256) {
        report.rejected.add(CloudRejection(name, '内容和清单对不上'));
        continue;
      }

      // 目的地（清单定的）与「按默认策略实际该落哪儿」；目标已有同名不同内容时两者不同
      final destination = target.destination;
      final settled = _settleDestination(destination, target.sha256, content);
      if (settled == null) {
        report.unchanged.add(destination);
        continue;
      }
      if (settled != destination) {
        switch (mode) {
          case CloudImportMode.keepBoth:
            report.keptBoth.add(settled);
          case CloudImportMode.skip:
            report.conflicts.add(destination);
            continue;
          case CloudImportMode.overwrite:
            report.overwritten.add(destination);
        }
      } else {
        report.written.add(destination);
      }
      report.writtenBytes += content.length;
      // 临时文件放数据目录的 `tmp/` —— **不能放在目标旁边**：Steam 云对
      // `saves/`、`maps`、`mods`、`schematics` 的规则是 `*`，会把半个 `.importing`
      // 也传上去、还占配额（`tmp/` 不在规则里）
      _writeAtomicallySync(
        File(mode == CloudImportMode.overwrite ? destination : settled),
        content,
        tempDir: p.join(dataPath, 'tmp'),
      );
    }

    // 清单里有、包里没有的（导出时被丢掉的那种）
    for (final entry in planned.entries) {
      if (report.rejected.any((item) => item.path == entry.key)) continue;
      final exists =
          report.written.contains(entry.value.destination) ||
          report.keptBoth.contains(entry.value.destination) ||
          report.overwritten.contains(entry.value.destination) ||
          report.unchanged.contains(entry.value.destination);
      if (!exists) {
        report.rejected.add(CloudRejection(entry.key, '包里没带这一份'));
      }
    }

    report.missingMods.addAll(missingMods);
    return report;
  }

  /// 目的地已经有东西了怎么办：内容一样就跳过，不一样就**留两份**（返回新路径）；
  /// 返回 null 表示「不用动」
  static String? _settleDestination(
    String destination,
    String sha256,
    List<int> content,
  ) {
    final existing = File(destination);
    if (!existing.existsSync()) return destination;
    if (sha256OfBytes(existing.readAsBytesSync()) == sha256) return null;

    final directory = p.dirname(destination);
    final extension = p.extension(destination);
    final base = p.basenameWithoutExtension(destination);
    final short = sha256.substring(0, 8);

    var candidate = p.join(directory, '$base-cloud-$short$extension');
    var index = 2;
    while (File(candidate).existsSync()) {
      final same = sha256OfBytes(File(candidate).readAsBytesSync()) == sha256;
      if (same) return null;
      candidate = p.join(directory, '$base-cloud-$short-$index$extension');
      index++;
    }
    return candidate;
  }

  static Map<String, dynamic>? _readJson(Archive archive, String name) {
    for (final entity in archive) {
      if (!entity.isFile || _safeEntryName(entity.name) != name) continue;
      try {
        return jsonDecode(utf8.decode(entity.content)) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static const _metadataNames = {
    CloudArchive.manifestName,
    CloudArchive.progressName,
    CloudArchive.modsManifestName,
  };
}

/// 同名但内容不同时怎么办（`extractTo` 的 [CloudImportMode]）
///
/// 默认**留两份** —— 解包本身绝不静默覆盖；[overwrite] 只给「恢复云端快照」这种
/// 明确要盖掉本机的场景，调用方必须先自己备份
enum CloudImportMode {
  /// 另存一份 `<名字>-cloud-<哈希前 8 位>.<扩展名>`，本机那份不动
  keepBoth,

  /// 跳过，记进 [CloudImportReport.conflicts]
  skip,

  /// 直接覆盖本机那份
  overwrite,
}

/// 解包报告：谁落了地、谁被留下当第二份、谁没进来
class CloudImportReport {
  CloudImportReport({required this.manifest});

  final CloudManifest manifest;

  /// 落地的绝对路径
  final List<String> written = [];

  /// 内容一模一样，跳过没动的
  final List<String> unchanged = [];

  /// 同名但内容不同，留了第二份
  final List<String> keptBoth = [];

  /// 同名但内容不同，被覆盖掉的本机文件（[CloudImportMode.overwrite]）
  final List<String> overwritten = [];

  /// 同名但内容不同，[CloudArchiveReader.extractTo] 传了 [CloudImportMode.skip]
  final List<String> conflicts = [];

  /// 没进来的（路径不安全 / 哈希不符 / 不在清单里 / 包里没带）
  final List<CloudRejection> rejected = [];

  /// 包里没有字节、要靠重新下载的模组
  final List<CloudModEntry> missingMods = [];

  int writtenBytes = 0;

  /// 合回本机 `settings.bin` 的模组启用状态条数（见 [CloudArchiveReader.mergeModStates]）
  int appliedModStates = 0;

  /// 一个文件都没落地、也没被拒 —— 说明本机已经是这个包的样子了
  bool get isNoop => written.isEmpty && keptBoth.isEmpty && overwritten.isEmpty;
}

/// 被拒的条目与原因（给用户看的）
class CloudRejection {
  const CloudRejection(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => '$path：$reason';
}

class CloudArchiveException implements Exception {
  const CloudArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PlannedFile {
  const _PlannedFile({required this.sha256, required this.destination});

  final String sha256;
  final String destination;
}

/// 包内条目名一律用 `/`，统一按 posix 规整
String? _safeEntryName(String name) {
  final normalized = p.posix.normalize(name.replaceAll('\\', '/'));
  if (normalized.isEmpty || normalized == '.') return null;
  if (p.posix.isAbsolute(normalized)) return null;
  if (normalized == '..' || normalized.startsWith('../')) return null;
  return normalized;
}

/// 文件自己的名字：不能带目录、不能是相对跳出去的（存档名是游戏侧的身份，只认裸名）
String? _safeName(String name) {
  if (name.isEmpty) return null;
  if (name.contains('/') || name.contains('\\')) return null;
  if (name == '.' || name == '..') return null;
  return name;
}

Future<void> _writeAtomically(File target, List<int> bytes) async {
  target.parent.createSync(recursive: true);
  final temporary = File('${target.path}.importing');
  await temporary.writeAsBytes(bytes, flush: true);
  if (target.existsSync()) target.deleteSync();
  await temporary.rename(target.path);
}

void _writeAtomicallySync(File target, List<int> bytes, {String? tempDir}) {
  target.parent.createSync(recursive: true);
  final directory = tempDir ?? target.parent.path;
  Directory(directory).createSync(recursive: true);
  final temporary = File(
    p.join(directory, '${p.basename(target.path)}.importing'),
  );
  temporary.writeAsBytesSync(bytes, flush: true);
  if (target.existsSync()) target.deleteSync();
  temporary.renameSync(target.path);
}
