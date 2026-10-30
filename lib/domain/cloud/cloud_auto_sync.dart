import 'dart:async';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/cloud_sync_task.dart';
import 'package:copper_launcher/ui/dialog/cloud_conflict_prompt.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 云存档自动同步：**启动前拉、游戏退出后传、关启动器前等它传完**
///
/// - 只对「启用了云存档」的数据目录动作（开关在「概览 → 账户」）
/// - 只在**游戏不在跑**的时候动数据目录（Steam 云也是这个前提）
/// - 任何一步失败都只记日志 + 一条通知，**绝不阻断游戏启动 / 退出**
/// - 本机与云端都改过（`conflicted`）时**不替用户选**，只提示去云存档页处理
class CloudAutoSync {
  CloudAutoSync._();

  /// 正在跑的自动同步；关启动器前要等它（见 [waitForPending]）
  static Future<void>? _pending;

  /// 本次会话里玩家在冲突弹窗选了「跳过同步并启动」的 profile
  ///
  /// 只挡本次退出后上传；下次启动仍然重新检查、重新提醒。
  static final Set<String> _skipAutoSync = {};

  static String _skipKey(Mindustry version) =>
      CloudSaveService.profileIdOf(version);

  static bool get isBusy => _pending != null;

  /// 启动前那次「查云端」最多等这么久，超了就问玩家要不要直接启动
  static const syncTimeout = Duration(seconds: 30);

  /// 游戏**启动前**：云端有新东西、本机没改过 ⇒ 拉下来
  ///
  /// 返回 **false = 这次别启动**（冲突没选 / 同步超时后选了取消）；出错一律返回 true
  /// （不拦启动）。覆盖前自备份由 [CloudSaveService.restore] 负责（备份做不出来会中止）
  static Future<bool> beforeLaunch(Mindustry version) async {
    try {
      if (!CloudSaveService.isEnabled(version)) return true;
      if (_skipAutoSync.contains(_skipKey(version))) return true;
      final token = await _token();
      if (token == null) return true;

      final CloudSyncOutcome outcome;
      try {
        outcome = await CloudSaveService.syncStatus(
          accessToken: token,
          version: version,
        ).timeout(syncTimeout);
      } on TimeoutException {
        //超时：问玩家要不要直接启动（与 Steam 云一致）
        addLog(
          .warning,
          '云存档检查超时（${syncTimeout.inSeconds} 秒），问玩家要不要直接启动',
          tag: 'Cloud',
        );
        return await showCloudSyncTimeoutPrompt(versionTag: version.tag);
      }
      final slotId = outcome.slotId;
      final snapshotId = outcome.remote?.snapshotId;

      switch (outcome.status) {
        case CloudSyncStatus.pendingDownload:
          if (slotId == null || snapshotId == null) return true;
          addLog(.info, '云存档：启动前发现云端更新，先恢复 [${version.tag}]', tag: 'Cloud');
          final result = await _restoreWithCard(
            version: version,
            token: token,
            slotId: slotId,
            snapshotId: snapshotId,
          );
          addNotice(
            icon: Icons.cloud_download_outlined,
            title: '已自动恢复云端存档',
            content: '写入 ${result.report.written.length} 份（覆盖前已备份）',
          );
          _notifyRestoreGap(version, result.report);
          return true;
        case CloudSyncStatus.conflicted:
          //两边都改过：让玩家自己选；没选就**不启动**
          final choice = await showCloudConflictPrompt(
            outcome: outcome,
            versionTag: version.tag,
          );
          return await _resolveConflict(
            choice: choice,
            version: version,
            token: token,
            slotId: slotId,
            snapshotId: snapshotId,
          );
        default:
          return true;
      }
    } catch (error) {
      addLog(.warning, '云存档自动拉取失败：${removeNewlines('$error')}', tag: 'Cloud');
      return true;
    }
  }

