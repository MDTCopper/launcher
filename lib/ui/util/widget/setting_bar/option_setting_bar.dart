import 'package:flutter/material.dart';

import '../animated_dropdown_menu.dart';

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
    this.wide ,
    this.titleWide= 150,
    this.menuHeight = 200,
    this.hintText,
  }) : assert(!(wide != null && titleWide != null && wide <= titleWide));

  @override
  Widget build(BuildContext context) {
    double buttonWide = wide ?? double.infinity;
    if (titleWide != null) buttonWide -= titleWide!;

    return Row(
      children: [
        SizedBox(width: titleWide, child: Text(title)),
        Expanded(
          child: AnimatedDropdownMenu<T>(
            hintText: hintText??'默认',
            width: buttonWide,
            initialValue: initialValue,
            options: options,
            onSelect: onSelect,
            menuHeight: menuHeight,
          ),
        ),
      ],
    );
  }
}


