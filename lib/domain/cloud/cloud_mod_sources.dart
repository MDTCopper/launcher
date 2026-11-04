import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/data/net/mod/mod_release.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 一个「能自己下回来」的模组：不上传字节，只记下载地址
class CloudModSource {
  const CloudModSource({
    required this.internalName,
    required this.url,
    required this.repo,
    required this.version,
    required this.fileName,
    required this.hasJava,
  });

  final String internalName;

  /// release 资产的下载地址（GitHub 的 `browser_download_url`）
  final String url;

  /// `作者/仓库`
  final String repo;

  /// 云端清单里记的版本号（用于提示与核对）
  final String version;

  /// 当时本地的文件名，恢复时沿用
  final String fileName;

  final bool hasJava;

  Map<String, dynamic> toJson() => {
    'id': internalName,
    'url': url,
    'repo': repo,
    'version': ?version.isEmpty ? null : version,
    'fileName': fileName,
    'hasJava': hasJava,
  };

  static CloudModSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final id = '${map['id'] ?? ''}'.trim();
    final url = '${map['url'] ?? ''}'.trim();
    if (id.isEmpty || url.isEmpty) return null;
    return CloudModSource(
      internalName: id,
      url: url,
      repo: '${map['repo'] ?? ''}'.trim(),
      version: '${map['version'] ?? ''}'.trim(),
      fileName: '${map['fileName'] ?? ''}'.trim(),
      hasJava: map['hasJava'] == true,
    );
  }
}

/// 随快照一起同步的「模组下载来源」清单
///
/// 服务端的 mods 元数据只有 id / name / version / sha256（多传的字段会被丢弃），
/// 所以「这个模组去哪下」只能作为一个普通文件放进快照里；文件放在数据目录根部，
/// 游戏不认这个名字，恢复后不影响加载
class CloudModSources {
  const CloudModSources(this.sources);

  static const fileName = 'cloud-mod-sources.json';

  static const _format = 'copper-mod-sources-v1';

  final List<CloudModSource> sources;

  bool get isEmpty => sources.isEmpty;

  Map<String, CloudModSource> get byInternalName => {
    for (final source in sources) source.internalName.toLowerCase(): source,
  };

  CloudModSource? sourceOf(String? internalName) {
    final key = (internalName ?? '').trim().toLowerCase();
    if (key.isEmpty) return null;
    return byInternalName[key];
  }

  Map<String, dynamic> toJson() => {
    'format': _format,
    'mods': [for (final source in sources) source.toJson()],
  };

  String encode() => jsonEncode(toJson());

  static CloudModSources? decode(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      if (map['format'] != _format) return null;
      final raw = map['mods'];
      if (raw is! List) return const CloudModSources([]);
      return CloudModSources([
        for (final item in raw)
          if (CloudModSource.fromJson(item) case final source?) source,
      ]);
    } catch (_) {
      return null;
    }
  }

  /// 数据目录里那份清单（没有 / 坏了都返回 null，不影响恢复）
  static CloudModSources? read(String dataPath) {
    final file = File(p.join(dataPath, fileName));
    if (!file.existsSync()) return null;
    try {
      return decode(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }
}

/// 上传前给「私有模组」找退路：有仓库且那个版本发过 release 的，记下载地址、不带字节
///
/// 只处理**不在官方列表里**的模组：官方列表里的恢复时本来就能按内部名找回来；
/// 列表外的模组如果没有来源就只能用云包里的字节，有来源就省一份配额
Future<CloudModSources> classifyUploadSources({
  required Iterable<CloudModEntry> mods,
  required Set<String> officialKeys,
  void Function(String status)? onStatus,
}) async {
  final sources = <CloudModSource>[];
  final releasesByRepo = <String, List<ModRelease>?>{};
  for (final mod in mods) {
    final internalName = (mod.internalName ?? '').trim();
    if (internalName.isEmpty) continue;
    final repo = (mod.source ?? '').trim();
    if (repo.isEmpty) continue;
    if (officialKeys.contains(internalName.toLowerCase()) ||
        officialKeys.contains(repo.toLowerCase())) {
      continue;
    }
    final releases = releasesByRepo[repo] ??= await _fetchReleases(repo, onStatus);
    if (releases == null || releases.isEmpty) continue;
    final release = _pickRelease(releases, mod.version);
    if (release == null) continue;
    final extension = mod.fileName.toLowerCase().endsWith('.jar')
        ? '.jar'
        : '.zip';
    final assets = release.assetsOfType(extension);
    if (assets.isEmpty) continue;
    final asset = assets.first;
    if (asset.url.trim().isEmpty) continue;
    sources.add(
      CloudModSource(
        internalName: internalName,
        url: asset.url,
        repo: repo,
        version: (mod.version ?? '').trim(),
        fileName: mod.fileName,
        hasJava: extension == '.jar',
      ),
    );
    addLog(
      .info,
      '模组可用链接恢复，不带字节：$internalName ← ${release.tag}',
      tag: 'Cloud',
    );
  }
  return CloudModSources(sources);
}

Future<List<ModRelease>?> _fetchReleases(
  String repo,
  void Function(String status)? onStatus,
) async {
  try {
    onStatus?.call('检查模组来源 $repo');
    final response = await cio.get<List>(
      'https://api.github.com/repos/$repo/releases?page=1&per_page=100',
      headers: const {'User-Agent': 'MindustryModDownloader'},
    );
    return [
      for (final item in response.data ?? const [])
        ModRelease.fromJson((item as Map).cast<String, dynamic>()),
    ];
  } catch (error) {
    addLog(
      .warning,
      '查模组 $repo 的 release 失败，按「不能网上下回来」处理：'
      '${removeNewlines('$error')}',
      tag: 'Cloud',
    );
    return null;
  }
}

/// 版本号对得上的那条 release：先完全一致 / 带 v，再比数字版本核前缀
ModRelease? _pickRelease(List<ModRelease> releases, String? version) {
  final wanted = (version ?? '').trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final release in releases) {
    for (final raw in [release.tag, release.name]) {
      final text = raw.trim().toLowerCase();
      if (text.isEmpty) continue;
      if (text == wanted || text == 'v$wanted') return release;
    }
  }
  final wantedCore = _numericCore(wanted);
  if (wantedCore == null) return null;
  for (final release in releases) {
    for (final raw in [release.tag, release.name]) {
      final core = _numericCore(raw);
      if (core == null) continue;
      if (core == wantedCore) return release;
    }
  }
  return null;
}

List<int>? _numericCore(String text) {
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(text);
  if (match == null) return null;
  return [
    for (final part in match.group(0)!.split('.')) int.tryParse(part) ?? 0,
  ];
}
