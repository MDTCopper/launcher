import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 空 / 错误 / 加载三态的公共排版：图标 + 标题 + 说明 + 可选动作，整体居中
class _StateBody extends StatelessWidget {
  const _StateBody({
    required this.skin,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.message,
    this.action,
  });

  final TemplateSkin skin;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TemplateSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: TemplateSpace.sm,
          children: [
            Icon(icon, size: 32, color: iconColor),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TemplateType.item.copyWith(color: skin.textPrimary),
            ),
            if (message != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                    height: 18 / 12,
                  ),
                ),
              ),
            if (action != null) ...[
              const SizedBox(height: TemplateSpace.xs),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 空态：列表 / 搜索结果 / 没有存档之类的地方统一用它
///
/// 覆盖度审计 P0-6：现项目里空态散着 8+ 种写法，全混着各自页面的字体与间距
class TemplateEmptyState extends StatelessWidget {
  const TemplateEmptyState({
    super.key,
    required this.skin,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final TemplateSkin skin;
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _StateBody(
      skin: skin,
      icon: icon,
      iconColor: skin.textTertiary,
      title: title,
      message: message,
      action: action,
    );
  }
}

/// 错误态：图标与标题用危险色，动作一般是「重试」
class TemplateErrorState extends StatelessWidget {
  const TemplateErrorState({
    super.key,
    required this.skin,
    required this.title,
    this.message,
    this.icon = Icons.error_outline,
    this.action,
  });

  final TemplateSkin skin;
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _StateBody(
      skin: skin,
      icon: icon,
      iconColor: skin.dangerText,
      title: title,
      message: message,
      action: action,
    );
  }
}

/// 加载态：右侧一句话可留空；条粗细与颜色跟皮肤走
class TemplateLoadingState extends StatelessWidget {
  const TemplateLoadingState({super.key, required this.skin, this.message});

  final TemplateSkin skin;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TemplateSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: TemplateSpace.md,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: skin.accent,
              ),
            ),
            if (message != null)
              Text(
                message!,
                style: TemplateType.caption.copyWith(color: skin.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}
