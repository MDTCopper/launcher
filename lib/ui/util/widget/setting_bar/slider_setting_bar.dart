import 'package:flutter/material.dart';

class SliderSettingBar extends StatelessWidget {
  const SliderSettingBar({
    super.key,
    required this.title,
    this.label,
    required this.value,
    this.onChanged,
    this.wide = 150,
    this.min = 0.0 ,
    this.max =1.0,
    this.divisions = 50,
  });

  final String title;
  final String? label;
  final double? wide;
  final void Function(double)? onChanged;
  final double value;
  final int divisions;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: wide, child: Text(title)),
        Expanded(
          child: Slider(
            value: value,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
            min: min,
            max: max,
            padding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }
}
