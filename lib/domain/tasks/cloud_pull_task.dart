import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_mod_state.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/cloud/game_version_fill.dart';
import 'package:copper_launcher/domain/cloud/mod_fill_runner.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/tasks/cloud_sync_task.dart';
import 'package:flutter/material.dart';

/// 从云拉取：把账号下所有槽位的 head 快照同步到本机
///
/// 缺游戏版本时静默装；缺的模组也静默补，补不回来的记进 [missingMods]
class CloudPullTask extends CloudSyncTask {
  CloudPullTask({required this.accessToken})
    : super(
        direction: CloudSyncDirection.download,
        versionTag: '账号下所有存档',
        idOverride: 'cloud_pull_all',
        onRun: _run,
      );

  final String accessToken;

  /// 补不回来的模组：名字 + 原因，调用方在完成后列成一张表
  final List<({String name, String reason})> missingMods = [];

  @override
  String get displayTitle => '从云拉取';

  @override
  IconData get displayIcon => Icons.cloud_download_outlined;

  static Future<String> _run(CloudSyncTask task) =>
      (task as CloudPullTask).run();

  Future<String> run() async {
    setPhase('读取云端槽位');
    final slots = await CloudSaveService.allSlots(
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    if (slots.isEmpty) return '账号下没有云端存档';

    var synced = 0;
    var installed = 0;
    final failedSlots = <String>[];
    for (final slot in slots) {
      if (cancelToken.isCancelled) break;
      final item = CloudTaskItem(title: slot.name);
      addQueueItem(item);
      setPhase('同步 ${slot.name}');

      final release = CloudSaveService.releaseFromSlotName(slot.name);
      var version = CloudSaveService.findInstalledVersion(release);
      if (version == null) {
        final install = await _prepareVersion(release);
        if (install == null) {
          failedSlots.add('${slot.name}：版本装不上');
          updateQueueItem(item, failed: true);
          continue;
        }
        bindQueueSubTask(item, install);
        await install.startAsync();
        version = CloudSaveService.findInstalledVersion(release);
        if (version == null) {
          failedSlots.add('${slot.name}：版本装完没找到');
          updateQueueItem(item, failed: true);
          continue;
        }
        installed++;
      }

      CloudSaveService.bindSlot(version, slot.id);
      final head = slot.currentSnapshotId;
      if (head == null) {
        updateQueueItem(item, done: true);
        continue;
      }
      final report = await CloudSaveService.download(
        accessToken: accessToken,
        version: version,
        slotId: slot.id,
        snapshotId: head,
        onStatus: (state) => updateQueueItem(item, progress: state.progress),
        cancelToken: cancelToken,
      );
      await applyModEnabledStates(
        dataPath: version.dataPath,
        manifest: report.manifest,
      );
      await _fillMods(version: version, report: report);
      updateQueueItem(item, done: true);
      synced++;
    }

    final parts = ['同步 $synced 个存档'];
    if (installed > 0) parts.add('新装 $installed 个版本');
    if (missingMods.isNotEmpty) parts.add('${missingMods.length} 个模组没补回来');
    if (failedSlots.isNotEmpty) parts.add('${failedSlots.length} 个槽位失败');
    return parts.join('，');
  }

  Future<Task?> _prepareVersion(String release) async {
    setPhase('查找游戏版本 $release');
    final prep = await prepareGameVersion(
      game: CloudGameInfo(tag: release, release: release),
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

  String _reasonOf(ModFillStatus status) => switch (status) {
    ModFillStatus.notInOfficialList => '官方列表里没有',
    ModFillStatus.noSource => '找不到仓库',
    ModFillStatus.noCompiledAsset => '没有编译产物',
    ModFillStatus.incompatible => '版本不兼容',
    ModFillStatus.failed => '拉取失败',
    _ => '没补上',
  };
}
