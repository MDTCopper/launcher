import 'dart:convert';

import 'release.dart';

/// 解析国内论坛（MDTBBS）的版本清单
///
/// 结构：`games[0].releases[]`，每个 release 的 `assets[]` 里只有
/// `platform == desktop` 是游戏本体；字段映射见 [MindustryRelease.fromManifestJson]
List<MindustryRelease> parseMindustryManifest(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) throw const FormatException('manifest 不是对象');

  final games = decoded['games'];
  if (games is! List) throw const FormatException('manifest 缺 games');

  final releases = <MindustryRelease>[];
  for (final game in games) {
    if (game is! Map || game['id'] != 'mindustry') continue;
    final list = game['releases'];
    if (list is! List) continue;
    for (final release in list) {
      if (release is! Map) continue;
      final parsed = MindustryRelease.fromManifestJson(
        Map<String, dynamic>.from(release),
      );
      // tag 空 / 没有桌面本体的都装不了，跳过
      if (parsed.tag.isEmpty || parsed.desktopJarAsset == null) continue;
      releases.add(parsed);
    }
  }

  if (releases.isEmpty) {
    throw const FormatException('manifest 里没有可用的 Mindustry 版本');
  }
  return releases;
}
