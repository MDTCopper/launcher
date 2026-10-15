import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
import 'package:flutter/material.dart';

/// 列本机「覆盖前自备份」，玩家点哪份就把本机覆盖回哪份
///
/// 返回选中的那份备份；关掉弹窗给 null。**覆盖动作由调用方做**（它要联网不成，
/// 但要起备份、写数据目录，不适合塞在弹窗里）
Future<CloudBackupFile?> showCloudBackupPrompt({
  required List<CloudBackupFile> backups,
  int keepCount = CloudSaveService.backupKeep,
  String? versionTag,
  BuildContext? context,
}) async {
  final chosen = await showAnimatedDialog<CloudBackupFile>(
    context: context,
    pageBuilder: (_, _, _) => _CloudBackupDialog(
      backups: backups,
      keepCount: keepCount,
      versionTag: versionTag,
    ),
  );
  return chosen;
}

class _CloudBackupDialog extends StatelessWidget {
  const _CloudBackupDialog({
    required this.backups,
    required this.keepCount,
    this.versionTag,
  });

  final List<CloudBackupFile> backups;
  final int keepCount;
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
              Text('本机自备份', style: theme.textTheme.titleLarge),
              Text(
                '${versionTag == null ? '这个版本' : '「$versionTag」'}每次被云端存档覆盖之前，'
                '都会先把本机那份留在这里（只保留最近 $keepCount 份）。'
                '选一份就能把本机覆盖回去 —— 覆盖前还会再留一份新的，所以这一步同样能退回去。',
                style: theme.textTheme.bodySmall,
              ),
              if (backups.isEmpty)
                Text('还没有备份。每次用云端存档覆盖本机时会自动留一份。',
                    style: theme.textTheme.labelMedium)
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 6,
                      children: [
                        for (final backup in backups)
                          _buildRow(context, backup),
                      ],
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconTextButton(
                    icon: Icons.close,
                    content: '关闭',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, CloudBackupFile backup) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final at = backup.createdAt?.toLocal();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.lowBackgroundOnCard,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  // 时间解不出来时退回文件名，至少能对上是哪一份
                  at == null ? backup.name : at.format('yyyy-MM-dd HH:mm:ss'),
                  style: theme.textTheme.labelLarge,
                ),
                Text(formatBytes(backup.bytes),
                    style: theme.textTheme.labelMedium),
              ],
            ),
          ),
          IconTextButton(
            icon: Icons.settings_backup_restore,
            content: '还原',
            onTap: () => Navigator.of(context).pop(backup),
          ),
        ],
      ),
    );
  }
}
