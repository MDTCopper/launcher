import 'package:flutter/material.dart';

import '../feature_button.dart';

class SegmentSettingBar<T> extends StatelessWidget {
  const SegmentSettingBar({
    super.key,
    required this.segments,
    this.multiSelectionEnabled = false,
    required this.onChange,
    required this.selected,
    required this.title,
    this.wide = 150,
  });

  final String title;
  final double? wide;
  final List<ReboundButtonSegment<T>> segments;
  final bool multiSelectionEnabled;
  final void Function(Set<T>) onChange;
  final Set<T> selected;


  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: wide, child: Text(title)),
        Expanded(child: SizedBox()),
        SegmentedReboundButton(
          segments: segments,
          onChange: onChange,
          selected: selected,
          multiSelectionEnabled: multiSelectionEnabled,
        ),
      ],
    );
  }
}
