import 'package:flutter/material.dart';

import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';

import 'setting_bar_row.dart';

class OptionSettingBar<T> extends StatelessWidget {
  final String title;
  final List<DropdownOption<T>> options;
  final void Function(T value)? onSelect;
  final String? hintText;
  final T? initialValue;
  final double? wide;
  final double? titleWide;
  final double menuHeight;

  const OptionSettingBar({
    super.key,
    required this.title,
    required this.options,
    this.onSelect,
    this.initialValue,
    this.wide,
    this.titleWide = 150,
    this.menuHeight = 200,
    this.hintText,
  }) : assert(!(wide != null && titleWide != null && wide <= titleWide));

  @override
  Widget build(BuildContext context) {
    // 下拉框头部占剩余空间，宽窗撑满、窄窗保控件最小宽
    return SettingBarRow(
      title: title,
      titleWide: titleWide ?? 150,
      control: DropdownLayer<T>(
        hintText: hintText ?? '默认',
        width: double.infinity,
        initialValue: initialValue,
        options: options,
        onSelect: onSelect,
        menuHeight: menuHeight,
      ),
    );
  }
}