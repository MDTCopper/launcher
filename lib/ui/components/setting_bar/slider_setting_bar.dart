import 'package:flutter/material.dart';

import 'setting_bar_row.dart';

class SliderSettingBar extends StatelessWidget {
  const SliderSettingBar({
    super.key,
    required this.title,
    this.label,
    required this.value,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.wide = 150,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions = 50,
  });

  final String title;
  final String? label;
  final double? wide;
  final void Function(double)? onChanged;
  final void Function(double)? onChangeStart;
  final void Function(double)? onChangeEnd;
  final double value;
  final int divisions;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return SettingBarRow(
      title: title,
      titleWide: wide ?? 150,
      // 官方 Slider：吸附/赋值/点击跳转由框架保证
      control: Slider(
        value: value,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        min: min,
        max: max,
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
}