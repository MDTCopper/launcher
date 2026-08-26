import 'package:flutter/material.dart';

import 'adaptive_title.dart';
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
    return Row(
      children: [
        AdaptiveTitle(title: title, titleWide: wide ?? 150),
        const SizedBox(width: 8),
        Expanded(child: SizedBox()),
        ReboundSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}