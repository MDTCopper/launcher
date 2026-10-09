import 'dart:async';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/ui/dialog/cloud_conflict_prompt.dart';
import 'package:copper_launcher/ui/util/notification.dart';
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

  static bool get isBusy => _pending != null;

  /// 游戏**启动前**：云端有新东西、本机没改过 ⇒ 拉下来
  ///
  /// 返回 **false = 这次别启动**（冲突弹窗玩家没选）；出错一律返回 true（不拦启动）。
  /// 覆盖前自备份由 [CloudSaveService.restore] 负责（备份做不出来它会中止）
  static Future<bool> beforeLaunch(Mindustry version) async {
    try {
      if (!CloudSaveService.isEnabled(version)) return true;
      final token = await _token();
      if (token == null) return true;

      final outcome = await CloudSaveService.syncStatus(
        accessToken: token,
        version: version,
      );
      final slotId = outcome.slotId;
      final snapshotId = outcome.remote?.snapshotId;

      switch (outcome.status) {
        case CloudSyncStatus.pendingDownload:
          if (slotId == null || snapshotId == null) return true;
          addLog(.info, '云存档：启动前发现云端更新，先恢复 [${version.tag}]', tag: 'Cloud');
          final result = await CloudSaveService.restore(
            accessToken: token,
            version: version,
            slotId: slotId,
            snapshotId: snapshotId,
          );
          addNotice(
            icon: Icons.cloud_download_outlined,
            title: '已自动恢复云端存档',
            content: '写入 ${result.report.written.length} 份（覆盖前已备份）',
          );
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
        final result = await CloudSaveService.restore(
          accessToken: token,
          version: version,
          slotId: slotId,
          snapshotId: snapshotId,
        );
        addNotice(
          icon: Icons.cloud_download_outlined,
          title: '已用云端覆盖本机',
          content: '写入 ${result.report.written.length} 份（覆盖前已备份）',
        );
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
      case CloudConflictChoice.cancel:
        addLog(.info, '云存档冲突：玩家没选，按不启动处理 [${version.tag}]', tag: 'Cloud');
        return false;
    }
  }

  /// 游戏**退出后**：把本机这份传上去；关启动器前用 [waitForPending] 等它
  static Future<void> afterGameExit(Mindustry version) {
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
      final token = await _token();
      if (token == null) return;

      final result = await CloudSaveService.upload(
        accessToken: token,
        version: version,
        reason: CloudSaveUploadReason.afterExit,
      );
      addLog(
        .info,
        '云存档：退出后已自动上传 [${version.tag}]（${result.archiveBytes} 字节）',
        tag: 'Cloud',
      );
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
    await accounts.restore();
    if (!accounts.isLoggedIn) return null;
    return accounts.ensureAccessToken();
  }
}
