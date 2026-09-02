import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CheckboxSettingBar<T> extends StatelessWidget {
  final String title;
  final double titleWide;
  final String? hint;

  final List<Widget> options;
  final double? optionsWidth;

  ///DropdownLayer参数比较复杂，最好在外部构造好传进来
  final DropdownLayer? dropdown;

  const CheckboxSettingBar({
    super.key,
    required this.title,
    required this.options,
    this.optionsWidth,
    this.titleWide = 150,
    this.hint,
    this.dropdown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Row(
      children: [
        SizedBox(
          width: titleWide,
          child: Row(
            children: [
              Text(title, style: theme.textTheme.bodyMedium),

              if (hint != null) ...[
                const SizedBox(width: 8),
                HintLayer(
                  hint: hint,
                  showOnTap: true,
                  // waitDuration: const Duration(),
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colors.itemHint,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > (optionsWidth ?? 0) ||
                  dropdown == null) {
                return Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.fromBorderSide(
                      theme.inputDecorationTheme.border?.borderSide ??
                          BorderSide(),
                    ),
                  ),
                  child: Row(spacing: 4, mainAxisSize: .min, children: options),
                );
              }
              return dropdown!;
            },
          ),
        ),
      ],
    );
  }
}
