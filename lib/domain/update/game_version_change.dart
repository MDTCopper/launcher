import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../data/models.dart';
import '../../data/net/data_index/data_index_client.dart';
import 'update_models.dart';

/// 游戏版本「更换版本」的结果
class GameVersionChangeCheck {
  const GameVersionChangeCheck({this.changes = const [], this.error});

  /// 按版本族（正式版 / BE）各一条；本机没装过那一族时没有对应条目
  final List<GameVersionChange> changes;

  /// 整类检查失败的原因；非空时 [changes] 为空
  final String? error;

  /// 所有族的可选版本（正式版在前、各自的版本新在前）
  Iterable<GameVersionCandidate> get candidates =>
      changes.expand((change) => change.candidates);
}

/// 游戏版本「更换版本」：列可选版本，并给出「有新版」提醒所需的事实
///
/// 更新提醒 / 通知属 UI 侧，这里只给数据：本机最高版本、远端最新版本、这一族全部可选版本
class GameVersionChangeService {
  /// 检查远端可更换的正式版 / BE 版本
  ///
  /// [installed] 传配置里的全部版本记录（跨分类目录）；版本号取记录里的 `release`，
  /// 不看玩家自己改的 `tag`
  static Future<GameVersionChangeCheck> check({
    required Iterable<Mindustry> installed,
    bool refresh = false,
  }) async {
    final remote = await DataIndexClient.loadMindustryVersions(
      refresh: refresh,
    );
    if (remote == null) {
      return const GameVersionChangeCheck(error: '游戏版本列表拉取失败');
    }

    final versions = installed.toList(growable: false);
    return GameVersionChangeCheck(
      changes: [
        ...changesOfFamily(isBe: false, installed: versions, remote: remote),
        ...changesOfFamily(isBe: true, installed: versions, remote: remote),
      ],
    );
  }

  /// 某一族（正式版 / BE）的可选版本与「有新版」判定（纯函数）
  @visibleForTesting
  static List<GameVersionChange> changesOfFamily({
    required bool isBe,
    required Iterable<Mindustry> installed,
    required List<MindustryRelease> remote,
  }) {
    final remoteFamily = [
      for (final release in remote)
        if (release.isBe == isBe && release.buildNumber != null) release,
    ]..sort((a, b) => (b.buildNumber ?? 0).compareTo(a.buildNumber ?? 0));
    if (remoteFamily.isEmpty) return const [];

    final latest = remoteFamily.first;
    final latestBuild = latest.buildNumber ?? 0;

    double? installedNewestBuild;
    String? installedNewestTag;
    final installedTags = <String>{};
    for (final version in installed) {
      if (version.isBe != isBe) continue;
      installedTags.add(_normalizedTag(version.release));

      final build = version.releaseDouble;
      if (build <= 0) continue;
      if (installedNewestBuild == null || build > installedNewestBuild) {
        installedNewestBuild = build;
        installedNewestTag = version.displayRelease;
      }
    }

    // 本机没装过这一族：没有「更换版本」的上下文，不列候选
    if (installedNewestBuild == null) return const [];

    return [
      GameVersionChange(
        isBe: isBe,
        installedVersion: installedNewestTag,
        latestVersion: latest.tag,
        hasUpdate: latestBuild > installedNewestBuild,
        latestRelease: latest,
        candidates: [
          for (final release in remoteFamily)
            GameVersionCandidate(
              release: release,
              installed: installedTags.contains(_normalizedTag(release.tag)),
              isLatest: release.tag == latest.tag,
            ),
        ],
      ),
    ];
  }

  /// 版本 tag 归一化：`v160.7` 与 `160.7` 视为同一版（BE 本来就不带 `v`）
  static String _normalizedTag(String tag) =>
      tag.trim().replaceFirst(RegExp('^v'), '');
}
