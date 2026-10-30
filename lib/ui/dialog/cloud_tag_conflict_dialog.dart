import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 本地实例 tag 与云端 boundTag 不一致时的选择
enum CloudTagChoice {
  /// 把本机实例改名成云端 tag；云槽位名 / 云签名不动
  useCloud,

  /// 把云槽位名改成当前实例 tag；本机不动
  useLocal,

  /// 取消，不绑定也不拉取
  cancel,
}

Future<CloudTagChoice> showCloudTagConflictPrompt({
  required String localTag,
  required String cloudTag,
  BuildContext? context,
}) async {
  final choice = await showAnimatedDialog<CloudTagChoice>(
    context: context,
    pageBuilder: (_, _, _) =>
        _CloudTagConflictDialog(localTag: localTag, cloudTag: cloudTag),
  );
  return choice ?? CloudTagChoice.cancel;
}

class _CloudTagConflictDialog extends StatelessWidget {
  const _CloudTagConflictDialog({
    required this.localTag,
    required this.cloudTag,
  });

  final String localTag;
  final String cloudTag;

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
          constraints: BoxConstraints(maxWidth: screen.width * 0.55),
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
              Text('云端标签与本机不一致', style: theme.textTheme.titleLarge),
              Text(
                '本机实例：$localTag\n云端绑定：$cloudTag\n'
                '云签名由槽位决定，两个选项都只改可读名字，不改云存档身份。',
                style: theme.textTheme.bodySmall,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  IconTextButton(
                    icon: Icons.cloud_outlined,
                    content: '使用云端标签',
                    onTap: () =>
                        Navigator.of(context).pop(CloudTagChoice.useCloud),
                  ),
                  IconTextButton(
                    icon: Icons.computer,
                    content: '使用本地标签',
                    onTap: () =>
                        Navigator.of(context).pop(CloudTagChoice.useLocal),
                  ),
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消',
                    onTap: () =>
                        Navigator.of(context).pop(CloudTagChoice.cancel),
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
