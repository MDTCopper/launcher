import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/core/cu_progress.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 日志等级（图标与语义色）
enum CuLogLevel { info, success, warning, error }

/// 日志条目：任务抽屉 / 日志页共用
///
/// 三种形态：
/// - 单行：图标 + 文本 + 时间（超长时仍单行省略，用 `onTap` 或详情展开）
/// - 带详情：标题行 + 可展开的等宽详情块（堆栈 / 命令输出），展开后可复制
/// - 带进度：标题行 + 进度条 + 百分比（下载 / 解压这类过程日志）
class CuLogTile extends StatefulWidget {
  const CuLogTile({
    super.key,
    required this.text,
    this.level = CuLogLevel.info,
    this.time,
    this.detail,
    this.progress,
    this.mono = false,
    this.expanded = false,
    this.onCopy,
  });

  final String text;
  final CuLogLevel level;

  /// 时间戳文字（调用方格式化好）
  final String? time;

  /// 详情：给了就出现「展开 / 收起」；等宽显示
  final String? detail;

  /// 0~1；给了就显示进度条
  final double? progress;

  /// 正文用等宽字体（命令 / 输出）
  final bool mono;

  final bool expanded;

  /// 复制详情（给了才显示复制按钮）
  final VoidCallback? onCopy;

  @override
  State<CuLogTile> createState() => _CuLogTileState();
}

class _CuLogTileState extends State<CuLogTile> {
  late bool _expanded = widget.expanded;

  Color _levelColor(AppColors colors) => switch (widget.level) {
    CuLogLevel.info => colors.itemSecondary,
    CuLogLevel.success => colors.success,
    CuLogLevel.warning => colors.warning,
    CuLogLevel.error => colors.error,
  };

  IconData get _levelIcon => switch (widget.level) {
    CuLogLevel.info => Icons.info_outline,
    CuLogLevel.success => Icons.check_circle_outline,
    CuLogLevel.warning => Icons.warning_amber_outlined,
    CuLogLevel.error => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final tone = _levelColor(colors);

    final headline = Row(
      spacing: AppSpacing.related,
      children: [
        Icon(_levelIcon, size: AppIconSize.inline, color: tone),
        Expanded(
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (widget.mono ? textTheme.bodySmall : textTheme.bodyMedium)
                ?.copyWith(
                  color: colors.itemPrimary,
                  fontFamily: widget.mono ? 'Consolas' : null,
                  fontFamilyFallback: widget.mono
                      ? const ['Courier New', 'monospace']
                      : null,
                ),
          ),
        ),
        if (widget.time != null)
          Text(
            widget.time!,
            style: textTheme.labelSmall?.copyWith(color: colors.itemHint),
          ),
        if (widget.detail != null)
          CuPressable(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: AppIconSize.inline,
              color: colors.itemHint,
            ),
          ),
        if (widget.onCopy != null)
          CuPressable(
            onTap: widget.onCopy,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Icon(
              Icons.copy,
              size: AppIconSize.inline,
              color: colors.itemHint,
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.related,
        vertical: AppSpacing.tight + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.tight,
        children: [
          headline,
          if (widget.progress != null)
            CuProgress(
              value: widget.progress,
              label: '${(widget.progress! * 100).round()}%',
            ),
          if (widget.detail != null && _expanded)
            Container(
              decoration: BoxDecoration(
                color: colors.inputBackground,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              padding: const EdgeInsets.all(AppSpacing.related),
              child: SelectableText(
                widget.detail!,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.itemSecondary,
                  fontFamily: 'Consolas',
                  fontFamilyFallback: const ['Courier New', 'monospace'],
                  height: 16 / 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
