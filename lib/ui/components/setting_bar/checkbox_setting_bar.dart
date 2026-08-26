import 'package:flutter/material.dart';

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

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        SizedBox(width: titleWide ?? 150, child: Text(title)),
        Container(
          padding: EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.fromBorderSide(
              theme.inputDecorationTheme.border?.borderSide ?? BorderSide(),
            ),
          ),
          child: Row(spacing: 4, children: options),
        ),
      ],
    );
  }
}
