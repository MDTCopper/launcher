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
import 'package:copper_launcher/domain/cloud/cloud_notes.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/cloud/game_version_fill.dart';
import 'package:copper_launcher/domain/cloud/mod_fill_runner.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/tips/warning_bar.dart';
import 'package:copper_launcher/ui/dialog/cloud_backup_prompt.dart';
import 'package:copper_launcher/ui/dialog/cloud_restore_gap_prompt.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
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

class _VersionCloudSavePageState extends State<VersionCloudSavePage> {
  CloudSaveSlot? _slot;
  List<CloudSaveSnapshot> _snapshots = const [];

  bool _loading = false;
  String? _error;

  /// 正在进行的动作（登录 / 上传 / 恢复）的文案；null 表示空闲
  String? _busy;

  /// 上传进度 0–1
  double _busyProgress = 0;

  /// 这次操作哪个版本：路由参数（版本设置里带过来的那份）优先
  Mindustry? get _selectedVersion =>
      (ModalRoute.of(context)?.settings.arguments as Map?)?['version']
          as Mindustry? ??
      config.versionOptions.selectedVersion;

  /// 上传前的预算：这次大概多大（清单合计、未压缩）与云端还剩多少
  CloudUploadEstimate? _estimate;
  CloudSaveQuota? _quota;

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

    setState(() {
      _loading = true;
      _error = null;
    });

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
        try {
          estimate = await CloudSaveService.estimateUpload(version);
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
      setState(() {
        _loading = false;
        _slot = slot;
        _snapshots = snapshots;
        _estimate = estimate;
        _quota = quota;
      });
    } on MdtbbsException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } catch (error) {
      if (!mounted) return;
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
      _busyProgress = 0;
    });

    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        throw const MdtbbsException(message: '登录已失效，请重新登录');
      }

      final result = await CloudSaveService.upload(
        accessToken: token,
        version: version,
        conflictPolicy: confirmCurrentSnapshotId == null
            ? CloudSaveConflictPolicy.normal
            : CloudSaveConflictPolicy.forceReplaceHead,
        confirmCurrentSnapshotId: confirmCurrentSnapshotId,
        onStatus: (status) {
          if (mounted) setState(() => _busy = status);
        },
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _busyProgress = sent / total);
        },
      );

      if (!mounted) return;
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
          _busyProgress = 0;
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
    setState(() => _busy = '正在下载并解包…');
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        throw const MdtbbsException(message: '登录已失效，请重新登录');
      }

      final report = await CloudSaveService.download(
        accessToken: token,
        version: version,
        slotId: snapshot.slotId ?? _slot!.id,
        snapshotId: snapshot.id,
        onStatus: (state) {
          if (!mounted) return;
          setState(() => _busy = '下载中 ${formatBytes(state.downloaded)}');
        },
      );

      if (!mounted) return;
      addNotice(
        icon: Icons.cloud_download_outlined,
        title: '已从云端恢复',
        content: _restoreSummary(report),
      );
      await _offerRestoreGaps(version: version, report: report);
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

  /// 恢复完本机还缺东西时问一句：缺哪些模组 / 缺哪个游戏版本，能补的一键补
  ///
  /// 两件都缺就**逐件问**（办完一件把那件藏掉再问下一件）—— 一次只让用户做一个决定
  Future<void> _offerRestoreGaps({
    required Mindustry version,
    required CloudImportReport report,
  }) async {
    final gap = computeRestoreGap(
      dataPath: version.dataPath,
      manifest: report.manifest,
      installedGameTags: installedGameIdentifiers(),
    );
    if (!mounted || gap.isEmpty) return;

    var offerMods = gap.downloadableMods.isNotEmpty;
    var offerGame = gap.missingGame != null;
    while (mounted && (offerMods || offerGame)) {
      final choice = await showRestoreGapPrompt(
        gap: gap,
        version: version,
        versionTag: version.tag,
        offerModFill: offerMods,
        offerGameInstall: offerGame,
      );
      switch (choice) {
        case CloudRestoreGapChoice.fillMods:
          offerMods = false;
          await _fillMissingMods(gap: gap, version: version);
        case CloudRestoreGapChoice.installGame:
          offerGame = false;
          await _installMissingGame(gap.missingGame!);
        case CloudRestoreGapChoice.later:
          return;
      }
    }
  }

  /// 把能补的模组排进下载队列，结果报一句
  Future<void> _fillMissingMods({
    required CloudRestoreGap gap,
    required Mindustry version,
  }) async {
    setState(() => _busy = '正在补全模组…');
    try {
      final outcomes = await fillMissingMods(
        gap: gap,
        version: version,
        onStatus: (status) {
          if (mounted) setState(() => _busy = status);
        },
      );
      if (!mounted) return;
      addNotice(
        icon: Icons.extension_outlined,
        title: '模组补全',
        content: describeFillOutcomes(outcomes),
      );
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '模组补全失败',
        content: removeNewlines('$error'),
      );
    }
  }

  /// 把云包里那个游戏版本装回来
  Future<void> _installMissingGame(CloudGameInfo game) async {
    setState(() => _busy = '正在查找游戏版本…');
    try {
      final failure = await installGameVersion(
        game: game,
        onStatus: (status) {
          if (mounted) setState(() => _busy = status);
        },
      );
      if (!mounted) return;
      addNotice(
        icon: failure == null
            ? Icons.download_for_offline_outlined
            : Icons.error_outline,
        title: failure == null ? '游戏版本已排入下载' : '装游戏版本失败',
        content: failure ?? '${game.tag}（装完在版本列表里选它）',
      );
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '装游戏版本失败',
        content: removeNewlines('$error'),
      );
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
    final version = _selectedVersion;
    if (version == null) return const SizedBox.shrink();

    final enabled = CloudSaveService.isEnabled(version);
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
          SwitchSettingBar(
            title: '启用云存档',
            value: enabled,
            onChanged: (value) {
              CloudSaveService.setEnabled(version, value);
              setState(() {});
              addLog(
                .info,
                '[${version.tag}] 云存档${value ? '开启' : '关闭'}，数据目录：${version.dataPath}',
                tag: 'Cloud',
              );
            },
          ),
          Text(
            enabled ? '开启后：启动游戏前拉云端、退出游戏后自动上传' : '没开：这个版本不参与云存档',
            style: theme.textTheme.labelMedium,
          ),
          if (shared > 0)
            Text(
              '这个版本与其他 $shared 个版本共用数据目录，开关是这份目录的',
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
          Text(version.tag, style: theme.textTheme.bodyLarge),
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
          if (_buildBudgetLine(context) case final budget?) budget,
          if (_busy != null && _busyProgress > 0) ...[
            PercentBar(
              total: 1,
              dataList: [PercentBarData(value: _busyProgress)],
            ),
          ],
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
  });

  final CloudSaveSnapshot snapshot;

  /// 是不是云端当前版本
  final bool isHead;

  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

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
