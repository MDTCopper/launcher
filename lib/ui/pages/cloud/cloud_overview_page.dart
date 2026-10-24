import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/pages/cloud/version_cloud_save_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
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
          children: [_buildSwitchPanel(), _buildQuotaPanel()],
        ),
      ),
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
