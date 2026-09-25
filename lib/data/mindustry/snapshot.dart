import 'dart:convert';

import 'release.dart';

/// 官方版本列表快照（`remote/mindustry_versions.json`）
///
/// 快照存的是不会变的历史版本，字段是 GitHub release 对象的精简版
/// （见 `.script/generate_mindustry_versions.dart`），所以解析与 API 共用
/// [MindustryRelease.fromGithubJson]；启动时取最新一页补上新版本
class MindustryVersionSnapshot {
  /// 解析快照内容，格式不对 / 单条损坏时返回能解析出来的部分
  static List<MindustryRelease> parse(String? content) {
    if (content == null || content.trim().isEmpty) return const [];

    final List<dynamic>? releases;
    try {
      final decoded = jsonDecode(content);
      releases = decoded is Map<String, dynamic>
          ? decoded['releases'] as List<dynamic>?
          : decoded as List<dynamic>?;
    } catch (_) {
      return const [];
    }
    if (releases == null) return const [];

    final versions = <MindustryRelease>[];
    for (final release in releases) {
      try {
        versions.add(
          MindustryRelease.fromGithubJson(release as Map<String, dynamic>),
        );
      } catch (_) {
        // 单条坏了跳过，不拖垮整份快照
      }
    }
    return versions;
  }

  /// 合并快照与最新列表：同 tag 以最新那份为准（列表也更新），快照补老版本
  static List<MindustryRelease> merge(
    List<MindustryRelease> snapshot,
    List<MindustryRelease> latest,
  ) {
    final latestTags = {for (final version in latest) version.tag};
    return [
      ...latest,
      for (final version in snapshot)
        if (!latestTags.contains(version.tag)) version,
    ];
  }
}
