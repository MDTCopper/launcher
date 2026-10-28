import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_cloud_save_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_auto_sync.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_mod_state.dart';
import 'package:copper_launcher/domain/cloud/cloud_notes.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/cloud/game_version_fill.dart';
import 'package:copper_launcher/domain/cloud/mod_fill_runner.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/cloud_pull_task.dart';
import 'package:copper_launcher/domain/tasks/cloud_sync_task.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/components/tips/warning_bar.dart';
import 'package:copper_launcher/ui/dialog/cloud_backup_prompt.dart';
import 'package:copper_launcher/ui/dialog/cloud_restore_gap_prompt.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/dialog/missing_mods_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

const versionCloudSavePageRouteKey = '/cloud_save/version';

/// 版本设置里的「云存档」页：**这一个版本**的云端槽位与快照
///
/// 同步单元是**数据目录**不是版本：页面认路由参数里的那份版本（没带参数就退回
/// 当前选中版本），云端槽位绑的是它的数据目录（见 `CloudSaveService`）
///
/// **加载时不创建槽位** —— 建槽要占配额，是用户点「上传」才做的事
class VersionCloudSavePage extends StatefulWidget {
  const VersionCloudSavePage({super.key});

  @override
  State<VersionCloudSavePage> createState() => _VersionCloudSavePageState();
}

/// 这份数据目录上次拉到的状态：再进页面先用它渲染，再后台刷新
class _CloudPageCacheEntry {
  _CloudPageCacheEntry({
    required this.slot,
    required this.snapshots,
    required this.estimate,
    required this.quota,
  });

  final CloudSaveSlot? slot;
  final List<CloudSaveSnapshot> snapshots;
  final CloudUploadEstimate? estimate;
  final CloudSaveQuota? quota;
}

final Map<String, _CloudPageCacheEntry> _cloudPageCache = {};

class _VersionCloudSavePageState extends State<VersionCloudSavePage> {
  CloudSaveSlot? _slot;
  List<CloudSaveSnapshot> _snapshots = const [];

  bool _loading = false;
  String? _error;

  /// 正在进行的动作（登录 / 上传 / 恢复）的文案；null 表示空闲
  String? _busy;

  /// 上传进度 0–1

  /// 这次操作哪个版本：路由参数（版本设置里带过来的那份）优先
  Mindustry? get _selectedVersion =>
      (ModalRoute.of(context)?.settings.arguments as Map?)?['version']
          as Mindustry? ??
      config.versionOptions.selectedVersion;

  /// 上传前的预算：这次大概多大（清单合计、未压缩）与云端还剩多少
  CloudUploadEstimate? _estimate;
  CloudSaveQuota? _quota;

  /// 本次恢复里没补回来的模组：完成后列成一张表
  List<({String name, String reason})> _restoreMissingMods = [];

  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    // 首帧之后再拉：登录态与网络都是异步的，别在 build 里起
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  // ── 数据 ──

  /// 拉一遍这个版本的云端槽位与快照历史
  Future<void> _reload() async {
    if (!_accounts.isConfigured) {
      setState(() => _error = null);
      return;
    }

    final version = _selectedVersion;
    final cacheKey = version?.dataPath;
    final cached = cacheKey == null ? null : _cloudPageCache[cacheKey];
    if (cached != null) {
      setState(() {
        _slot = cached.slot;
        _snapshots = cached.snapshots;
        _estimate = cached.estimate;
        _quota = cached.quota;
        _loading = false;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _accounts.ensureRestored();
      if (!_accounts.isLoggedIn) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _slot = null;
          _snapshots = const [];
        });
        return;
      }

      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        throw const MdtbbsException(message: '登录已失效，请重新登录');
      }

      // 只查不建：没有槽位就是「这个版本还没传过」
      final version = _selectedVersion;
      final slot = version == null
          ? null
          : await CloudSaveService.findSlot(
              accessToken: token,
              version: version,
            );
      final snapshots = slot == null
          ? const <CloudSaveSnapshot>[]
          : (await CloudSaveService.snapshots(
              accessToken: token,
              slotId: slot.id,
            )).snapshots;

      // 预算：两个都失败也不影响这页（只记日志）
      CloudUploadEstimate? estimate;
      if (version != null) {
        // 官方列表里没有的模组会随包带字节，预算要按同一口径算
        Set<String> officialKeys = const {};
        try {
          officialKeys = await officialModKeys();
        } on Object catch (error) {
          addLog(
            .warning,
            '读官方列表失败，预算按不带模组字节算：${removeNewlines('$error')}',
            tag: 'Cloud',
          );
        }
        try {
          estimate = await CloudSaveService.estimateUpload(
            version,
            includeBytesWhen: officialKeys.isEmpty
                ? null
                : (mod) => !_isOfficialMod(mod, officialKeys),
          );
        } catch (error) {
          addLog(.warning, '算本机清单体积失败：${removeNewlines('$error')}', tag: 'Cloud');
        }
      }
      CloudSaveQuota? quota;
      try {
        quota = await CloudSaveService.quota(accessToken: token);
      } catch (error) {
        addLog(.warning, '读云端配额失败：${removeNewlines('$error')}', tag: 'Cloud');
      }

