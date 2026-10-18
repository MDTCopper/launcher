import 'dart:convert';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/net/mindustry/mindustry_release.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/mindustry_download_task.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';

/// GitHub 走 API 认这个 UA（与下载页的 `gameDownloadHeaders` 同义；那几个在 UI 层）
const _defaultHeaders = {'User-Agent': 'MindustryDownloader'};

/// 从一页官方 release 里挑出云包记的那个游戏版本
///
/// 云包里记的是**发布号**（`v160.5`）与启动器内部的 tag（`v8 Build 160.5`）——
/// 前者才是 GitHub 的 tag，所以先按发布号对，顺手也认一下 tag。
/// 比较时忽略大小写与开头那个 `v`（`160.5` / `V160.5` 都算）
MindustryRelease? pickGameRelease(
  Iterable<MindustryRelease> releases,
  CloudGameInfo game,
) {
  final wantedRelease = _normalize(game.release);
  final wantedTag = _normalize(game.tag);
  if (wantedRelease.isEmpty && wantedTag.isEmpty) return null;
  for (final release in releases) {
    final tag = _normalize(release.tag);
    if (tag.isEmpty) continue;
    if (tag == wantedRelease || tag == wantedTag) return release;
  }
  return null;
}

/// 查到本体版本后准备出来的下载任务：交给调用方决定是排进任务抽屉还是就地跑
class GameVersionPrep {
  const GameVersionPrep({this.task, this.failure});

  final MindustryDownloadTask? task;

  /// 没准备出来的原因（给人看）
  final String? failure;
}

/// 查到云包记的那个本体版本、把下载任务准备好（**不启动**）
Future<GameVersionPrep> prepareGameVersion({
  required CloudGameInfo game,
  Map<String, String> headers = _defaultHeaders,
  void Function(String status)? onStatus,
}) async {
  onStatus?.call('读取游戏本体版本列表');
  final List<MindustryRelease> releases;
  try {
    // 不能直接 `cio.get<List>`：dio 只在 content-type 是 JSON 时才解，镜像节点
    // 有时回 HTML 错误页 ⇒ 拿原始串自己解（与下载页同一套防御）
    final response = await cio.get<String>(
      '$githubMindustryUrl?per_page=$mindustryVersionPageSize',
      headers: headers,
    );
    final decoded = jsonDecode('${response.data}');
    if (decoded is! List) {
      throw const FormatException('本体 release 列表不是数组');
    }
    releases = [
      for (final item in decoded)
        if (item is Map)
          MindustryRelease.fromGithubJson(item.cast<String, dynamic>()),
    ];
  } on Object catch (error) {
    addLogAndPrint(.warning, '读本体版本列表失败：$error', tag: 'Cloud');
    return GameVersionPrep(failure: '读本体版本列表失败：$error');
  }

  final release = pickGameRelease(releases, game);
  if (release == null) {
    return const GameVersionPrep(
      failure: '官方 release 列表里没有这个版本（可能太旧，已不在第一页）',
    );
  }
  return GameVersionPrep(
    task: MindustryDownloadTask(mindustryMeta: release, tag: release.tag),
  );
}

/// 把云包里那个游戏版本装回来：拉一页官方 release → 按发布号找 → 起下载任务
///
/// **返回 null = 已经排进下载队列**；返回字符串 = 没排上，内容是给人看的原因。
/// 只装**本体**：云包里的 `loaderVersion` 不在这条路上处理（加载器在版本设置里换 / 补）
Future<String?> installGameVersion({
  required CloudGameInfo game,
  Map<String, String> headers = _defaultHeaders,
  void Function(String status)? onStatus,
}) async {
  final prep = await prepareGameVersion(
    game: game,
    headers: headers,
    onStatus: onStatus,
  );
  final task = prep.task;
  if (task == null) return prep.failure;
  addTask(task);
  addLogAndPrint(.info, '补全游戏版本：${task.tag}', tag: 'Cloud');
  return null;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceFirst(RegExp('^v'), '');
