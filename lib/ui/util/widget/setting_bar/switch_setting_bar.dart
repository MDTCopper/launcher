
import 'package:flutter/material.dart';

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
    return Row(
      children: [
        SizedBox(width: wide, child: Text(title)),
        Expanded(child: SizedBox()),
        SizedBox(height: 36, child: Switch(value: value, onChanged: onChanged)),
      ],
    );
  }
}
