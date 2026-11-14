import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 提示条语气
enum CuNoticeTone { info, success, warning, danger, note }

/// 提示条：搬运设计层 [TemplateNotice]
/// （左侧一道语义色 + 凹槽淡底，可带标题 / 行内动作 / 关闭）
class CuNotice extends StatelessWidget {
  const CuNotice({
    super.key,
    required this.text,
    this.title,
    this.tone = CuNoticeTone.info,
    this.icon,
    this.action,
    this.onClose,
  });

  final String text;
  final String? title;
  final CuNoticeTone tone;
  final IconData? icon;
  final Widget? action;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return TemplateNotice(
      skin: cuSkinOf(context),
      text: text,
      title: title,
      tone: switch (tone) {
        CuNoticeTone.info => TemplateNoticeTone.info,
        CuNoticeTone.success => TemplateNoticeTone.success,
        CuNoticeTone.warning => TemplateNoticeTone.warning,
        CuNoticeTone.danger => TemplateNoticeTone.danger,
        CuNoticeTone.note => TemplateNoticeTone.note,
      },
      icon: icon,
      action: action,
      onClose: onClose,
    );
  }
}
