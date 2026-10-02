import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/mindustry_save_file/settings_bin_codec.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 云存档里的一类小文件
enum CloudCategory {
  save('saves', '存档'),
  map('maps', '地图'),
  schematic('schematics', '蓝图'),
  preview('previews', '预览图');

  const CloudCategory(this.folder, this.label);

  /// 数据目录下的目录名，也是云包里的目录名
  final String folder;
  final String label;
}

/// 云端包对应的游戏版本：一个 tag 一个包
///
/// 恢复时靠它判断「本机有没有这个版本」、并做兼容性提示（配合包里的 mod 清单）
class CloudGameInfo {
  const CloudGameInfo({
    required this.tag,
    required this.release,
    this.build,
    this.isBe = false,
    this.loaderVersion,
  });

  /// 版本记录里的 tag（`v8 Build 160.5`），也是云包的身份
  final String tag;

  /// 官方发布号（`v160.5`）或 BE 的构建号（`27898`）
  final String release;

  /// 写这份存档的游戏 build
  final int? build;
  final bool isBe;

  /// 走 Copper 加载器时的 loader 版本（跟包里的 mod 一起决定能不能开）
  final String? loaderVersion;

  factory CloudGameInfo.fromVersion(Mindustry version) => CloudGameInfo(
    tag: version.tag,
    release: version.release,
    build: version.versionNumber ?? version.releaseInt,
    isBe: version.isBe,
    loaderVersion: LoaderLibraryVersion.of(version),
  );

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'release': release,
    if (build != null) 'build': build,
    'isBe': isBe,
    if (loaderVersion != null) 'loaderVersion': loaderVersion,
  };

  factory CloudGameInfo.fromJson(Map<String, dynamic> json) => CloudGameInfo(
    tag: '${json['tag'] ?? ''}',
    release: '${json['release'] ?? ''}',
    build: json['build'] is int ? json['build'] as int : null,
    isBe: json['isBe'] == true,
    loaderVersion: json['loaderVersion'] as String?,
  );
}

/// 包里的一个文件（存档 / 地图 / 蓝图 / 预览图）
class CloudFileEntry {
  CloudFileEntry({
    required this.category,
    required this.name,
    required this.size,
    required this.sha256,
    this.meta,
    this.included = true,
  });

  final CloudCategory category;

  /// 文件名（含扩展名）—— 游戏侧就是拿名字当身份，没有 UUID
  final String name;
  final int size;
  final String sha256;

  /// 能解析出来的元数据（存档/地图给 `MapSave.fromJson`，蓝图尽力而为）
  final Map<String, dynamic>? meta;

  /// 用户勾选：这次要不要进云
  bool included;

  /// 存档/地图的元数据；读不出来返回 null
  MapSave? get mapSave {
    final values = meta;
    if (values == null) return null;
    try {
      return MapSave.fromJson(values);
    } catch (_) {
      return null;
    }
  }

  /// 游戏自己写的存档时刻（判新旧用这个，别看文件 mtime）
  DateTime? get savedAt {
    final millis = mapSave?.saved ?? 0;
    if (millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'name': name,
    'size': size,
    'sha256': sha256,
    if (meta != null) 'meta': meta,
    if (!included) 'included': false,
  };

  factory CloudFileEntry.fromJson(Map<String, dynamic> json) => CloudFileEntry(
    category: CloudCategory.values.firstWhere(
      (value) => value.name == json['category'],
      orElse: () => CloudCategory.save,
    ),
    name: '${json['name'] ?? ''}',
    size: json['size'] is int ? json['size'] as int : 0,
    sha256: '${json['sha256'] ?? ''}',
    meta: (json['meta'] as Map?)?.cast<String, dynamic>(),
    included: json['included'] != false,
  );
}

/// 包里的一个模组
///
/// **默认只记清单不传字节**：能从启动器现有下载链路（官方仓库 / 作者仓库）拿回来的，
/// 记 `{内部名, 版本, 文件名, sha256}` 就够；拿不回来的（私有 / 已下架）才需要
/// [includeBytes] 随包带字节 —— 社区侧没有 mod 管理，所以只有这两条路
class CloudModEntry {
  CloudModEntry({
    required this.fileName,
    required this.size,
    required this.sha256,
    required this.isCopper,
    this.internalName,
    this.displayName,
    this.version,
    this.enabled,
    this.includeBytes = false,
  });

  final String fileName;
  final int size;
  final String sha256;

  /// Copper 原生模组（`copper/mods/`）还是原版模组（`mods/`）
  final bool isCopper;

  /// 与 Mindustry settings 键 `mod-<内部名>-enabled` 对齐
  final String? internalName;
  final String? displayName;
  final String? version;

