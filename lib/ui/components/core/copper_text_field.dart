import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 内核输入框：单行 / 多行、标签、错误态、前后缀图标
///
/// 颜色全部取 `AppColors`：底 = 输入面、悬停/聚焦换描边、错误换语义色。
/// 不做颜色插值（聚焦态直接换色，换主题不慢半拍）。
class CopperTextField extends StatefulWidget {
  const CopperTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.error,
    this.enabled = true,
    this.obscure = false,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;

  /// 左侧标签（可选）；给了标签就按固定宽排，方便多行对齐
  final String? label;

  final String? hint;
  final String? error;
  final bool enabled;
  final bool obscure;
  final int maxLines;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<CopperTextField> createState() => _CopperTextFieldState();
}

class _CopperTextFieldState extends State<CopperTextField> {
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);
  bool _focused = false;

  void _onFocusChanged() {
    if (_focused != _focus.hasFocus) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final borderColor = !widget.enabled
        ? colors.lowBackgroundOnCard
        : widget.error != null
        ? colors.error
        : _focused
        ? colors.contentBorderFocus
        : colors.contentBorder;

    final field = Container(
      decoration: BoxDecoration(
        color: widget.enabled
            ? colors.inputBackground
            : colors.lowBackgroundOnCard,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.related,
        vertical: AppSpacing.tight,
      ),
      child: Row(
        spacing: AppSpacing.related,
        children: [
          if (widget.prefixIcon != null)
            Icon(
              widget.prefixIcon,
              size: AppIconSize.inline,
              color: colors.itemHint,
            ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              obscureText: widget.obscure,
              maxLines: widget.obscure ? 1 : widget.maxLines,
              autofocus: widget.autofocus,
              style: textTheme.bodyMedium?.copyWith(
                color: widget.enabled ? colors.itemPrimary : colors.itemHint,
              ),
              cursorColor: colors.interactive,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  vertical: widget.maxLines > 1 ? AppSpacing.tight : 6,
                ),
                hintText: widget.hint,
                hintStyle: textTheme.bodyMedium?.copyWith(
                  color: colors.itemHint,
                ),
              ),
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
            ),
          ),
          if (widget.suffixIcon != null)
            Icon(
              widget.suffixIcon,
              size: AppIconSize.inline,
              color: colors.itemHint,
            ),
        ],
      ),
    );

    Widget content = field;
    if (widget.label != null || widget.error != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.tight,
        children: [
          if (widget.label != null)
            Text(
              widget.label!,
              style: textTheme.bodySmall?.copyWith(color: colors.itemSecondary),
            ),
          field,
          if (widget.error != null)
            Text(
              widget.error!,
              style: textTheme.bodySmall?.copyWith(color: colors.error),
            ),
        ],
      );
    }
    return content;
  }
}
