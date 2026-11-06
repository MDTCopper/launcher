import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 任务卡：仿当前 launcher 里的 Mindustry 任务卡（`LaunchMindustryTask.buildDisplayWidget`）
///
/// 形制就是那一套：**图标 + 强调色大标题 + 右侧时间**，下面一行状态说明，
/// 再到一条进度条，最后是等宽的操作按钮（结束进程 / 进程日志…）。
/// 差别只在于：这里把内容抽成参数，其它任务类型也能套同一条形制
class TemplateTaskCard extends StatelessWidget {
  const TemplateTaskCard({
    super.key,
    required this.skin,
    required this.icon,
    required this.title,
    this.subtitle,
    this.progress,
    this.timeText,
    this.actions = const <Widget>[],
  });

  final TemplateSkin skin;
  final IconData icon;
  final String title;

  /// 状态说明那一行，如 `Mindustry 146  运行中...`
  final String? subtitle;

  /// 0~1；null = 不确定进度（跟原生 `LinearProgressIndicator()` 一样来回走）
  final double? progress;
  final String? timeText;

  /// 底部等宽操作按钮；直接放 `TemplateButton(expanded: true)` 即可
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
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
              Icon(icon, size: 24, color: skin.accentText),
              Expanded(
                child: Text(
                  title,
                  style: TemplateType.page.copyWith(
                    color: skin.accentText,
                    fontWeight: FontWeight.w700,
                  ),
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
          if (subtitle != null)
            Text(
              subtitle!,
              style: TemplateType.item.copyWith(color: skin.textPrimary),
            ),
          TemplateProgressBar(
            skin: skin,
            value: progress ?? 0,
            indeterminate: progress == null,
            height: 4,
          ),
          if (actions.isNotEmpty)
            Row(
              spacing: TemplateSpace.sm,
              children: [for (final action in actions) Expanded(child: action)],
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
