import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 任务卡（右侧任务抽屉）
///
/// 2026-11-06 第二版：不是照抄 `LaunchMindustryTask` 那种「大标题 + 通栏按钮」，
/// 换成跟其它卡片同一套语汇——**图标块 + 标题/状态徽标 + 右侧时间**、
/// 进度条带百分比、说明与体积分两栏、操作按钮收在右下角
class TemplateTaskCard extends StatelessWidget {
  const TemplateTaskCard({
    super.key,
    required this.skin,
    required this.icon,
    required this.title,
    this.statusLabel,
    this.statusTone = TemplateBadgeTone.accent,
    this.progress,
    this.phaseText,
    this.progressText,
    this.sizeText,
    this.detailText,
    this.timeText,
    this.actions = const <Widget>[],
  });

  final TemplateSkin skin;
  final IconData icon;
  final String title;

  /// 状态徽标，如 进行中 / 已暂停 / 失败 / 已完成
  final String? statusLabel;
  final TemplateBadgeTone statusTone;

  /// 0~1；null = 不确定进度（总量未知）
  final double? progress;

  /// 阶段说明，如 `正在下载本体分块`
  final String? phaseText;

  /// 左侧进度文字，如 `5.2 MB / 12.4 MB`
  final String? progressText;

  /// 右侧速率 / 体积文字，如 `1.8 MB/s`
  final String? sizeText;

  /// 次级明细，如 `分块 3 / 8 · 已校验 2 块`
  final String? detailText;
  final String? timeText;

  /// 右下角操作按钮（一般给安静按钮）
  final List<Widget> actions;

  Color get _iconColor => switch (statusTone) {
    TemplateBadgeTone.danger => skin.dangerText,
    TemplateBadgeTone.warning => skin.warning,
    TemplateBadgeTone.success => skin.success,
    _ => skin.accentText,
  };

  @override
  Widget build(BuildContext context) {
    final determinate = progress != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 抽屉里只有 300 上下宽：操作按钮不能跟明细挤在一排，
        // 否则就像用户说的「捉襟见肘」（宽屏 / 将来的任务详情页才走一排）
        final compact = constraints.maxWidth < 400;

        // 窄屏时把按钮自动抻满一行；宽屏保持原来的安静按钮
        Widget resolvedAction(Widget action) => switch (action) {
          TemplateButton() when compact => TemplateButton(
            skin: action.skin,
            label: action.label,
            icon: action.icon,
            kind: action.kind,
            danger: action.danger,
            enabled: action.enabled,
            expanded: true,
            onTap: action.onTap,
          ),
          _ => action,
        };

        return TemplateCard(
          skin: skin,
          padding: const EdgeInsets.all(TemplateSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.sm,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TemplateSpace.md,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: skin.sunken,
                      borderRadius: BorderRadius.circular(
                        TemplateRadius.control,
                      ),
                    ),
                    child: Icon(icon, size: 18, color: _iconColor),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          title,
                          style: TemplateType.item.copyWith(
                            color: skin.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (phaseText != null)
                          Text(
                            phaseText!,
                            style: TemplateType.caption.copyWith(
                              color: skin.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // 时间在上、状态在下（用户 2026-11-06：「把任务当前状态放到时间下面」）
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: TemplateSpace.xs,
                    children: [
                      if (timeText != null)
                        Text(
                          timeText!,
                          style: TemplateType.micro.copyWith(
                            color: skin.textTertiary,
                          ),
                        ),
                      if (statusLabel != null)
                        TemplateBadge(
                          skin: skin,
                          label: statusLabel!,
                          tone: statusTone,
                        ),
                    ],
                  ),
                ],
              ),
              Row(
                spacing: TemplateSpace.sm,
                children: [
                  Expanded(
                    child: TemplateProgressBar(
                      skin: skin,
                      value: progress ?? 0,
                      indeterminate: !determinate,
                      height: 8,
                    ),
                  ),
                  if (determinate)
                    Text(
                      '${(progress! * 100).round()}%',
                      style: TemplateType.micro.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                ],
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
              if (compact) ...[
                if (detailText != null)
                  Text(
                    detailText!,
                    style: TemplateType.micro.copyWith(
                      color: skin.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (actions.isNotEmpty)
                  Row(
                    spacing: TemplateSpace.sm,
                    children: [
                      for (final action in actions)
                        Expanded(child: resolvedAction(action)),
                    ],
                  ),
              ] else
                Row(
                  spacing: TemplateSpace.sm,
                  children: [
                    Expanded(
                      child: Text(
                        detailText ?? '',
                        style: TemplateType.micro.copyWith(
                          color: skin.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final action in actions) action,
                  ],
                ),
            ],
          ),
        );
      },
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
