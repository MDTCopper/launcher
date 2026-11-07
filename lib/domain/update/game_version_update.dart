import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../data/models.dart';
import '../../data/net/data_index/data_index_client.dart';
import 'update_models.dart';

/// 游戏版本更新检查结果
class GameVersionCheck {
  const GameVersionCheck({this.updates = const [], this.error});

  /// 按版本族（正式版 / BE）各一条；本机没装过那一族时没有对应条目
  final List<GameVersionUpdate> updates;

  /// 整类检查失败的原因；非空时 [updates] 为空
  final String? error;
}

/// 游戏版本更新：对比本机版本记录与数据索引里的版本列表
///
/// 只做**提示**：远端有更新的版本时给出去下载的信息，已装版本不动
class GameVersionUpdateService {
  /// 检查远端有没有比本机新的正式版 / BE 版本
  ///
  /// [installed] 传配置里的全部版本记录（跨分类目录）；版本号取记录里的
  /// `release`，不看玩家自己改的 `tag`
  static Future<GameVersionCheck> check({
    required Iterable<Mindustry> installed,
    bool refresh = false,
  }) async {
    final remote = await DataIndexClient.loadMindustryVersions(
      refresh: refresh,
    );
    if (remote == null) {
      return const GameVersionCheck(error: '游戏版本列表拉取失败');
    }

    return GameVersionCheck(
      updates: [
        ...updatesOfFamily(isBe: false, installed: installed, remote: remote),
        ...updatesOfFamily(isBe: true, installed: installed, remote: remote),
      ],
    );
  }

  /// 某一族（正式版 / BE）的更新判定（纯函数；用例直接喂两端数据核对）
  @visibleForTesting
  static List<GameVersionUpdate> updatesOfFamily({
    required bool isBe,
    required Iterable<Mindustry> installed,
    required List<MindustryRelease> remote,
  }) {
    final remoteFamily = [
      for (final release in remote)
        if (release.isBe == isBe && release.buildNumber != null) release,
    ];
    if (remoteFamily.isEmpty) return const [];

    final latest = remoteFamily.reduce(
      (a, b) => (a.buildNumber ?? 0) >= (b.buildNumber ?? 0) ? a : b,
    );
    final latestBuild = latest.buildNumber ?? 0;

    double? installedNewestBuild;
    String? installedNewestTag;
    for (final version in installed) {
      if (version.isBe != isBe) continue;
      final build = version.releaseDouble;
      if (build <= 0) continue;
      if (installedNewestBuild == null || build > installedNewestBuild) {
        installedNewestBuild = build;
        installedNewestTag = version.displayRelease;
      }
    }

    // 本机没装过这一族：不提示「更新」（那是首次下载，不是更新）
    if (installedNewestBuild == null) return const [];

    return [
      GameVersionUpdate(
        isBe: isBe,
        installedVersion: installedNewestTag,
        latestVersion: latest.tag,
        hasUpdate: latestBuild > installedNewestBuild,
        latestRelease: latest,
      ),
    ];
  }
}
