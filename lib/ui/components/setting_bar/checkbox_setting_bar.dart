import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:flutter/material.dart';

import 'setting_bar_row.dart';

class CheckboxSettingBar<T> extends StatelessWidget {
  final String title;

  final double? titleWide;
  final List<Widget> options;

  /// 提供时在选项组尾部显示"重置"按钮(清空勾选，特定场景自选)。
  final VoidCallback? onReset;

  const CheckboxSettingBar({
    super.key,
    required this.title,
    required this.options,
    this.titleWide,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final resetButton = onReset == null
        ? null
        : ReboundButton(
            pressedScale: 0.9,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            onTap: onReset,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restart_alt, size: 14),
                SizedBox(width: 4),
                Text('重置'),
              ],
            ),
          );

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
        // 多选整组：内容紧凑排列，放不下自动换行；重置按钮随组显示
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [...options, ?resetButton],
        ),
      ),
    );
  }
}
