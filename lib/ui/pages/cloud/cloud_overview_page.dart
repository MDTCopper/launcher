import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/domain/tasks/cloud_pull_task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/pages/cloud/version_cloud_save_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:flutter/material.dart';

/// 账户抽屉里的「云存档」：只管**总开关**与容量
///
/// 按版本的启用 / 快照 / 调试都在「版本云存档管理」里，不在这儿重复
class CloudOverviewPage extends StatefulWidget {
  const CloudOverviewPage({super.key});

  @override
  State<CloudOverviewPage> createState() => _CloudOverviewPageState();
}

class _CloudOverviewPageState extends State<CloudOverviewPage> {
  CloudSaveQuota? _quota;
  bool _loading = false;

  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    if (!_accounts.isLoggedIn) {
      setState(() => _quota = null);
      return;
    }
    setState(() => _loading = true);
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) return;
      final quota = await CloudSaveService.quota(accessToken: token);
      if (mounted) setState(() => _quota = quota);
    } on Object {
      // 容量读不到不影响开关，静默
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CopperSingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.block),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.group,
          children: [
            _buildSwitchPanel(),
            _buildQuotaPanel(),
            _buildPullPanel(),
          ],
        ),
      ),
    );
  }

  /// 从云端拉取：账号下任意一份存档拉回当前版本
  ///
  /// 放在这里而不是只放在版本页：用户进「云存档」第一眼就该看到这个入口
  Widget _buildPullPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final slots = _cloudSlots;
    return ContentPanelModule(
      title: '从云端拉取',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          Text(
            '把账号下任意一份云端存档拉回当前选中的版本；覆盖前会自动备份',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.cloud_download_outlined,
              content: _loadingSlots
                  ? '读取中…'
                  : (slots == null ? '查看云端存档' : '重新读取'),
              onTap: (_loadingSlots || !_accounts.isLoggedIn)
                  ? null
                  : () => unawaited(_loadSlotsForPull()),
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
              spacing: AppSpacing.related,
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
                  onTap: () => unawaited(_pullSlot(slot)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<CloudSaveSlot>? _cloudSlots;
  bool _loadingSlots = false;

  Future<void> _loadSlotsForPull() async {
    setState(() => _loadingSlots = true);
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        addNotice(icon: Icons.info_outline, title: '先登录或检查网络');
        return;
      }
      final slots = await CloudSaveService.allSlots(accessToken: token);
      if (!mounted) return;
      setState(() => _cloudSlots = slots);
    } on Object catch (error) {
      addNotice(
        icon: Icons.close,
        title: '读取云端存档失败',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _pullSlot(CloudSaveSlot slot) async {
    final token = await _accounts.ensureAccessToken();
    if (token == null) return;
    final version = config.versionOptions.selectedVersion;
    final task = CloudPullTask(
      accessToken: token,
      slot: slot,
      targetVersion: (version != null && !version.isolation) ? version : null,
    );
    addTask(task);
    await task.done;
    if (!mounted) return;
    addNotice(
      icon: Icons.cloud_download_outlined,
      title: task.error == null ? '从云拉取完成' : '从云拉取失败',
      content: task.error == null
          ? (task.result ?? '')
          : removeNewlines('${task.error}'),
    );
  }
  Widget _buildSwitchPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final enabled = CloudSaveService.globallyEnabled;
    return ContentPanelModule(
      title: '云存档',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          SwitchSettingBar(
            title: '启用云存档',
            value: enabled,
            onChanged: (value) {
              CloudSaveService.setGlobalEnabled(value);
              setState(() {});
            },
          ),
          Text(
            enabled
                ? '所有版本统一参与：启动游戏前拉云端、退出后自动上传'
                : '关着：所有版本都不参与云存档',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.tune,
              content: '版本云存档管理',
              onTap: () => Navigator.pushNamed(
                context,
                versionCloudSavePageRouteKey,
              ),
            ),
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
      title: '云端容量',
      child: quota == null
          ? Text(
              _loading ? '读取中…' : (_accounts.isLoggedIn ? '读不到容量' : '登录后显示'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.related,
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
                  '单个云包上限 ${formatBytes(quota.maxFileSizeBytes ?? 0)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
              ],
            ),
    );
  }
}
