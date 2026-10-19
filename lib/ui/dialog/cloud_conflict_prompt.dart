import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
import 'package:flutter/material.dart';

/// 云存档冲突时玩家的选择
enum CloudConflictChoice {
  /// 用云端那份覆盖本机（覆盖前会自备份）
  useCloud,

  /// 用本机这份覆盖云端当前版本
  useLocal,

  /// 两份都留：云端那份解出来，同名不同内容的另存一份
  keepBoth,

  /// 没选 / 关掉弹窗 —— 调用方据此**停止启动**
  cancel,
}

/// 启动前发现「本机与云端都改过」时弹这个：**让玩家自己选**
///
/// 没选（点取消或关掉弹窗）返回 [CloudConflictChoice.cancel]：调用方据此停止启动，
/// **绝不替玩家挑一边**。启动任务没有自己的 context，所以这里不要求传
Future<CloudConflictChoice> showCloudConflictPrompt({
  required CloudSyncOutcome outcome,
  String? versionTag,
  BuildContext? context,
}) async {
  final choice = await showAnimatedDialog<CloudConflictChoice>(
    context: context,
    pageBuilder: (_, _, _) =>
        _CloudConflictDialog(outcome: outcome, versionTag: versionTag),
  );
  return choice ?? CloudConflictChoice.cancel;
}

/// 同步**超时**时问玩家：要不要直接启动（与 Steam 云那套一致）
///
/// 返回 true = 直接启动；false = 不启动（取消 / 关掉弹窗都算不启动）
Future<bool> showCloudSyncTimeoutPrompt({
  String? versionTag,
  BuildContext? context,
}) async {
  final choice = await showAnimatedDialog<bool>(
    context: context,
    pageBuilder: (_, _, _) => _CloudTimeoutDialog(versionTag: versionTag),
  );
  return choice ?? false;
}

class _CloudTimeoutDialog extends StatelessWidget {
  const _CloudTimeoutDialog({this.versionTag});

  final String? versionTag;

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
          constraints: BoxConstraints(maxWidth: screen.width * 0.5),
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
              Text('云存档同步超时', style: theme.textTheme.titleLarge),
              Text(
                '${versionTag == null ? '这个版本' : '「$versionTag」'}的云存档还没同步完。'
                '直接启动就用本机现在的存档，退出游戏后还会再传一次。',
                style: theme.textTheme.bodySmall,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  IconTextButton(
                    icon: Icons.play_arrow,
                    content: '直接启动',
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudConflictDialog extends StatelessWidget {
  const _CloudConflictDialog({required this.outcome, this.versionTag});

  final CloudSyncOutcome outcome;
  final String? versionTag;

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
              Text('云存档冲突', style: theme.textTheme.titleLarge),
              Text(
                '${versionTag == null ? '这个版本' : '「$versionTag」'}的存档本机与云端都改过，'
                '需要你选一份，或者两份都留下。不选就**不启动**（不会动任何一边）。',
                style: theme.textTheme.bodySmall,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Expanded(
                    child: _buildSide(
                      context,
                      '本机',
                      outcome.local,
                      local: true,
                    ),
                  ),
                  Expanded(
                    child: _buildSide(
                      context,
                      '云端',
                      outcome.remote,
                      local: false,
                    ),
                  ),
                ],
              ),
              if (!outcome.hasBaseline)
                Text(
                  '没有上次同步的逐文件记录，判断不了具体改了哪些文件',
                  style: theme.textTheme.labelMedium,
                )
              else if (outcome.changedFiles.isNotEmpty)
                Text(
                  '本机改了 ${outcome.changedFiles.length} 个文件'
                  '（${outcome.changedFiles.take(3).join('、')}'
                  '${outcome.changedFiles.length > 3 ? ' 等' : ''}）',
                  style: theme.textTheme.labelMedium,
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  IconTextButton(
                    icon: Icons.cloud_download_outlined,
                    content: '用云端覆盖本机',
                    onTap: () =>
                        Navigator.of(context).pop(CloudConflictChoice.useCloud),
                  ),
                  IconTextButton(
                    icon: Icons.cloud_upload_outlined,
                    content: '用本机覆盖云端',
                    onTap: () =>
                        Navigator.of(context).pop(CloudConflictChoice.useLocal),
                  ),
                  IconTextButton(
                    icon: Icons.copy_all_outlined,
                    content: '两份都留',
                    onTap: () =>
                        Navigator.of(context).pop(CloudConflictChoice.keepBoth),
                  ),
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消（不启动）',
                    onTap: () =>
                        Navigator.of(context).pop(CloudConflictChoice.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一侧的时间：本机看存档时间，云端看上传（快照创建）时间
  ///
  /// 机器信息（设备 / 系统）不显示：云端快照里没有平台字段，只有本机有 ⇒ 摆出来也没法对照
  Widget _buildSide(
    BuildContext context,
    String title,
    CloudSyncSide? side, {
    required bool local,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    final at = local ? side?.savedAt?.toLocal() : side?.createdAt?.toLocal();
    final lines = <String>[
      if (at != null)
        '${local ? '存档时间' : '上传时间'}：${at.format('yyyy-MM-dd HH:mm')}',
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.lowBackgroundOnCard,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (lines.isEmpty)
            Text('没有可读的时间', style: theme.textTheme.labelMedium)
          else
            for (final line in lines)
              Text(line, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