  /// 打包时它在本地是不是启用着（要跟着云包走，否则恢复出来「装了但没生效」）
  final bool? enabled;

  /// 是否随包带字节（私有模组只能这样备份）
  bool includeBytes;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'size': size,
    'sha256': sha256,
    'isCopper': isCopper,
    if (internalName != null) 'internalName': internalName,
    if (displayName != null) 'displayName': displayName,
    if (version != null) 'version': version,
    if (enabled != null) 'enabled': enabled,
    if (includeBytes) 'includeBytes': true,
  };

  factory CloudModEntry.fromJson(Map<String, dynamic> json) => CloudModEntry(
    fileName: '${json['fileName'] ?? ''}',
    size: json['size'] is int ? json['size'] as int : 0,
    sha256: '${json['sha256'] ?? ''}',
    isCopper: json['isCopper'] == true,
    internalName: json['internalName'] as String?,
    displayName: json['displayName'] as String?,
    version: json['version'] as String?,
    enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
    includeBytes: json['includeBytes'] == true,
  );
}

/// 一份可同步的清单：**一个游戏版本 tag + 它的资源（存档 / 地图 / 蓝图 / 模组）**
///
/// 只描述「有什么、多大、什么哈希、谁的版本」，不含字节 —— 打包/上传按它来，
/// 恢复也按它落地（文件按 [CloudFileEntry.sha256] 校验，模组按 [CloudModEntry] 补齐）
class CloudManifest {
  CloudManifest({
    required this.game,
    required this.exportedAt,
    required this.deviceName,
    this.account,
    this.isIsolated = true,
    List<CloudFileEntry>? files,
    List<CloudModEntry>? mods,
    Map<String, bool>? modStates,
  }) : files = files ?? [],
       mods = mods ?? [],
       modStates = modStates ?? {};

  /// 容器格式版本：以后改结构就靠它做兼容
  static const formatVersion = 1;

  final CloudGameInfo game;
  final DateTime exportedAt;

  /// 导出这台设备的名字（冲突提示里说「另一台设备 X 传的」）
  final String deviceName;
  final String? account;

  /// 数据目录是否独占（未开版本隔离时多个 tag 共用一份，云端包语义会乱 ⇒ 建议要求隔离）
  final bool isIsolated;

  final List<CloudFileEntry> files;
  final List<CloudModEntry> mods;

  /// 模组启用状态（内部名 → 是否启用），来自 `settings.bin`
  final Map<String, bool> modStates;

  List<CloudFileEntry> get includedFiles => [
    for (final file in files)
      if (file.included) file,
  ];

  int get includedBytes =>
      includedFiles.fold(0, (sum, file) => sum + file.size);

  /// 这次要随包带字节的模组（私有模组），它们的体积也要算进配额
  List<CloudModEntry> get includedModBytes => [
    for (final mod in mods)
      if (mod.includeBytes) mod,
  ];

