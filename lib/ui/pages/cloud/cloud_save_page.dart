import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_cloud_save_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_notes.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/tips/warning_bar.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:flutter/material.dart';

const cloudSavePageRouteKey = '/cloud_save';

/// 云存档页：MDTBBS 账号 + 当前版本的云端槽位与快照
///
/// 同步单元是**数据目录**不是版本：页面按「当前选中版本」呈现，但云端槽位绑的是
/// 它那份数据目录（见 `CloudSaveService`）。所以这里显示的是「这个版本用的那份
/// 数据目录」的云端状态
///
/// **加载时不创建槽位** —— 建槽要占配额，是用户点「上传」才做的事
class CloudSavePage extends StatefulWidget {
  const CloudSavePage({super.key});

  @override
  State<CloudSavePage> createState() => _CloudSavePageState();
}

class _CloudSavePageState extends State<CloudSavePage> {
  MdtbbsAccount? _account;
  CloudSaveQuota? _quota;
  CloudSaveSlot? _slot;
  List<CloudSaveSnapshot> _snapshots = const [];

  bool _loading = false;
  String? _error;

  /// 正在进行的动作（登录 / 上传 / 恢复）的文案；null 表示空闲
  String? _busy;

  /// 上传进度 0–1
  double _busyProgress = 0;

  Mindustry? get _selectedVersion => config.versionOptions.selectedVersion;

  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    // 首帧之后再拉：登录态与网络都是异步的，别在 build 里起
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  // ── 数据 ──

  /// 拉一遍账号 / 配额 / 当前版本槽位 / 快照历史
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
      await _accounts.restore();
      if (!_accounts.isLoggedIn) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _account = null;
          _quota = null;
          _slot = null;
          _snapshots = const [];
        });
        return;
      }

      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        throw const MdtbbsException(message: '登录已失效，请重新登录');
      }

      final account = await _accounts.loadAccount();
      final quota = await CloudSaveService.quota(accessToken: token);

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

      if (!mounted) return;
      setState(() {
        _loading = false;
        _account = account;
        _quota = quota;
        _slot = slot;
        _snapshots = snapshots;
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

  Future<void> _login() async {
    setState(() => _busy = '等待浏览器授权…');
    try {
      // 会在系统浏览器里打开授权页，这里只等回调
      await _accounts.login();
      if (!mounted) return;
      addNotice(icon: Icons.cloud_done_outlined, title: '已登录 MDTBBS');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '登录没成功',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _logout() {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '退出 MDTBBS 账号？',
      content: '会撤销这个启动器的登录凭证并清掉本地账号信息；云端存档不受影响',
      action: () async {
        await _accounts.logout();
        if (!mounted) return;
        addNotice(icon: Icons.logout, title: '已退出登录');
        await _reload();
      },
    );
  }

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
      addNotice(
        icon: Icons.cloud_upload_outlined,
        title: '已上传到云端',
        content: dropped.isEmpty
            ? '云包 ${formatBytes(result.archiveBytes)}'
            : '云包 ${formatBytes(result.archiveBytes)}；'
                  '有 ${dropped.length} 个文件在打包时被改动过，没进包',
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
        _buildAccountPanel(),
        _buildQuotaPanel(),
        _buildVersionPanel(),
        _buildSnapshotPanel(),
        _buildHintsPanel(),
      ],
    );
  }

  Widget _buildAccountPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final account = _account;

    if (!_accounts.isConfigured) {
      return ContentPanelModule(
        title: '账号',
        child: Text(
          '这个构建还没配置 MDTBBS 的 client_id，云存档不可用',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.itemHint),
        ),
      );
    }

    return ContentPanelModule(
      title: '账号',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (account == null)
            Text(
              '登录 MDTBBS 账号后，可以把存档同步到社区云端。'
              '登录在系统浏览器里完成，启动器不接触你的密码。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            )
          else
            Row(
              spacing: 8,
              children: [
                Icon(Icons.account_circle_outlined, color: colors.itemPrimary),
                Expanded(
                  child: Text(
                    account.username ?? account.subject,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                if (account.phoneVerified == false)
                  Text(
                    '手机号未验证（云端写操作会被拒）',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.error,
                    ),
                  ),
              ],
            ),
          if (_busy != null)
            Row(
              spacing: 8,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Expanded(child: Text(_busy!, style: theme.textTheme.bodySmall)),
              ],
            ),
          Row(
            spacing: 8,
            children: [
              if (account == null)
                IconTextButton(
                  icon: Icons.login,
                  content: '登录 MDTBBS',
                  onTap: _busy == null ? _login : null,
                )
              else ...[
                IconTextButton(
                  icon: Icons.refresh,
                  content: '刷新',
                  onTap: _loading ? null : _reload,
                ),
                IconTextButton(
                  icon: Icons.logout,
                  content: '退出登录',
                  onTap: _logout,
                ),
              ],
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
        ],
      ),
    );
  }

  Widget _buildQuotaPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final quota = _quota;

    return ContentPanelModule(
      title: '云端用量',
      child: quota == null
          ? Text(
              _accounts.isLoggedIn ? '读取中…' : '登录后显示',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                PercentBar(
                  total: (quota.limitBytes ?? 1).toDouble(),
                  dataList: [
                    PercentBarData(value: (quota.usedBytes ?? 0).toDouble()),
                  ],
                ),
                Text(
                  '${formatBytes(quota.usedBytes ?? 0)} / '
                  '${formatBytes(quota.limitBytes ?? 0)}'
                  '　槽位 ${quota.slotsUsed ?? 0}/${quota.slotsLimit ?? 0}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemSecondary,
                  ),
                ),
                Text(
                  '单个云包上限 ${formatBytes(quota.maxFileSizeBytes ?? 0)}；'
                  '模组默认只记清单不带字节（带字节很容易超上限）',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
              ],
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