      if (!mounted) return;
      if (cacheKey != null) {
        _cloudPageCache[cacheKey] = _CloudPageCacheEntry(
          slot: slot,
          snapshots: snapshots,
          estimate: estimate,
          quota: quota,
        );
      }
      setState(() {
        _loading = false;
        _slot = slot;
        _snapshots = snapshots;
        _estimate = estimate;
        _quota = quota;
      });
    } on MdtbbsException catch (error) {
      if (!mounted) return;
      if (cached != null) {
        addLog(.warning, '刷新云存档状态失败：$error', tag: 'Cloud');
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } catch (error) {
      if (!mounted) return;
      if (cached != null) {
        addLog(.warning, '刷新云存档状态失败：$error', tag: 'Cloud');
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _error = removeNewlines('$error');
      });
    }
  }

  // ── 动作 ──

  /// 上传当前版本的数据目录
  ///
  /// [confirmCurrentSnapshotId] 只在「冲突后用户选了强制覆盖」时给：
  /// 服务端要求强制覆盖必须报出它确认的那个当前快照 ID
  void _upload({String? confirmCurrentSnapshotId}) {
    final version = _selectedVersion;
    if (version == null) return;

    showConfirmationPopup(
      context: context,
      type: ConfirmationType.notification,
      title: '上传到云端？',
      content:
          '把「${version.tag}」的数据目录打包传到云端，会新建一个快照。\n'
          '只读本机文件，不会改动它们。',
      action: () => _runUpload(
        version: version,
        confirmCurrentSnapshotId: confirmCurrentSnapshotId,
      ),
    );
  }

  Future<void> _runUpload({
    required Mindustry version,
    String? confirmCurrentSnapshotId,
  }) async {
    setState(() {
      _busy = '准备上传…';
    });

    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        throw const MdtbbsException(message: '登录已失效，请重新登录');
      }

      CloudSaveUploadResult? uploaded;
      final task = CloudSyncTask(
        direction: CloudSyncDirection.upload,
        versionTag: version.tag,
        idOverride: 'cloud_sync_manual_upload_${version.tag}',
        onRun: (task) async {
          // 官方列表里没有的模组（私有 / 已下架）恢复时装不回来，直接把字节带上
          var officialKeys = const <String>{};
          try {
            task.setPhase('检查官方列表');
            officialKeys = await officialModKeys();
          } on Object catch (error) {
            addLog(
              .warning,
              '读官方列表失败，私有模组这次不带字节：${removeNewlines('$error')}',
              tag: 'Cloud',
            );
          }
          uploaded = await CloudSaveService.upload(
            accessToken: token,
            version: version,
            conflictPolicy: confirmCurrentSnapshotId == null
                ? CloudSaveConflictPolicy.normal
                : CloudSaveConflictPolicy.forceReplaceHead,
            confirmCurrentSnapshotId: confirmCurrentSnapshotId,
            includeBytesWhen: officialKeys.isEmpty
                ? null
                : (mod) => !_isOfficialMod(mod, officialKeys),
            onStatus: task.setPhase,
            onSendProgress: task.acceptBytes,
            cancelToken: task.cancelToken,
          );
          return '云包 ${formatBytes(uploaded!.archiveBytes)}';
        },
      );
      addTask(task);
      if (mounted) setState(() => _busy = '上传中（任务列表可取消）');
      await task.done;

      if (!mounted) return;
      if (task.status == TaskStatus.cancel) {
        addNotice(icon: Icons.close, title: '已取消上传');
        return;
      }
      if (task.error != null) {
        final error = task.error;
        if (error is MdtbbsException && error.isConflict) {
          _askForceReplace(error.conflictCurrentSnapshotId);
        } else {
          addNotice(
            icon: Icons.error_outline,
            title: '上传失败',
            content: removeNewlines('$error'),
          );
        }
        return;
      }

      final result = uploaded!;
      final dropped = result.dropped;
      final guard = result.quotaGuard;
      final parts = <String>[
        '云包 ${formatBytes(result.archiveBytes)}',
        if (dropped.isNotEmpty) '有 ${dropped.length} 个文件在打包时被改动过，没进包',
        // 空间不够时我们自己删了旧快照，得说出来（不然用户不知道历史少了版本）
        if (guard.cleaned)
          '云端空间不够，已清理 ${guard.deletedSnapshots} 个旧快照、腾出 ${formatBytes(guard.freedBytes)}',
        if (guard.remainingBytes != null)
          '云端还剩 ${formatBytes(guard.remainingBytes!)}',
      ];
      addNotice(
        icon: Icons.cloud_upload_outlined,
        title: '已上传到云端',
        content: parts.join('；'),
      );
      await _reload();
    } on MdtbbsException catch (error) {
      if (!mounted) return;
      if (error.isConflict) {
        _askForceReplace(error.conflictCurrentSnapshotId);
      } else {
        addNotice(
          icon: Icons.error_outline,
          title: '上传失败',
          content: removeNewlines('$error'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '上传失败',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
            });
      }
    }
  }

  /// 云端 head 比本机新（多半是另一台设备传过）：让用户决定要不要盖掉
  void _askForceReplace(String? currentSnapshotId) {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '云端已有更新的版本',
      content:
          '云端这份不是本机上次传的那份（可能是另一台设备传的）。\n'
          '继续会用本机这份覆盖云端当前版本；云端旧版本仍留在历史里，可以恢复',
      action: () => _runUpload(
        version: _selectedVersion!,
        confirmCurrentSnapshotId: currentSnapshotId,
      ),
    );
  }

  void _restore(CloudSaveSnapshot snapshot) {
    final version = _selectedVersion;
    if (version == null) return;

    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '用云端这份覆盖本机？',
      content:
          '把云端第 ${snapshot.revision ?? '?'} 版解到本机数据目录。\n'
          '同名且内容不同的文件会**留两份**（新那份带 -cloud- 后缀），'
          '本机原有文件不动。\n\n'
          '${CloudNotes.gameRunningHint}',
      action: () => _runRestore(version: version, snapshot: snapshot),
    );
  }

  Future<void> _runRestore({
    required Mindustry version,
    required CloudSaveSnapshot snapshot,
  }) async {
    setState(() => _busy = '准备恢复…');
    _restoreMissingMods = [];
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        throw const MdtbbsException(message: '登录已失效，请重新登录');
      }

      CloudImportReport? restored;
      final task = CloudSyncTask(
        direction: CloudSyncDirection.download,
        versionTag: version.tag,
        idOverride: 'cloud_sync_manual_download_${version.tag}',
        onRun: (task) async {
          // 队列里的第一项就是恢复本身；补全 / 装本体会往后加，总体进度按权重算
          final restoreItem = CloudTaskItem(title: '恢复云端存档');
          task.setQueue([restoreItem]);
          task.setPhase('下载云端快照');
          restored = await CloudSaveService.download(
            accessToken: token,
            version: version,
            slotId: snapshot.slotId ?? _slot!.id,
            snapshotId: snapshot.id,
            onStatus: (state) =>
                task.updateQueueItem(restoreItem, progress: state.progress),
            cancelToken: task.cancelToken,
          );
          task.updateQueueItem(restoreItem, done: true);
          final report = restored!;
          final extra = await _handleRestoreGapInsideTask(
            report: report,
            version: version,
            task: task,
          );
          await applyModEnabledStates(
            dataPath: version.dataPath,
            manifest: report.manifest,
          );
          final summary = _restoreSummary(report);
          return extra.isEmpty ? summary : '$summary；$extra';
        },
      );
      addTask(task);
      if (mounted) setState(() => _busy = '恢复中（任务列表可取消）');
      await task.done;

      if (!mounted) return;
      if (task.status == TaskStatus.cancel) {
        addNotice(icon: Icons.close, title: '已取消恢复');
        return;
      }
      if (task.error != null) {
        addNotice(
          icon: Icons.error_outline,
          title: '恢复失败',
          content: removeNewlines('${task.error}'),
        );
        return;
      }
      addNotice(
        icon: Icons.cloud_download_outlined,
        title: '已从云端恢复',
        content: task.result ?? '',
      );
      if (_restoreMissingMods.isNotEmpty) {
        await showMissingModsDialog(context, _restoreMissingMods);
      }
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '恢复失败',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 官方列表里有它（按仓库或内部名）
  bool _isOfficialMod(CloudModEntry mod, Set<String> keys) {
    final internal = (mod.internalName ?? '').trim().toLowerCase();
    final source = (mod.source ?? '').trim().toLowerCase();
    return (internal.isNotEmpty && keys.contains(internal)) ||
        (source.isNotEmpty && keys.contains(source));
  }

  /// 恢复完在**同一张任务卡**里处理缺口：模组静默补，只问要不要装游戏版本
  ///
  /// 补全的下载不另起任务卡，进度直接反馈到这张卡上
  Future<String> _handleRestoreGapInsideTask({
    required CloudImportReport report,
    required Mindustry version,
    required CloudSyncTask task,
  }) async {
    final gap = computeRestoreGap(
      dataPath: version.dataPath,
      manifest: report.manifest,
      installedGameTags: installedGameIdentifiers(),
    );
    if (gap.isEmpty || !mounted) return '';

    final notes = <String>[];
    await _fillModsSilently(gap: gap, version: version, task: task);

    final missingGame = gap.missingGame;
    if (missingGame != null && mounted) {
      // 本体比模组重得多：先占位，再问要不要装
      final placeholder = CloudTaskItem(
        title: '游戏本体 ${missingGame.release}',
        weight: 5,
      );
      task.addQueueItem(placeholder);
      task.setPhase('等待选择要不要装游戏版本');
      final choice = await showRestoreGapPrompt(
        gap: gap,
        version: version,
        versionTag: version.tag,
        offerModFill: false,
        offerGameInstall: true,
      );
      if (choice == CloudRestoreGapChoice.installGame) {
        task.setPhase('查找游戏版本');
        final prep = await prepareGameVersion(game: missingGame);
        final installTask = prep.task;
        if (installTask == null) {
          task.removeQueueItem(placeholder);
          notes.add(prep.failure ?? '装游戏版本失败');
        } else {
          task.setPhase('下载游戏版本 ${missingGame.release}');
          task.bindQueueSubTask(placeholder, installTask);
          await installTask.startAsync();
          if (installTask.status != TaskStatus.completed) {
            throw StateError(
              '本体没下完：${installTask.statusLabel ?? installTask.status.name}',
            );
          }
          task.updateQueueItem(placeholder, done: true);
          notes.add('已装游戏版本 ${missingGame.release}');
        }
      } else {
        task.removeQueueItem(placeholder);
      }
    }
    return notes.join('；');
  }

  /// 静默补一份存档缺的模组；补不回来的记进 [_restoreMissingMods]
  Future<void> _fillModsSilently({
    required CloudRestoreGap gap,
    required Mindustry version,
    required CloudSyncTask task,
  }) async {
    if (gap.downloadableMods.isEmpty) return;

    // 先占位，避免恢复跑满 100% 后等列表那几秒停在 100%
    final placeholder = CloudTaskItem(
      title: '补全模组（读取列表…）',
      weight: gap.downloadableMods.length.toDouble(),
    );
    task.addQueueItem(placeholder);
    task.setPhase('补全模组…');
    final outcomes = await fillMissingMods(
      gap: gap,
      version: version,
      queueTasks: false,
      onStatus: task.setPhase,
    );
    task.removeQueueItem(placeholder);

    for (final outcome in outcomes) {
      if (task.cancelToken.isCancelled) return;
      if (!outcome.isQueued) {
        _restoreMissingMods.add((
          name: outcome.displayName,
          reason: outcome.detail ?? modFillReason(outcome.status),
        ));
        continue;
      }
      final item = CloudTaskItem(title: outcome.displayName);
      task.addQueueItem(item);
      final subtask = buildFillTask(outcome.plan!, version);
      task.bindQueueSubTask(item, subtask);
      await subtask.startAsync();
      if (subtask.status != TaskStatus.completed) {
        _restoreMissingMods.add((name: outcome.displayName, reason: '下载失败'));
      }
    }
  }

  /// 恢复报告压成一句话：落地几份、留了几份、拒了几份
  String _restoreSummary(CloudImportReport report) {
    final parts = <String>['写入 ${report.written.length} 份'];
    if (report.keptBoth.isNotEmpty) {
      parts.add('同名留两份 ${report.keptBoth.length} 份');
    }
    if (report.unchanged.isNotEmpty) {
      parts.add('内容相同跳过 ${report.unchanged.length} 份');
    }
    if (report.rejected.isNotEmpty) {
      parts.add('没进来 ${report.rejected.length} 份');
    }
    return parts.join('，');
  }

  /// 本机自备份：列出 → 选一份 → 覆盖回本机
  ///
  /// 「还原」本身也会先留一份新备份（域层负责），所以这一步同样能退回去
  Future<void> _openBackups() async {
    final version = _selectedVersion;
    if (version == null) return;

    final chosen = await showCloudBackupPrompt(
      backups: CloudSaveService.backups(),
      versionTag: version.tag,
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = '正在用自备份还原…');
    try {
      final result = await CloudSaveService.restoreBackup(
        version: version,
        backupPath: chosen.path,
      );
      if (!mounted) return;
      addNotice(
        icon: Icons.settings_backup_restore,
        title: '已用本机自备份还原',
        content:
            '${_restoreSummary(result.report)}；覆盖前那份留在 ${result.backupPath.split(RegExp(r'[\\/]')).last}',
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '还原失败',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _deleteSnapshot(CloudSaveSnapshot snapshot) {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '删除云端第 ${snapshot.revision ?? '?'} 版？',
      content: '只删云端这一份历史快照，本机存档不动；删了不可恢复',
      action: () async {
        try {
          final token = await _accounts.ensureAccessToken();
          if (token == null) return;
          await MdtbbsCloudSaveApi.deleteSnapshot(
            accessToken: token,
            slotId: _slot!.id,
            snapshotId: snapshot.id,
          );
          if (!mounted) return;
          addNotice(icon: Icons.delete_outline, title: '已删除云端快照');
          await _reload();
        } catch (error) {
          if (!mounted) return;
          addNotice(
            icon: Icons.error_outline,
            title: '删除失败',
            content: removeNewlines('$error'),
          );
        }
      },
    );
  }

  /// 固定 / 取消固定一份快照：固定过的不会被「腾空间」删掉
  Future<void> _togglePin(CloudSaveSnapshot snapshot) async {
    final slot = _slot;
    if (slot == null) return;
    final token = await _accounts.ensureAccessToken();
    if (token == null) {
      addNotice(
        icon: Icons.info_outline,
        title: '先登录 BBS',
        content: '固定快照需要登录',
      );
      return;
    }
    try {
      await CloudSaveService.setSnapshotPinned(
        accessToken: token,
        slotId: slot.id,
        snapshotId: snapshot.id,
        pinned: !snapshot.pinned,
      );
      await _reload();
    } on Object catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '固定状态没改成功',
        content: removeNewlines('$error'),
      );
    }
  }

  void _deleteSlot() {
    final slot = _slot;
    if (slot == null) return;

    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '删除整个云端存档？',
      content:
          '会删掉云端「${slot.name}」这个槽位与它的全部历史快照；'
          '**本机存档不受影响**',
      action: () async {
        try {
          final token = await _accounts.ensureAccessToken();
          if (token == null) return;
          await CloudSaveService.deleteSlot(
            accessToken: token,
            slotId: slot.id,
          );
          if (!mounted) return;
          addNotice(icon: Icons.delete_forever, title: '已删除云端存档');
          await _reload();
        } catch (error) {
          if (!mounted) return;
          addNotice(
            icon: Icons.error_outline,
            title: '删除失败',
            content: removeNewlines('$error'),
          );
        }
      },
    );
  }

  // ── 界面 ──

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        _buildEnablePanel(),
        if (!_accounts.isLoggedIn) _buildLoginHint(),
        if (_error != null) _buildErrorHint(),
        _buildVersionPanel(),
        _buildSnapshotPanel(),
        _buildPullPanel(),
        _buildHintsPanel(),
        if (kDebugMode) _buildDebugPanel(),
      ],
    );
  }

  /// 这一页的开头：**按版本开关云存档**
  ///
  /// 与「概览 → 账户」里那个开关是同一个（按数据目录记）；共用一份数据目录的版本
  /// 共用同一个开关，所以要把这件事写出来
  Widget _buildEnablePanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final version = _selectedVersion;
    if (version == null) return const SizedBox.shrink();

    final enabled = CloudSaveService.isEnabled(version);
    final globalOn = CloudSaveService.globallyEnabled;
    final shared =
        CloudSaveService.versionsSharingDataPath(
          version,
          config.versionOptions.versionFolds.expand((fold) => fold.versions),
        ) -
        1;

    return ContentPanelModule(
      title: '云存档',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          // 总开关是前置条件：关着时这个版本的开关直接禁用
          SwitchSettingBar(
            title: '这个版本启用云存档',
            value: enabled,
            onChanged: globalOn
                ? (value) {
                    final ok = CloudSaveService.setEnabled(version, value);
                    if (!ok) {
                      addNotice(
                        icon: Icons.info_outline,
                        title: '先打开总开关',
                        content: '账户 → 云存档 里的总开关关着，局部开关打不开',
                      );
                      return;
                    }
                    setState(() {});
                    addLog(
                      .info,
                      '[${version.tag}] 云存档${value ? '开启' : '关闭'}，数据目录：${version.dataPath}',
                      tag: 'Cloud',
                    );
                  }
                : null,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  globalOn
                      ? '总开关已开：各版本自己决定要不要参与（默认关）'
                      : '总开关关着：先去账户 → 云存档打开，才能逐个版本开',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemSecondary,
                  ),
                ),
              ),
              IconTextButton(
                icon: Icons.tune,
                content: '总开关',
                onTap: () {
                  addNotice(
                    icon: Icons.tune,
                    title: '云存档总开关在账户里',
                    content: '点顶栏头像旁边的账户按钮 → 云存档',
                  );
                },
              ),
            ],
          ),
          if (shared > 0)
            Text(
              '这个版本与其他 $shared 个版本共用数据目录，云存档已禁用（会互相覆盖）；'
              '要同步先给版本开隔离数据目录',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else
            Text(
              enabled ? '启用中：启动游戏前拉云端、退出游戏后自动上传' : '当前版本不参与云存档',
              style: theme.textTheme.labelMedium,
            ),
        ],
      ),
    );
  }

  /// 调试模块（仅 debug）：不用真开游戏就能试云存档的传 / 拉 / 冲突
  ///
  /// 「伪造一份存档」往这个版本的数据目录里写一份游戏认得的假存档（同名，内容每次不同）
  /// ⇒ 再点上传 / 跑一次启动前检查，就能把三种状态都走一遍
  Widget _buildDebugPanel() {
    final theme = Theme.of(context);
    final version = _selectedVersion;
    if (version == null) return const SizedBox.shrink();

    return ContentPanelModule(
      title: '调试（仅 debug）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            '往数据目录写一份假存档，用来试「上传 / 启动前拉取 / 冲突」；'
            '别在游戏跑着的时候点。',
            style: theme.textTheme.labelMedium,
          ),
          Row(
            spacing: 8,
            children: [
              IconTextButton(
                icon: Icons.science_outlined,
                content: '伪造一份存档',
                onTap: _busy == null
                    ? () {
                        _writeDebugSave(version.dataPath);
                        addNotice(
                          icon: Icons.check,
                          title: '已写入假存档',
                          content: 'saves/copper-debug.msav',
                        );
                        _reload();
                      }
                    : null,
              ),
              IconTextButton(
                icon: Icons.cloud_download_outlined,
                content: '跑一次启动前检查',
                onTap: _busy == null
                    ? () async {
                        await CloudAutoSync.beforeLaunch(version);
                        await _reload();
                      }
                    : null,
              ),
              IconTextButton(
                icon: Icons.cloud_upload_outlined,
                content: '跑一次退出后上传',
                onTap: _busy == null
                    ? () async {
                        await CloudAutoSync.afterGameExit(version);
                        await _reload();
                      }
                    : null,
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              IconTextButton(
                icon: Icons.link_off,
                content: '清掉本机同步记录（造冲突）',
                onTap: _busy == null
                    ? () {
                        final file = File(CloudSaveService.bindingPath);
                        if (file.existsSync()) file.deleteSync();
                        addNotice(
                          icon: Icons.check,
                          title: '已清掉本机同步记录',
                          content: '再改一次本机存档，就会出现「两边都改过」的冲突',
                        );
                        _reload();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 拉取失败要说出来（登录失效 / 网络不通都会走到这）
  Widget _buildErrorHint() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '读取失败',
      child: Text(
        _error!,
        style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
      ),
    );
  }

  /// 没登录时页面要能自己说明白：上传 / 恢复都要账号（登录在「账户」页）
  Widget _buildLoginHint() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '需要 BBS 账号',
      child: Text(
        '云存档按账号存；登录在「概览 → 账户」里完成，登录后回到这一页即可上传与恢复。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.itemSecondary,
        ),
      ),
    );
  }

  Widget _buildVersionPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final version = _selectedVersion;
    final slot = _slot;

    if (version == null) {
      return ContentPanelModule(
        title: '当前版本',
        child: Text(
          '先在主页选一个游戏版本——云存档是按版本的数据目录来的',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.itemHint),
        ),
      );
    }

    final head = slot?.currentSnapshot;

    return ContentPanelModule(
      title: '当前版本',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Text(version.tag, style: theme.textTheme.bodyLarge),
              // 默认数据目录那份是「唯一可共享存档」，不绑定版本，只做提示
              if (!version.isolation)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('默认存档', style: theme.textTheme.labelSmall),
                ),
            ],
          ),
          if (!version.isolation)
            Text(
              '这份存档在游戏默认数据目录：不绑定任何版本，所有「未隔离」的版本共用它。'
              '要一份独立的云存档，给这个版本打开隔离数据目录。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
          Text(
            version.dataPath,
            style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
          ),
          if (slot == null)
            Text(
              '这个版本还没传到云端',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            )
          else
            Text(
              '云端槽位「${slot.name}」\n'
              '当前版本：${head?.revision == null ? '—' : '第 ${head!.revision} 版'}'
              '${head?.createdAt == null ? '' : '，${head!.createdAt!.toLocal().format('yyyy-MM-dd HH:mm')}'}'
              '${head?.size == null ? '' : '，${formatBytes(head!.size!)}'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
          ?_buildBudgetLine(context),
          Row(
            spacing: 8,
            children: [
              IconTextButton(
                icon: Icons.cloud_upload_outlined,
                content: '上传当前版本',
                onTap: (_busy == null && _accounts.isLoggedIn && !_loading)
                    ? () => _upload()
                    : null,
              ),
              if (slot != null)
                IconTextButton(
                  icon: Icons.delete_forever,
                  content: '删除云端存档',
                  onTap: _busy == null ? _deleteSlot : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「这次约 X MB · 云端还剩 Y MB」—— 传之前就把话说清（完全没有预算时返回 null）
  ///
  /// 估的是**清单合计（未压缩）**：`.msav` / `.msch` 在包里原样存（本来就 zlib 过），
  /// 只有模组 jar 会压 ⇒ 真实包会小一点，所以说「约」
  Widget? _buildBudgetLine(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final estimate = _estimate;
    final quota = _quota;
    final used = quota?.usedBytes;
    final limit = quota?.limitBytes;
    final remaining = (used == null || limit == null) ? null : limit - used;

    final parts = <String>[
      if (estimate != null)
        '这次约 ${formatBytes(estimate.bytes)}'
            '（${estimate.fileCount} 份文件'
            '${estimate.modCount == 0 ? '' : ' · ${estimate.modCount} 个模组'}）',
      if (remaining != null)
        '云端还剩 ${formatBytes(remaining)}'
            '${limit == null ? '' : ' / 共 ${formatBytes(limit)}'}',
    ];
    if (parts.isEmpty) return null;

    final tooBig =
        estimate != null && remaining != null && estimate.bytes > remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Text(
          parts.join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        if (tooBig)
          Text(
            '按未压缩算可能不够：上传前会自动清最旧的未固定快照腾地方，'
            '要是固定太多腾不出来，去下面「云端历史」取消固定或删几个。',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
          ),
      ],
    );
  }

  /// 账号下所有云端槽位（点到「查看云端存档」才有）
  List<CloudSaveSlot>? _cloudSlots;
  bool _loadingCloudSlots = false;

  /// 拉取账号下全部槽位，摊在面板里让用户挑一个拉回来
  Future<void> _loadCloudSlots() async {
    if (_loadingCloudSlots) return;
    setState(() {
      _loadingCloudSlots = true;
      _error = null;
    });
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) throw const MdtbbsException(message: '登录已失效，请重新登录');
      final slots = await CloudSaveService.allSlots(accessToken: token);
      if (!mounted) return;
      setState(() => _cloudSlots = slots);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取云端存档失败：${removeNewlines('$error')}');
    } finally {
      if (mounted) setState(() => _loadingCloudSlots = false);
    }
  }

  /// 把某个云端槽位拉回本版本的数据目录
  Future<void> _pullSlot(CloudSaveSlot slot) async {
    final token = await _accounts.ensureAccessToken();
    if (token == null) {
      addNotice(
        icon: Icons.info_outline,
        title: '先登录 BBS',
        content: '从云拉取需要登录',
      );
      return;
    }
    // 选中版本没开隔离 = 拉的就是「默认存档」：直接写回它的数据目录，不装版本也不补全
    final version = _selectedVersion;
    final task = CloudPullTask(
      accessToken: token,
      slot: slot,
      targetVersion: version != null && !version.isolation ? version : null,
    );
    addTask(task);
    await task.done;
    if (!mounted) return;
    if (task.status == TaskStatus.cancel) {
      addNotice(icon: Icons.close, title: '已取消从云拉取');
      return;
    }
    if (task.error != null) {
      addNotice(
        icon: Icons.error_outline,
        title: '从云拉取失败',
        content: removeNewlines('${task.error}'),
      );
      return;
    }
    addNotice(
      icon: Icons.cloud_download_outlined,
      title: '从云拉取完成',
      content: task.result ?? '',
    );
    if (task.missingMods.isNotEmpty) {
      await showMissingModsDialog(context, task.missingMods);
    }
    await _reload();
  }

  /// 云端槽位列表：拉取入口就在这里（快照列表只有本版本绑定的那份）
  Widget _buildPullPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final slots = _cloudSlots;
    return ContentPanelModule(
      title: '从云端拉取',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            '把账号下任意一份云端存档拉回这个版本；拉取会覆盖本地数据目录里同名的文件',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.cloud_download_outlined,
              content: _loadingCloudSlots
                  ? '读取中…'
                  : (slots == null ? '查看云端存档' : '重新读取'),
              onTap: _loadingCloudSlots ? null : () => unawaited(_loadCloudSlots()),
            ),
          ),
          if (slots != null && slots.isEmpty)
            Text(
              '账号下还没有任何云端存档',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            ),
          for (final slot in slots ?? const <CloudSaveSlot>[])
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    slot.name,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.download,
                  content: '拉取',
                  onTap: _busy == null
                      ? () => unawaited(_pullSlot(slot))
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSnapshotPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '云端历史版本',
      child: _snapshots.isEmpty
          ? Text(
              _slot == null ? '还没有云端存档' : '这个槽位还没有快照',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final snapshot in _snapshots)
                  _SnapshotTile(
                    snapshot: snapshot,
                    isHead: snapshot.id == _slot?.currentSnapshotId,
                    onRestore: _busy == null ? () => _restore(snapshot) : null,
                    onDelete: _busy == null
                        ? () => _deleteSnapshot(snapshot)
                        : null,
                    onTogglePin: _busy == null
                        ? () => _togglePin(snapshot)
                        : null,
                  ),
              ],
            ),
    );
  }

  Widget _buildHintsPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isSteam = _selectedVersion?.steam ?? false;

    return ContentPanelModule(
      title: '同步前注意',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (isSteam)
            ?buildWarningBar(
              context,
              'cloud_hint_steam',
              CloudNotes.steamCloudHint,
            ),
          Text(
            CloudNotes.overwriteBackupHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          // 覆盖前那份备份得有个入口能看见 / 还原 —— 不然等于存了拿不出来
          // （备份只留最近 5 份，列一次目录很便宜）
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              icon: Icons.settings_backup_restore,
              content: '本机自备份（${CloudSaveService.backups().length}）',
              onTap: _openBackups,
            ),
          ),
          Text(
            CloudNotes.retentionHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Text(
            CloudNotes.gameRunningHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条云端快照：版本号 / 时间 / 体积 / 哪台设备传的
class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    required this.snapshot,
    required this.isHead,
    this.onRestore,
    this.onDelete,
    this.onTogglePin,
  });

  final CloudSaveSnapshot snapshot;

  /// 是不是云端当前版本
  final bool isHead;

  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final device = snapshot.deviceId;

    return ReboundListTile(
      leading: Icon(
        isHead ? Icons.cloud_done_outlined : Icons.cloud_outlined,
        color: isHead ? colors.itemPrimary : colors.itemHint,
      ),
      title: Text('第 ${snapshot.revision ?? '?'} 版${isHead ? '（云端当前）' : ''}'),
      subtitle: Text(
        [
          if (snapshot.createdAt != null)
            snapshot.createdAt!.toLocal().format('yyyy-MM-dd HH:mm'),
          if (snapshot.size != null) formatBytes(snapshot.size!),
          if (device != null && device.isNotEmpty) device,
        ].join(' · '),
        style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          IconTextButton(
            icon: snapshot.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            content: snapshot.pinned ? '已固定' : '固定',
            onTap: onTogglePin,
          ),
          IconTextButton(
            icon: Icons.settings_backup_restore,
            content: '恢复',
            onTap: onRestore,
          ),
          IconTextButton(
            icon: Icons.delete_outline,
            content: '删除',
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 调试用：往数据目录写一份**游戏那套读法能认**的假存档（zlib + MSAV + meta 区）
///
/// 名字固定（`copper-debug.msav`）、波次每次不同 ⇒ 反复点就能造出「本机改了」，
/// 配合上传就能造出冲突。只在 debug 下由「调试」模块调用
void _writeDebugSave(String dataPath) {
  final metaBytes = BytesBuilder();
  void u16(BytesBuilder builder, int value) =>
      builder.add([(value >> 8) & 0xFF, value & 0xFF]);
  void utf(BytesBuilder builder, String text) {
    final bytes = utf8.encode(text);
    u16(builder, bytes.length);
    builder.add(bytes);
  }

  final meta = {
    'mapname': '调试存档',
    'wave': '${DateTime.now().millisecondsSinceEpoch % 1000}',
    'build': '160',
    'saved': '${DateTime.now().millisecondsSinceEpoch}',
    'playtime': '7993185',
  };
  u16(metaBytes, meta.length);
  meta.forEach((key, value) {
    utf(metaBytes, key);
    utf(metaBytes, value);
  });

  final raw = BytesBuilder();
  void i32(BytesBuilder builder, int value) => builder.add([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
  raw.add(utf8.encode('MSAV'));
  i32(raw, 13);
  i32(raw, metaBytes.length);
  raw.add(metaBytes.takeBytes());

  final file = File(p.join(dataPath, 'saves', 'copper-debug.msav'))
    ..createSync(recursive: true);
  file.writeAsBytesSync(ZLibEncoder().encodeBytes(raw.takeBytes()));
}
