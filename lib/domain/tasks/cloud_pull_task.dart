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
import 'package:copper_launcher/util/format/string_cleaner.dart';
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
    final isDefaultSlot =
        slot.name.contains('默认存档') ||
        CloudSaveService.profileIdBoundToSlot(slot.id) == 'default';
    final boundProfile = CloudSaveService.profileIdBoundToSlot(slot.id);
    final targetProfile = boundProfile ?? (isDefaultSlot ? 'default' : null);
    var version = targetProfile == null
        ? null
        : CloudSaveService.versionOfProfile(targetProfile);
    var needBind = targetProfile == null;
    var installedNow = false;
    if (version == null) {
      // 绑定在但实例已经不在了：旧 profile 作废，按「没有实例」新建一个
      if (boundProfile != null && boundProfile != 'default') {
        CloudSaveService.discardProfileBinding(boundProfile);
      }
      final install = await _prepareVersion(
        release,
        isolation: !isDefaultSlot,
      );
      if (install == null) {
        updateQueueItem(item, failed: true);
        return '版本装不上：$release';
      }
      bindQueueSubTask(item, install);
      await install.startAsync();
      version = isDefaultSlot
          ? (CloudSaveService.versionOfProfile('default') ??
                CloudSaveService.findInstalledVersion(release))
          : CloudSaveService.findInstalledVersion(release);
      if (version == null) {
        updateQueueItem(item, failed: true);
        return '版本装完没找到：$release';
      }
      installedNow = true;
      needBind = !isDefaultSlot;
      // 新实例优先采用云端 boundTag，保证本地绑定与云端槽位名一致
      final cloudTag = CloudSaveService.boundTagOfSlotName(slot.name);
      if (!isDefaultSlot &&
          cloudTag != null &&
          cloudTag.isNotEmpty &&
          cloudTag != version.tag) {
        try {
          await CloudSaveService.adoptCloudTag(version, cloudTag);
        } catch (error) {
          addLog(
            .warning,
            '新实例采用云端标签失败，保留 ${version.tag}：${removeNewlines('$error')}',
            tag: 'Cloud',
          );
        }
      }
    }

    if (needBind) CloudSaveService.bindSlot(version, slot.id);
    final head = slot.currentSnapshotId;
    if (head == null) {
      updateQueueItem(item, done: true);
      return '${slot.name} 还没有快照';
    }
    final restored = await CloudSaveService.restore(
      accessToken: accessToken,
      version: version,
      slotId: slot.id,
      snapshotId: head,
      onStatus: setPhase,
      onProgress: (state) => updateQueueItem(item, progress: state.progress),
      cancelToken: cancelToken,
    );
    final report = restored.report;
    await applyModEnabledStates(
      dataPath: version.dataPath,
      manifest: report.manifest,
    );
    // 默认数据目录那份不补全游戏：它就是本机现有数据，补全没有意义
    if (version.isolation) {
      await _fillMods(version: version, report: report);
    }
    updateQueueItem(item, done: true);

    final parts = ['已拉取 ${slot.name}', '写入 ${version.dataPath}'];
    if (installedNow) parts.add('新装版本 ${version.tag}');
    if (missingMods.isNotEmpty) parts.add('${missingMods.length} 个模组没补回来');
    return parts.join('，');
  }

  Future<Task?> _prepareVersion(String release, {required bool isolation}) async {
    setPhase('查找游戏版本 $release');
    final prep = await prepareGameVersion(
      // 新实例 tag 用游戏版本号；不再用槽位名，避免实例 tag 被设备 / 云端名污染
      game: CloudGameInfo(tag: release, release: release),
      // 非默认云存档新建隔离实例；默认存档用默认数据目录
      isolation: isolation,
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
          reason: outcome.detail ?? modFillReason(outcome.status),
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

}