  int get totalIncludedBytes =>
      includedBytes + includedModBytes.fold(0, (sum, mod) => sum + mod.size);

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'game': game.toJson(),
    'exportedAt': exportedAt.toIso8601String(),
    'deviceName': deviceName,
    if (account != null) 'account': account,
    'isIsolated': isIsolated,
    'files': [for (final file in files) file.toJson()],
    'mods': [for (final mod in mods) mod.toJson()],
    if (modStates.isNotEmpty) 'modStates': modStates,
  };

  factory CloudManifest.fromJson(Map<String, dynamic> json) => CloudManifest(
    game: CloudGameInfo.fromJson(
      (json['game'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    exportedAt:
        DateTime.tryParse('${json['exportedAt']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    deviceName: '${json['deviceName'] ?? ''}',
    account: json['account'] as String?,
    isIsolated: json['isIsolated'] != false,
    files: [
      for (final item in (json['files'] as List? ?? const []))
        if (item is Map) CloudFileEntry.fromJson(item.cast<String, dynamic>()),
    ],
    mods: [
      for (final item in (json['mods'] as List? ?? const []))
        if (item is Map) CloudModEntry.fromJson(item.cast<String, dynamic>()),
    ],
    modStates: ((json['modStates'] as Map?) ?? const {}).map(
      (key, value) => MapEntry('$key', value == true),
    ),
  );

  /// 扫一遍这个版本的数据目录，生成清单（**纯本地，不联网**）
  ///
  /// [includeModBytes] 为 true 时把模组字节也算成「随包带」（私有模组没法重新下载）；
  /// [includePreviews] 为 true 时把游戏生成的预览图也带上
  static Future<CloudManifest> scan({
    required Mindustry version,
    required String deviceName,
    String? account,
    bool includeModBytes = false,
    bool includePreviews = false,
  }) async {
    final dataPath = version.dataPath;
    final settings = _readModStates(dataPath);

    final files = <CloudFileEntry>[];
    for (final category in CloudCategory.values) {
      if (category == CloudCategory.preview && !includePreviews) continue;
      files.addAll(
        await _scanFolder(
          directory: p.join(dataPath, category.folder),
          category: category,
        ),
      );
    }

    final mods = <CloudModEntry>[];
    for (final isCopper in [false, true]) {
      mods.addAll(
        await _scanMods(
          directory: modsDirIn(dataPath, copper: isCopper),
          isCopper: isCopper,
          states: settings,
          includeBytes: includeModBytes,
        ),
      );
    }

    return CloudManifest(
      game: CloudGameInfo.fromVersion(version),
      exportedAt: DateTime.now(),
      deviceName: deviceName,
      account: account,
      isIsolated: version.isolation,
      files: files,
      mods: mods,
      modStates: settings,
    );
  }

  /// 扫一个分类目录：认得出的读 meta，认不出的也照样进清单（只带哈希与大小）
  static Future<List<CloudFileEntry>> _scanFolder({
    required String directory,
    required CloudCategory category,
  }) async {
    final folder = Directory(directory);
    if (!folder.existsSync()) return const [];

    final entries = <CloudFileEntry>[];
    for (final entity in folder.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // 游戏自己生成的「上一代」备份不算第二份存档（它自己也从列表里跳过）
      if (name.contains('backup')) continue;

      Map<String, dynamic>? meta;
      try {
        final reader = await FileReader.fromPath(entity.path);
        meta = reader.meta;
      } catch (_) {
        meta = null;
      }

      entries.add(
        CloudFileEntry(
          category: category,
          name: name,
          size: entity.lengthSync(),
          sha256: sha256OfFile(entity.path),
          meta: meta,
        ),
      );
    }
    return entries;
  }

  /// 扫一个模组目录：能解析出元数据就带上内部名/版本，好跟 settings 与官方源对上
  static Future<List<CloudModEntry>> _scanMods({
    required String directory,
    required bool isCopper,
    required Map<String, bool> states,
    required bool includeBytes,
  }) async {
    final folder = Directory(directory);
    if (!folder.existsSync()) return const [];

    final entries = <CloudModEntry>[];
    for (final entity in folder.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // loader 的核心模组是运行时的一部分，不进云
      if (name.startsWith('copper-core')) continue;

      Mod? mod;
      try {
        final reader = await FileReader.fromPath(entity.path);
        if (reader.type == ResourceType.mod && reader.meta != null) {
          mod = Mod.fromJson(reader.meta!);
        }
      } catch (_) {
        mod = null;
      }

      entries.add(
        CloudModEntry(
          fileName: name,
          size: entity.lengthSync(),
          sha256: sha256OfFile(entity.path),
          isCopper: isCopper,
          internalName: mod?.internalName,
          displayName: mod?.name,
          version: mod?.version,
          enabled: mod == null ? null : (states[mod.internalName] ?? true),
          includeBytes: includeBytes,
        ),
      );
    }
    return entries;
  }

  /// 从 `settings.bin` 读模组启用状态（`mod-<内部名>-enabled`）
  static Map<String, bool> _readModStates(String dataPath) {
    final file = File(p.join(dataPath, 'settings.bin'));
    if (!file.existsSync()) return {};
    try {
      final settings = SettingsBinCodec.decode(file.readAsBytesSync());
      const prefix = 'mod-';
      const suffix = '-enabled';
      final states = <String, bool>{};
      for (final entry in settings.entries) {
        final key = entry.key;
        if (!key.startsWith(prefix) || !key.endsWith(suffix)) continue;
        final name = key.substring(prefix.length, key.length - suffix.length);
        if (name.isEmpty || entry.value is! bool) continue;
        states[name] = entry.value as bool;
      }
      return states;
    } catch (_) {
      return {};
    }
  }
}

/// 文件的 sha256（清单的完整性凭据）
String sha256OfFile(String path) => sha256OfBytes(File(path).readAsBytesSync());

/// 一段字节的 sha256（打包 / 解包逐份校验都用它）
String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

/// 走加载器的版本才有 loader 版本号（就从记录里的 jar 文件名读，与库内复用同口径）
class LoaderLibraryVersion {
  LoaderLibraryVersion._();

  static String? of(Mindustry version) {
    final path = version.resolvedLauncherPath;
    if (path == null || path.isEmpty) return null;
    final matched = RegExp(
      r'(\d+(?:\.\d+)*)$',
    ).firstMatch(p.basenameWithoutExtension(path));
    return matched?.group(1);
  }
}
