import 'package:flutter/material.dart';

import 'setting_bar_row.dart';

class CheckboxSettingBar<T> extends StatelessWidget {
  final String title;

  final double? titleWide;
  final List<Widget> options;

  const CheckboxSettingBar({
    super.key,
    required this.title,
    required this.options,
    this.titleWide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SettingBarRow(
      title: title,
      titleWide: titleWide ?? 150,
      control: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.fromBorderSide(
            theme.inputDecorationTheme.border?.borderSide ?? BorderSide(),
          ),
        ),
        // 多选整组：内容紧凑排列，放不下自动换行
        child: Wrap(spacing: 4, runSpacing: 4, children: options),
      ),
    );
  }
}