  /// 冲突弹窗的选择落地；返回 false = 玩家没选，调用方停止启动
  static Future<bool> _resolveConflict({
    required CloudConflictChoice choice,
    required Mindustry version,
    required String token,
    required String? slotId,
    required String? snapshotId,
  }) async {
    switch (choice) {
      case CloudConflictChoice.useCloud:
        if (slotId == null || snapshotId == null) return true;
        addLog(.info, '云存档冲突：玩家选择用云端覆盖本机 [${version.tag}]', tag: 'Cloud');
        final result = await _restoreWithCard(
          version: version,
          token: token,
          slotId: slotId,
          snapshotId: snapshotId,
        );
        addNotice(
          icon: Icons.cloud_download_outlined,
          title: '已用云端覆盖本机',
          content: '写入 ${result.report.written.length} 份（覆盖前已备份）',
        );
        _notifyRestoreGap(version, result.report);
        return true;
      case CloudConflictChoice.useLocal:
        addLog(.info, '云存档冲突：玩家选择用本机覆盖云端 [${version.tag}]', tag: 'Cloud');
        final result = await CloudSaveService.upload(
          accessToken: token,
          version: version,
          reason: CloudSaveUploadReason.conflict,
          conflictPolicy: CloudSaveConflictPolicy.forceReplaceHead,
          confirmCurrentSnapshotId: snapshotId,
        );
        addNotice(
          icon: Icons.cloud_upload_outlined,
          title: '已用本机覆盖云端',
          content: '云包 ${result.archiveBytes} 字节',
        );
        return true;
      case CloudConflictChoice.skipAndLaunch:
        _skipAutoSync.add(_skipKey(version));
        addLog(.info, '云存档冲突：玩家选择跳过同步并启动 [${version.tag}]', tag: 'Cloud');
        return true;
      case CloudConflictChoice.cancel:
        addLog(.info, '云存档冲突：玩家没选，按不启动处理 [${version.tag}]', tag: 'Cloud');
        return false;
    }
  }

  /// 恢复一次，并且**让任务抽屉里看得见**（启动前那两条路以前只有日志）
  ///
  /// 失败时把任务里那次捕获的原始异常抛回去 —— 调用方按类型分支（冲突 / 网络）不用改
  static Future<CloudSaveRestoreResult> _restoreWithCard({
    required Mindustry version,
    required String token,
    required String slotId,
    required String snapshotId,
  }) async {
    CloudSaveRestoreResult? outcome;
    final syncTask = CloudSyncTask(
      direction: CloudSyncDirection.download,
      versionTag: version.tag,
      onRun: (task) async {
        outcome = await CloudSaveService.restore(
          accessToken: token,
          version: version,
          slotId: slotId,
          snapshotId: snapshotId,
          onStatus: task.setPhase,
          onProgress: task.acceptProgress,
          cancelToken: task.cancelToken,
        );
        return '写入 ${outcome!.report.written.length} 份（覆盖前已备份）';
      },
    );
    addTask(syncTask);
    await syncTask.done;

    final result = outcome;
    if (result == null) {
      throw syncTask.error ?? const MdtbbsException(message: '云端恢复被取消');
    }
    return result;
  }

  /// 恢复完顺手看一眼本机还缺什么，缺就提一句
  ///
  /// **只提示、不弹窗、不拦启动**：补全要往数据目录写模组，而这时候游戏马上要起 ——
  /// 与其跟启动抢着写，不如让用户自己在「云存档」页点
  static void _notifyRestoreGap(Mindustry version, CloudImportReport report) {
    final gap = computeRestoreGap(
      dataPath: version.dataPath,
      manifest: report.manifest,
      installedGameTags: installedGameIdentifiers(),
    );
    if (gap.isEmpty) return;
    addNotice(
      icon: Icons.extension_outlined,
      title: '云端包里有本机没有的东西',
      content: '${describeRestoreGap(gap)}；去「云存档」页可以一键补全',
    );
  }

