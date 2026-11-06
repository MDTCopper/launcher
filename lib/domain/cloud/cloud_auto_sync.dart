import 'dart:async';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/sync_proxy.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/cloud_sync_task.dart';
import 'package:copper_launcher/ui/dialog/cloud_conflict_prompt.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 启动前同步里查询玩家是否要求取消；true = 在安全检查点停下本次同步
typedef SyncCancelCheck = Future<bool> Function();

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
  /// 只挡本次退出后上传；下次启动仍然重新检查、重新提醒
  static final Set<String> _skipAutoSync = {};

  static String _skipKey(Mindustry version) =>
      CloudSaveService.profileIdOf(version);

  static bool get isBusy => _pending != null;

  /// 启动前那次「查云端」最多等这么久，超了就问玩家要不要直接启动
  static const syncTimeout = Duration(seconds: 30);

  /// 启动前最多等多久账号令牌
  ///
  /// refresh 失败会重试几次，网络差时能拖十几秒；启动不该被它卡住，
  /// 等超了就按「这次不查云端」直接启动（刷新还在后台继续，下次就能用上）
  @visibleForTesting
  static Duration tokenWaitLimit = const Duration(seconds: 4);

  /// 游戏**启动前**：云端有新东西、本机没改过 ⇒ 拉下来
  ///
  /// 返回 **false = 这次别启动**（冲突没选 / 同步超时后选了取消）；出错一律返回 true
  /// （不拦启动）；覆盖前自备份由 [CloudSaveService.restore] 负责（备份做不出来会中止）
  ///
  /// [onNeedsUi] 在弹冲突 / 超时窗口前调用：快捷启动的隐藏窗口会话靠它把界面叫出来；
  /// 返回值 **false = 当前进程弹不了界面**（无界面服务），冲突直接交回 UI
  ///
  /// [isCancelled] 在检查 / 下载的安全点查询玩家取消：true = 跳过本次同步直接启动；
  /// 写存档阶段不硬停，由无界面服务的代理窗口把状态切成「正在收尾」，当前步骤结束后照常启动
  static Future<bool> beforeLaunch(
    Mindustry version, {
    Future<bool> Function()? onNeedsUi,
    SyncCancelCheck? isCancelled,
  }) async {
    try {
      if (_skipAutoSync.contains(_skipKey(version))) return true;
      // 上次上传被强杀留下的临时包 / 标记：纯本地清理，顺手提示一次
      CloudSaveService.cleanupUploadLeftovers();
      // 先恢复账号再看开关：关闭云存档的版本不该为了一个 token 等十几秒
      await AccountManager.instance.ensureRestored();
      if (!CloudSaveService.isEnabled(version)) return true;
      // 无界面服务：启动前同步超过 3 秒才拉起代理窗口；UI 进程这里返回 null
      // 把「等令牌」也算进这 3 秒里：令牌慢的时候玩家也能看到正在干什么
      final gate = await SyncProxyGate.startForHeadlessService(
        versionId: version.id,
        tag: version.tag,
      );
      try {
        final tokenWatch = Stopwatch()..start();
        await gate?.reportPhase(SyncProxyPhase.checking, message: '等待账号登录');
        final token = await _token().timeout(
          tokenWaitLimit,
          onTimeout: () => null,
        );
        if (token == null) {
          if (tokenWatch.elapsedMilliseconds >= tokenWaitLimit.inMilliseconds) {
            addLog(
              .warning,
              '等账号令牌超过 ${tokenWaitLimit.inMilliseconds}ms，'
              '跳过启动前云同步直接启动：这次按本机存档进游戏',
              tag: 'Cloud',
            );
          }
          return true;
        }
        addLog(
          .info,
          '启动前云同步：拿令牌 ${tokenWatch.elapsedMilliseconds}ms',
          tag: 'Cloud',
        );

        return await _syncBeforeLaunch(
          version,
          token: token,
          onNeedsUi: onNeedsUi,
          isCancelled: isCancelled ?? gate?.shouldStopSyncing,
          gate: gate,
        );
      } finally {
        // 成功 / 取消 / 出错都要让代理窗口收尾，不能把它留在屏幕上
        await gate?.finishLaunching();
      }
    } catch (error) {
      addLog(.warning, '云存档自动拉取失败：${removeNewlines('$error')}', tag: 'Cloud');
      return true;
    }
  }

  /// 启动前同步的主体：[beforeLaunch] 扣掉「开关 / 令牌」两道判断后
  static Future<bool> _syncBeforeLaunch(
    Mindustry version, {
    required String token,
    required Future<bool> Function()? onNeedsUi,
    required SyncCancelCheck? isCancelled,
    required SyncProxyGate? gate,
  }) async {
    await gate?.reportPhase(SyncProxyPhase.checking, message: '检查云端存档');
    if (await isCancelled?.call() ?? false) return true;

    final CloudSyncOutcome outcome;
    final syncWatch = Stopwatch()..start();
    try {
      final syncResult = await _awaitCancelable(
        CloudSaveService.syncStatus(
          accessToken: token,
          version: version,
        ).timeout(syncTimeout),
        isCancelled,
      );
      // 取消就别再等云端返回了：直接跳过本次同步
      if (syncResult.cancelled) return true;
      outcome = syncResult.value!;
      addLog(
        .info,
        '启动前云同步：查云端 ${syncWatch.elapsedMilliseconds}ms'
        '（${outcome.status.name}）',
        tag: 'Cloud',
      );
    } on TimeoutException {
      //超时：问玩家要不要直接启动（与 Steam 云一致）
      addLog(
        .warning,
        '云存档检查超时（${syncTimeout.inSeconds} 秒），问玩家要不要直接启动',
        tag: 'Cloud',
      );
      final handled = await onNeedsUi?.call() ?? true;
      if (!handled) {
        // 无界面服务：超时按设计跳过同步直接启动，不弹窗
        addLog(.warning, '无界面服务：云存档检查超时，跳过同步直接启动', tag: 'Cloud');
        return true;
      }
      return await showCloudSyncTimeoutPrompt(versionTag: version.tag);
    }
    if (await isCancelled?.call() ?? false) return true;

    final slotId = outcome.slotId;
    final snapshotId = outcome.remote?.snapshotId;

    switch (outcome.status) {
      case CloudSyncStatus.pendingDownload:
        if (slotId == null || snapshotId == null) return true;
        await gate?.reportPhase(SyncProxyPhase.downloading, message: '下载云端存档');
        addLog(.info, '云存档：启动前发现云端更新，先恢复 [${version.tag}]', tag: 'Cloud');
        final CloudSaveRestoreResult result;
        try {
          result = await _restoreWithCard(
            version: version,
            token: token,
            slotId: slotId,
            snapshotId: snapshotId,
            gate: gate,
            isCancelled: isCancelled,
          );
        } on Object catch (error) {
          // 恢复没成功就别带着半套数据启动：交回界面让玩家处理
          addLog(
            .warning,
            '云存档：启动前恢复失败，这次不启动 [${version.tag}]：'
            '${removeNewlines('$error')}',
            tag: 'Cloud',
          );
          addNotice(
            icon: Icons.error_outline,
            title: '云端存档恢复失败，这次没有启动游戏',
            content: '打开启动器重试，或从「云存档 → 备份」还原上一份',
          );
          await gate?.markNeedsUi(message: '云存档恢复失败，需要到启动器里处理');
          return false;
        }
        addNotice(
          icon: Icons.cloud_download_outlined,
          title: '已自动恢复云端存档',
          content: '写入 ${result.report.written.length} 份（覆盖前已备份）',
        );
        await _notifyRestoreGap(version, result.report);
        return true;
      case CloudSyncStatus.conflicted:
        //两边都改过：让玩家自己选；没选就**不启动**
        final handled = await onNeedsUi?.call() ?? true;
        if (!handled) {
          // 无界面服务：冲突必须由人处理，交回 UI 再启动
          addLog(.info, '无界面服务：云存档冲突，交回界面处理', tag: 'Cloud');
          await gate?.markNeedsUi(message: '云存档冲突，需要到启动器里处理');
          return false;
        }
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
          isCancelled: isCancelled,
        );
      default:
        return true;
    }
  }

  /// 等云端返回，但玩家按了取消就不等了：请求本身继续跑完，我们直接放行启动
  ///
  /// 超时 / 网络异常原样抛给调用方；取消返回 `cancelled = true`
  static Future<({bool cancelled, T? value})> _awaitCancelable<T>(
    Future<T> future,
    SyncCancelCheck? isCancelled,
  ) async {
    if (isCancelled == null) {
      return (cancelled: false, value: await future);
    }
    final result = Completer<({bool cancelled, T? value})>();
    unawaited(
      future.then<void>(
        (value) {
          if (!result.isCompleted) {
            result.complete((cancelled: false, value: value));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        },
      ),
    );
    var asking = false;
    final watcher = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (result.isCompleted || asking) return;
      asking = true;
      try {
        final cancelled = await isCancelled();
        if (cancelled && !result.isCompleted) {
          result.complete((cancelled: true, value: null));
        }
      } catch (_) {
        // 取消查询自己出错不该改变同步结果
      } finally {
        asking = false;
      }
    });
    try {
      return await result.future;
    } finally {
      watcher.cancel();
    }
  }

  /// 冲突弹窗的选择落地；返回 false = 玩家没选，调用方停止启动
  static Future<bool> _resolveConflict({
    required CloudConflictChoice choice,
    required Mindustry version,
    required String token,
    required String? slotId,
    required String? snapshotId,
    SyncCancelCheck? isCancelled,
  }) async {
    switch (choice) {
      case CloudConflictChoice.useCloud:
        if (slotId == null || snapshotId == null) return true;
        addLog(.info, '云存档冲突：玩家选择用云端覆盖本机 [${version.tag}]', tag: 'Cloud');
        final CloudSaveRestoreResult result;
        try {
          result = await _restoreWithCard(
            version: version,
            token: token,
            slotId: slotId,
            snapshotId: snapshotId,
            isCancelled: isCancelled,
          );
        } on Object catch (error) {
          addLog(
            .warning,
            '云存档冲突：用云端恢复失败，这次不启动 [${version.tag}]：'
            '${removeNewlines('$error')}',
            tag: 'Cloud',
          );
          addNotice(
            icon: Icons.error_outline,
            title: '用云端恢复失败，这次没有启动游戏',
            content: '打开启动器重试，或从「云存档 → 备份」还原上一份',
          );
          return false;
        }
        addNotice(
          icon: Icons.cloud_download_outlined,
          title: '已用云端覆盖本机',
          content: '写入 ${result.report.written.length} 份（覆盖前已备份）',
        );
        await _notifyRestoreGap(version, result.report);
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

  /// 恢复一次，并在任务抽屉里看得见
  ///
  /// 失败时把任务里捕获的原始异常抛回去，调用方按类型分支（冲突 / 网络）不用改
  ///
  /// [gate] 把恢复内部的阶段文字同步给代理窗口
  /// [isCancelled] 玩家在代理窗口取消时，取消到恢复的**下载阶段**就生效；
  /// 已经进入写存档后不再中断（写一半更糟），等它写完再启动
  static Future<CloudSaveRestoreResult> _restoreWithCard({
    required Mindustry version,
    required String token,
    required String slotId,
    required String snapshotId,
    SyncProxyGate? gate,
    SyncCancelCheck? isCancelled,
  }) async {
    CloudSaveRestoreResult? outcome;
    final syncTask = CloudSyncTask(
      direction: CloudSyncDirection.download,
      versionTag: version.tag,
      onRun: (task) async {
        Timer? cancelWatcher;
        if (isCancelled != null) {
          cancelWatcher = Timer.periodic(const Duration(milliseconds: 300), (
            _,
          ) async {
            if (task.cancelToken.isCancelled) return;
            try {
              if (await isCancelled()) task.cancel();
            } catch (_) {
              // 取消查询自己出错不该改变恢复结果
            }
          });
        }
        try {
          outcome = await CloudSaveService.restore(
            accessToken: token,
            version: version,
            slotId: slotId,
            snapshotId: snapshotId,
            onStatus: (status) {
              task.setPhase(status);
              gate?.reportRestoreStatus(status);
            },
            onProgress: task.acceptProgress,
            cancelToken: task.cancelToken,
          );
        } finally {
          cancelWatcher?.cancel();
        }
        return '写入 ${outcome!.report.written.length} 份（覆盖前已备份）';
      },
    );
    syncTask.cancelWhenLoggedOut();
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
  static Future<void> _notifyRestoreGap(
    Mindustry version,
    CloudImportReport report,
  ) async {
    final gap = computeRestoreGap(
      dataPath: version.dataPath,
      manifest: report.manifest,
      installedGameTags: installedGameIdentifiers(),
      installedModInternalNames: await installedModInternalNamesAt(
        version.dataPath,
      ),
    );
    if (gap.isEmpty) return;
    addNotice(
      icon: Icons.extension_outlined,
      title: '云端包里有本机没有的东西',
      content:
          '${describeRestoreGap(gap)}；'
          '去「云存档 → 版本云存档管理 → 云端历史版本」点「补全本机缺的」',
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
      // 同上：先恢复账号再问开关，否则无界面进程永远判成「没开」
      final token = await _token();
      if (token == null) return;
      if (!CloudSaveService.isEnabled(version)) return;
      final state = CloudSaveService.localState(version);
      if (state == null || !state.hasBaseline) {
        addLog(.info, '云存档还没有同步基线，跳过退出后上传 [${version.tag}]', tag: 'Cloud');
        return;
      }

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
      syncTask.cancelWhenLoggedOut();
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
