import 'package:flutter/material.dart';

import 'setting_bar_row.dart';
import '../rebound/rebound_switch.dart';

class SwitchSettingBar extends StatelessWidget {
  const SwitchSettingBar({
    super.key,
    required this.title,
    required this.value,
    this.onChanged,
    this.wide = 150,
  });

  final String title;
  final double? wide;
  final void Function(bool)? onChanged;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return SettingBarRow(
      title: title,
      titleWide: wide ?? 150,
      // 开关固定尺寸，右对齐贴边
      control: Align(
        alignment: Alignment.centerRight,
        child: ReboundSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}