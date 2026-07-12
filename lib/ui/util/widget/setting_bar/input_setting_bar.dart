import 'dart:ffi';

import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:flutter/cupertino.dart';

typedef InputSettingBarCallBack = void Function(String);

class InputSettingBar extends StatelessWidget {
  const InputSettingBar({
    super.key,
    required this.title,
    this.initialValue,
    this.onChange,
    this.wide,
    this.titleWide = 150,
    this.controller,
    this.onEditingComplete,
  }) : assert(!(wide != null && titleWide != null && wide <= titleWide));

  final String title;
  final String? initialValue;
  final InputSettingBarCallBack? onChange;
  final double? wide;
  final double? titleWide;
  final TextEditingController? controller;
  final VoidCallback? onEditingComplete;

  @override
  Widget build(BuildContext context) {
    Widget widget = OutlinedTextField(
      labelWidth: titleWide,
      labelSpacing: 0,
      label: title,
      controller: controller,
      onEditingComplete: onEditingComplete,
    );

    if (wide != null) {
      widget = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide!),
        child: widget,
      );
    }

    return widget;
  }
}
