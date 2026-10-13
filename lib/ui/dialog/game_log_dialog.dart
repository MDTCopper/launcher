import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 弹一个只读的日志文件：顶上一行路径，正文用等宽字体铺满可滚动区
///
/// 内容由调用方先读好传进来 —— 文件可能不小，别在 build 里读盘
Future<void> showLogFileDialog(
  BuildContext context, {
  required String path,
  required String text,
}) => showAnimatedDialog<void>(
  context: context,
  pageBuilder: (_, _, _) => _LogFileDialog(path: path, text: text),
);

class _LogFileDialog extends StatelessWidget {
  const _LogFileDialog({required this.path, required this.text});

  final String path;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final size = MediaQuery.of(context).size;

    return SizedBox(
      height: size.height * 0.75,
      width: size.width * 0.85,
      child: Material(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      path,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.itemSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconTextButton(
                    icon: Icons.close,
                    content: '关闭',
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Expanded(
              child: CopperSingleChildScrollView(
                fadeMask: false,
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
