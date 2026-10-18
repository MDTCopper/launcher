import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_mod_state.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/cloud/game_version_fill.dart';
import 'package:copper_launcher/domain/cloud/mod_fill_runner.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/tasks/cloud_sync_task.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 从云拉取**一个槽位**到本机
///
/// 缺游戏版本时静默装（默认隔离）；缺的模组也静默补，补不回来的记进 [missingMods]
class CloudPullTask extends CloudSyncTask {
  CloudPullTask({required this.accessToken, required this.slot})
    : super(
        direction: CloudSyncDirection.download,
        versionTag: slot.name,
        idOverride: 'cloud_pull_${slot.id}',
        onRun: _run,
      );

  final String accessToken;
  final CloudSaveSlot slot;

  /// 补不回来的模组：名字 + 原因，调用方在完成后列成一张表
  final List<({String name, String reason})> missingMods = [];

  @override
  String get displayTitle => '从云拉取';

  @override
  IconData get displayIcon => Icons.cloud_download_outlined;

  static Future<String> _run(CloudSyncTask task) =>
      (task as CloudPullTask).run();

  Future<String> run() async {
    final item = CloudTaskItem(title: slot.name);
    addQueueItem(item);
    setPhase('同步 ${slot.name}');

    final release = CloudSaveService.releaseFromSlotName(slot.name);
    var version = CloudSaveService.findInstalledVersion(release);
    var installedNow = false;
    if (version == null) {
      final install = await _prepareVersion(release);
      if (install == null) {
        updateQueueItem(item, failed: true);
        return '版本装不上：$release';
      }
      bindQueueSubTask(item, install);
      await install.startAsync();
      version = CloudSaveService.findInstalledVersion(release);
      if (version == null) {
        updateQueueItem(item, failed: true);
        return '版本装完没找到：$release';
      }
      installedNow = true;
    }

    CloudSaveService.bindSlot(version, slot.id);
    final head = slot.currentSnapshotId;
    if (head == null) {
      updateQueueItem(item, done: true);
      return '${slot.name} 还没有快照';
    }
    final report = await CloudSaveService.download(
      accessToken: accessToken,
      version: version,
      slotId: slot.id,
      snapshotId: head,
      onStatus: (state) => updateQueueItem(item, progress: state.progress),
      cancelToken: cancelToken,
    );
    if (installedNow) {
      await _syncVersionTag(version, report.manifest.game.tag);
    }
    await applyModEnabledStates(
      dataPath: version.dataPath,
      manifest: report.manifest,
    );
    await _fillMods(version: version, report: report);
    updateQueueItem(item, done: true);

    final parts = ['已拉取 ${slot.name}'];
    if (installedNow) parts.add('新装版本 ${version.tag}');
    if (missingMods.isNotEmpty) parts.add('${missingMods.length} 个模组没补回来');
    return parts.join('，');
  }

  Future<Task?> _prepareVersion(String release) async {
    setPhase('查找游戏版本 $release');
    final prep = await prepareGameVersion(
      game: CloudGameInfo(tag: release, release: release),
      // 云拉下来的版本默认隔离：否则会落进官方默认数据目录，和别的版本共用
      isolation: true,
    );
    return prep.task;
  }

  /// 静默补这一份存档缺的模组；补不回来的记进 [missingMods]
  Future<void> _fillMods({
    required Mindustry version,
    required CloudImportReport report,
  }) async {
    final gap = computeRestoreGap(
      dataPath: version.dataPath,
      manifest: report.manifest,
      installedGameTags: installedGameIdentifiers(),
    );
    if (gap.downloadableMods.isEmpty) return;

    setPhase('补全 ${version.tag} 的模组');
    final outcomes = await fillMissingMods(
      gap: gap,
      version: version,
      queueTasks: false,
      onStatus: setPhase,
    );
    for (final outcome in outcomes) {
      if (cancelToken.isCancelled) return;
      if (!outcome.isQueued) {
        missingMods.add((
          name: outcome.displayName,
          reason: outcome.detail ?? _reasonOf(outcome.status),
        ));
        continue;
      }
      final item = CloudTaskItem(title: outcome.displayName);
      addQueueItem(item);
      final subtask = buildFillTask(outcome.plan!, version);
      bindQueueSubTask(item, subtask);
      await subtask.startAsync();
      if (subtask.status != TaskStatus.completed) {
        missingMods.add((name: outcome.displayName, reason: '下载失败'));
      }
    }
  }

  /// 装出来的版本按发布号起名，云端清单记的却是原设备的 tag（`v8 Build 160.5`）；
  /// 本次新装的版本对齐云端那份，免得两边名字对不上
  Future<void> _syncVersionTag(Mindustry version, String cloudTag) async {
    final wanted = cloudTag.trim();
    if (wanted.isEmpty || wanted == version.tag) return;
    final others = config.versionOptions.versionFolds.expand(
      (fold) => fold.versions,
    );
    if (others.any((other) => other != version && other.tag == wanted)) {
      addLog(
        .warning,
        '云端 tag [$wanted] 与已有版本重名，保留 ${version.tag}',
        tag: 'Cloud',
      );
      return;
    }
    version.tag = wanted;
    await config.saveAsJson();
    addLog(.info, '版本 tag 同步为云端的 [$wanted]', tag: 'Cloud');
  }

  String _reasonOf(ModFillStatus status) => switch (status) {
    ModFillStatus.notInOfficialList => '官方列表里没有',
    ModFillStatus.noSource => '找不到仓库',
    ModFillStatus.noCompiledAsset => '没有编译产物',
    ModFillStatus.incompatible => '版本不兼容',
    ModFillStatus.failed => '拉取失败',
    _ => '没补上',
  };
}
