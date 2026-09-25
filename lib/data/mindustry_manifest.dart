import 'dart:convert';

import 'net_asset.dart';

/// MDTBBS（国内论坛）提供的 Mindustry 版本清单
///
/// 一次拿全量版本、支持 Range、带 sha256，且不吃 GitHub 匿名额度；
/// 结构：`games[0].releases[]`，每个 release 的 `assets[]` 里 `platform == desktop`
/// 才是游戏本体
const mindustryManifestUrl =
    'https://file.mdtbbs.cn/api/v1/mindustry/manifest.json';

/// manifest 里的 `download_url` 是相对路径，拼上它才是真实地址
const mindustryManifestBase = 'https://file.mdtbbs.cn';

/// 解析 manifest，转成与 GitHub API / 本地快照同一套的版本元数据
///
/// 下游（列表合并、下载取址）都不用改：本体地址直接指向国内源。
/// - `reactions` 补个占位：`MindustryGithubMeta.isBe` 靠它判断，缺了会被当成 BE
/// - `build_name` 是论坛预留的 release 名，没有就退回 tag
List<MindustryGithubMeta> parseMindustryManifest(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) throw const FormatException('manifest 不是对象');

  final games = decoded['games'];
  if (games is! List) throw const FormatException('manifest 缺 games');

  final releases = <MindustryGithubMeta>[];
  for (final game in games) {
    if (game is! Map || game['id'] != 'mindustry') continue;
    final list = game['releases'];
    if (list is! List) continue;
    for (final release in list) {
      final meta = _releaseToMeta(release);
      if (meta != null) releases.add(meta);
    }
  }

  if (releases.isEmpty) {
    throw const FormatException('manifest 里没有可用的 Mindustry 版本');
  }
  return releases;
}

MindustryGithubMeta? _releaseToMeta(Object? raw) {
  if (raw is! Map) return null;
  final tag = raw['tag']?.toString() ?? '';
  if (tag.isEmpty) return null;

  final assets = <Map<String, dynamic>>[];
  final rawAssets = raw['assets'];
  if (rawAssets is List) {
    for (final asset in rawAssets) {
      if (asset is! Map || asset['platform'] != 'desktop') continue;
      final path = asset['download_url']?.toString() ?? '';
      if (path.isEmpty) continue;
      assets.add({
        'name': asset['file_name']?.toString() ?? '',
        'size': (asset['size'] as num?)?.toInt() ?? 0,
        'browser_download_url': '$mindustryManifestBase$path',
        'download_count': 0,
      });
    }
  }
  // 没有桌面本体的 release 装不了，跳过
  if (assets.isEmpty) return null;

  final buildName = raw['build_name']?.toString() ?? '';
  return MindustryGithubMeta.fromJson({
    'name': buildName.isEmpty ? tag : buildName,
    'tag_name': tag,
    'published_at': raw['published_at']?.toString() ?? '',
    'body': '',
    'reactions': const {'total_count': 0},
    'assets': assets,
  });
}
