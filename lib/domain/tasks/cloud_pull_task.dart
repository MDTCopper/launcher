import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_gap_fill.dart';
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
    addLog(
      .info,
      '从云拉取 [$slot.name]：槽位 ${slot.id}，绑定 ${boundProfile ?? '无'}，'
      '发布号 $release',
      tag: 'Cloud',
    );
    final targetProfile = boundProfile ?? (isDefaultSlot ? 'default' : null);
    var version = targetProfile == null
        ? null
        : CloudSaveService.versionOfProfile(targetProfile);
    var needBind = targetProfile == null;
    var installedNow = false;
    String? staleProfile;
    if (version == null) {
      if (isDefaultSlot) {
        // 默认存档的槽位名里没有发布号，装不出游戏版本
        updateQueueItem(item, failed: true);
        return '默认存档没有对应的本机版本：先在主页选好一个游戏版本再拉取';
      }
      // 实例已不在：先记下旧 profile，装好新实例再作废，装失败不弄丢原绑定
      final stale = (boundProfile != null && boundProfile != 'default')
          ? boundProfile
          : null;
      staleProfile = stale;
      if (stale != null) {
        addLog(
          .warning,
          '拉取 [$slot.name]：绑定 $stale 对应的实例已不在，按新实例处理',
          tag: 'Cloud',
        );
      }
      final prep = await _prepareVersion(release, isolation: !isDefaultSlot);
      if (prep.task == null) {
        updateQueueItem(item, failed: true);
        final reason = prep.failure ?? '未知原因';
        addLog(
          .warning,
          '拉取 [$slot.name]：游戏版本 $release 装不上（$reason）',
          tag: 'Cloud',
        );
        return '版本装不上：$release（$reason）';
      }
      bindQueueSubTask(item, prep.task!);
      await prep.task!.startAsync();
      version = isDefaultSlot
          ? (CloudSaveService.versionOfProfile('default') ??
                CloudSaveService.findInstalledVersion(release))
          : CloudSaveService.findInstalledVersion(release);
      if (version == null) {
        updateQueueItem(item, failed: true);
        addLog(
          .warning,
          '拉取 [$slot.name]：游戏版本装完却没找到 $release',
          tag: 'Cloud',
        );
        return '版本装完没找到：$release';
      }
      installedNow = true;
      needBind = !isDefaultSlot;
      addLog(.info, '拉取 [$slot.name]：新装版本 ${version.tag}', tag: 'Cloud');
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
    // 新实例绑好才作废旧 profile，中途失败原绑定还在
    if (needBind && staleProfile != null) {
      CloudSaveService.discardProfileBinding(staleProfile);
    }
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

  Future<GameVersionPrep> _prepareVersion(
    String release, {
    required bool isolation,
  }) async {
    setPhase('查找游戏版本 $release');
    return prepareGameVersion(
      // 新实例 tag 用游戏版本号，避免被设备名 / 云端名污染
      game: CloudGameInfo(tag: release, release: release),
      // 非默认云存档新建隔离实例；默认存档用默认数据目录
      isolation: isolation,
    );
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

    missingMods.addAll(
      await fillGapMods(
        gap: gap,
        version: version,
        onStatus: setPhase,
        isCancelled: () => cancelToken.isCancelled,
        enqueue: (outcome) async {
          final item = CloudTaskItem(title: outcome.displayName);
          addQueueItem(item);
          final subtask = buildFillTask(outcome.plan!, version);
          bindQueueSubTask(item, subtask);
          await subtask.startAsync();
          return subtask.status == TaskStatus.completed;
        },
      ),
    );
  }

}
