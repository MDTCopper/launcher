import 'dart:io';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/domain/launcher_update.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launcher_update_task.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 弹「检查更新」：进来就查一次，按结果给出下载 / 跳转动作
Future<void> showLauncherUpdateCheck(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    pageBuilder: (_, _, _) => const _LauncherUpdateDialog(),
  );
}

/// 检查结果
enum _CheckResult { checking, upToDate, available, failed }

class _LauncherUpdateDialog extends StatefulWidget {
  const _LauncherUpdateDialog();

  @override
  State<_LauncherUpdateDialog> createState() => _LauncherUpdateDialogState();
}

class _LauncherUpdateDialogState extends State<_LauncherUpdateDialog> {
  _CheckResult _result = _CheckResult.checking;
  LauncherRelease? _release;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final releases = await LauncherUpdate.fetchReleases();
    if (!mounted) return;

    setState(() {
      if (releases == null) {
        _result = _CheckResult.failed;
        return;
      }
      // 正式版用户不吃预发布：候选按本地通道筛过（内测 / 公测才看预发布）
      final candidate = LauncherUpdate.newestFor(
        local: LauncherUpdate.currentVersion,
        releases: releases,
      );
      if (candidate != null && LauncherUpdate.isNewer(candidate)) {
        _release = candidate;
        _result = _CheckResult.available;
      } else {
        _result = _CheckResult.upToDate;
      }
    });
  }

  /// 重试：先把面板切回「正在查询」（首次进来时不能 setState，见 initState）
  void _retry() {
    setState(() => _result = _CheckResult.checking);
    _check();
  }

  /// 当前形态要下的产物：Setup 装的取 Setup（覆盖安装）、解压版取 zip；
  /// 其它平台不下载，只跳 release 页
  LauncherAsset? get _asset {
    final release = _release;
    if (release == null || !Platform.isWindows) return null;
    return LauncherUpdate.pickWindowsAsset(
      release.assets,
      preferSetup: LauncherUpdate.isInstalledBuild,
    );
  }

  /// 下载：关掉弹窗，进度与取消交给任务抽屉
  void _download(LauncherAsset asset) {
    final release = _release;
    if (release == null) return;
    Navigator.of(context).pop();
    addTask(LauncherUpdateTask(release: release, asset: asset));
  }

  Future<void> _openReleasePage() async {
    final url = _release?.htmlUrl;
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.inAppWebView);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final screen = MediaQuery.of(context).size;

    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxWidth: screen.width * 0.5,
            maxHeight: screen.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              top: BorderSide(color: colors.border, width: 1.5),
              left: BorderSide(color: colors.border, width: 0.75),
              right: BorderSide(color: colors.border, width: 0.75),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('检查更新', style: theme.textTheme.titleLarge),
              Text(
                '当前版本：$appVersion (Build $appBuildNumber)',
                style: theme.textTheme.bodySmall,
              ),
              ..._buildResult(theme, colors),
            ],
          ),
        ),
      ),
    );
  }

  /// 按检查结果给出正文与动作
  List<Widget> _buildResult(ThemeData theme, AppColors colors) {
    switch (_result) {
      case _CheckResult.checking:
        return [Text('正在查询…', style: theme.textTheme.bodyMedium)];

      case _CheckResult.failed:
        return [
          Text('查询失败，检查网络后重试', style: theme.textTheme.bodyMedium),
          _buildActions([_retryButton(), _closeButton()]),
        ];

      case _CheckResult.upToDate:
        return [
          Text('已经是最新版本', style: theme.textTheme.bodyMedium),
          _buildActions([_closeButton()]),
        ];

      case _CheckResult.available:
        return _buildAvailable(theme, colors);
    }
  }

  List<Widget> _buildAvailable(ThemeData theme, AppColors colors) {
    final release = _release!;
    final asset = _asset;
    final channel = release.version?.channel;

    return [
      Row(
        spacing: 8,
        children: [
          Text(
            release.displayName,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.interactive,
            ),
          ),
          if (channel != null)
            Text('· ${channel.label}', style: theme.textTheme.labelMedium),
        ],
      ),
      if (release.body.trim().isNotEmpty)
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: SingleChildScrollView(
            child: Text(release.body.trim(), style: theme.textTheme.bodySmall),
          ),
        ),
      if (asset != null)
        Text(
          asset.name.endsWith('-setup.exe')
              ? '将下载安装包并覆盖安装：装完启动器会退出，重新打开即可'
              : '当前是解压版：会下载 zip，退出后自动覆盖并重新打开（用户数据不受影响）',
          style: theme.textTheme.labelMedium,
        ),
      _buildActions([
        if (asset != null)
          IconTextButton(
            icon: Icons.download,
            content: asset.name.endsWith('-setup.exe') ? '下载并安装' : '下载更新包',
            onTap: () => _download(asset),
          ),
        IconTextButton(
          icon: Icons.open_in_new,
          content: '前往下载页',
          onTap: _openReleasePage,
        ),
        _closeButton(),
      ]),
    ];
  }

  /// 动作行：放不下就换行（窄窗口下三个按钮会挤出界）
  Widget _buildActions(List<Widget> buttons) =>
      Wrap(spacing: 8, runSpacing: 8, children: buttons);

  Widget _retryButton() =>
      IconTextButton(icon: Icons.refresh, content: '重试', onTap: _retry);

  Widget _closeButton() => IconTextButton(
    icon: Icons.close,
    content: '关闭',
    onTap: () => Navigator.of(context).pop(),
  );
}
