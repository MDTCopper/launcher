import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 任务卡的状态
enum TemplateTaskState { running, paused, failed, done }

/// 任务卡：图标 + 标题 + 状态 + 进度 + 阶段说明 + 时间，右上可取消
///
/// 对应现有右侧任务抽屉里的那条卡（`CopperCard` + `task.buildDisplayWidget`）；
/// 设计层把可变的部分抽成参数，让不同任务类型都能套
class TemplateTaskCard extends StatelessWidget {
  const TemplateTaskCard({
    super.key,
    required this.skin,
    required this.icon,
    required this.title,
    this.state = TemplateTaskState.running,
    this.progress,
    this.progressText,
    this.sizeText,
    this.phaseText,
    this.detailText,
    this.timeText,
    this.onCancel,
  });

  final TemplateSkin skin;
  final IconData icon;
  final String title;
  final TemplateTaskState state;

  /// 0~1；null = 总量未知（进度条走不确定态）
  final double? progress;

  /// 左侧进度文字，如 `3.2 MB / 12.4 MB`
  final String? progressText;

  /// 右侧体积 / 速度文字
  final String? sizeText;

  /// 阶段说明，如 `正在下载[New Horizon]`
  final String? phaseText;

  /// 次级明细（分块 / 子任务），小字
  final String? detailText;
  final String? timeText;
  final VoidCallback? onCancel;

  (String, TemplateBadgeTone) get _statusBadge => switch (state) {
    TemplateTaskState.running => ('进行中', TemplateBadgeTone.accent),
    TemplateTaskState.paused => ('已暂停', TemplateBadgeTone.warning),
    TemplateTaskState.failed => ('失败', TemplateBadgeTone.danger),
    TemplateTaskState.done => ('已完成', TemplateBadgeTone.success),
  };

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusTone) = _statusBadge;
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: skin.sunken,
                  borderRadius: BorderRadius.circular(TemplateRadius.control),
                ),
                child: Icon(icon, size: 16, color: skin.textSecondary),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TemplateType.item.copyWith(
                    color: skin.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TemplateBadge(skin: skin, label: statusLabel, tone: statusTone),
              if (onCancel != null)
                TemplateIconButton(
                  skin: skin,
                  icon: Icons.close,
                  size: 24,
                  iconSize: 14,
                  tooltip: '取消任务',
                  onTap: onCancel,
                ),
            ],
          ),
          TemplateProgressBar(
            skin: skin,
            value: progress ?? 0,
            indeterminate: progress == null,
            height: 8,
          ),
          if (progressText != null || sizeText != null)
            Row(
              spacing: TemplateSpace.sm,
              children: [
                Expanded(
                  child: Text(
                    progressText ?? '',
                    style: TemplateType.caption.copyWith(
                      color: skin.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sizeText != null)
                  Text(
                    sizeText!,
                    style: TemplateType.caption.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
              ],
            ),
          if (phaseText != null)
            Text(
              phaseText!,
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (detailText != null)
            Text(
              detailText!,
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (timeText != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                timeText!,
                style: TemplateType.micro.copyWith(color: skin.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

/// 日志级别
enum TemplateLogTone { info, success, warning, error }

/// 日志行：级别图标 + 一行描述 + 时间
///
/// 对应现有右侧日志抽屉里那一条（图标按级别取，描述一行省略、超长看 hint，右侧时间）
class TemplateLogCard extends StatelessWidget {
  const TemplateLogCard({
    super.key,
    required this.skin,
    required this.message,
    this.timeText,
    this.tone = TemplateLogTone.info,
  });

  final TemplateSkin skin;
  final String message;
  final String? timeText;
  final TemplateLogTone tone;

  IconData get _icon => switch (tone) {
    TemplateLogTone.info => Icons.info_outline,
    TemplateLogTone.success => Icons.check_circle_outline,
    TemplateLogTone.warning => Icons.warning_amber_outlined,
    TemplateLogTone.error => Icons.error_outline,
  };

  Color get _color => switch (tone) {
    TemplateLogTone.info => skin.textTertiary,
    TemplateLogTone.success => skin.success,
    TemplateLogTone.warning => skin.warning,
    TemplateLogTone.error => skin.dangerText,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.sm,
      ),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        border: Border.all(color: skin.border),
      ),
      child: Row(
        spacing: TemplateSpace.sm,
        children: [
          Icon(_icon, size: 15, color: _color),
          Expanded(
            child: Text(
              message,
              style: TemplateType.caption.copyWith(color: skin.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeText != null)
            Text(
              timeText!,
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
            ),
        ],
      ),
    );
  }
}