  /// 游戏**退出后**：把本机这份传上去；关启动器前用 [waitForPending] 等它
  static Future<void> afterGameExit(Mindustry version) {
    if (_skipAutoSync.remove(_skipKey(version))) {
      addLog(.info, '云存档：本次跳过同步，退出后不上传 [${version.tag}]', tag: 'Cloud');
      return Future<void>.value();
    }
    final task = _uploadAfterExit(version);
    _pending = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_pending, task)) _pending = null;
      }),
    );
    return task;
  }

  static Future<void> _uploadAfterExit(Mindustry version) async {
    try {
      if (!CloudSaveService.isEnabled(version)) return;
      final state = CloudSaveService.localState(version);
      if (state == null || !state.hasBaseline) {
        addLog(.info, '云存档还没有同步基线，跳过退出后上传 [${version.tag}]', tag: 'Cloud');
        return;
      }
      final token = await _token();
      if (token == null) return;

      // 挂成任务：抽屉 / 托盘 / 任务栏都看得见进度，也能当场取消
      final syncTask = CloudSyncTask(
        direction: CloudSyncDirection.upload,
        versionTag: version.tag,
        onRun: (task) async {
          final result = await CloudSaveService.upload(
            accessToken: token,
            version: version,
            reason: CloudSaveUploadReason.afterExit,
            allowCreateSlot: false,
            onStatus: task.setPhase,
            onSendProgress: task.acceptBytes,
            cancelToken: task.cancelToken,
          );
          return result.alreadyUpToDate
              ? '与云端一致，没有重复上传'
              : '已上传 ${formatBytes(result.archiveBytes)}';
        },
      );
      addTask(syncTask);
      await syncTask.done;

      if (syncTask.succeeded) {
        addLog(
          .info,
          '云存档：退出后已自动上传 [${version.tag}]（${syncTask.result}）',
          tag: 'Cloud',
        );
      } else if (syncTask.error != null) {
        // 异常原样抛出去：下面按类型分支（冲突要单独那一条通知）
        throw syncTask.error!;
      } else {
        addLog(.warning, '云存档：退出后自动上传被取消 [${version.tag}]', tag: 'Cloud');
      }
    } on CloudSaveConflictException catch (error) {
      addNotice(
        icon: Icons.warning_amber_outlined,
        title: '云存档有冲突，没有自动上传',
        content: '云端这份不是本机上次传的；到「版本设置 → 云存档」里处理',
      );
      addLog(.warning, '云存档自动上传遇到冲突：${error.message}', tag: 'Cloud');
    } catch (error) {
      addNotice(
        icon: Icons.error_outline,
        title: '云存档自动上传失败',
        content: removeNewlines('$error'),
      );
      addLog(.warning, '云存档自动上传失败：${removeNewlines('$error')}', tag: 'Cloud');
    }
  }

  /// 关启动器前等自动同步跑完（最多 [timeout]，超时就先关并记一条）
  static Future<void> waitForPending({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final pending = _pending;
    if (pending == null) return;
    addLog(.info, '云存档：等自动同步传完再关启动器', tag: 'Cloud');
    try {
      await pending.timeout(timeout);
    } on TimeoutException {
      addLog(.warning, '云存档自动同步超时（${timeout.inSeconds} 秒），先关启动器', tag: 'Cloud');
    } catch (error) {
      //退出路径上绝不能因为同步失败而卡住
      addLog(.warning, '云存档自动同步收尾异常：${removeNewlines('$error')}', tag: 'Cloud');
    }
  }

  /// 拿令牌：没登录 / 没配 client_id 就当作「没开云存档」
  static Future<String?> _token() async {
    final accounts = AccountManager.instance;
    if (!accounts.isConfigured) return null;
    // restore() 会先清内存，广播一次「未登录」；联机服务正连着房间时
    // 会把这当成退出登录，直接把通道停掉（2026-10-21 实测）
    await accounts.ensureRestored();
    if (!accounts.isLoggedIn) return null;
    return accounts.ensureAccessToken();
  }
}
