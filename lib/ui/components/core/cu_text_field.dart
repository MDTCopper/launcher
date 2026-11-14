import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 输入框：搬运设计层 [TemplateTextField]
/// （标签、错误态、后缀控件、字数上限、密码显隐由它负责）
class CuTextField extends StatelessWidget {
  const CuTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint = '',
    this.error,
    this.enabled = true,
    this.obscure = false,
    this.maxLines = 1,
    this.suffix,
    this.maxLength,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;

  /// 左侧标签（可选）
  final String? label;

  final String hint;
  final String? error;
  final bool enabled;
  final bool obscure;
  final int maxLines;
  final Widget? suffix;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final skin = cuSkinOf(context);
    final field = TemplateTextField(
      skin: skin,
      controller: controller,
      hint: hint,
      enabled: enabled,
      maxLines: maxLines,
      obscure: obscure,
      error: error,
      maxLength: maxLength,
      suffix: suffix,
      onSubmitted: onSubmitted,
    );

    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [
        Text(
          label!,
          style: TemplateType.caption.copyWith(color: skin.textSecondary),
        ),
        field,
      ],
    );
  }
}
