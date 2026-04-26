import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show OutlineInputBorder;

class BorderSideTween extends Tween<BorderSide?> {
  BorderSideTween({super.begin, super.end});

  @override
  BorderSide? lerp(double t) {
    if (identical(begin, end)) {
      return begin;
    }
    if (begin == null) {
      return end!.scale(t);
    }
    if (end == null) {
      return begin?.scale(1.0 - t);
    }
    return BorderSide.lerp(begin!, end!, t);
  }
}

class OutlineInputBorderTween extends Tween<OutlineInputBorder?>{
  OutlineInputBorderTween({super.begin, super.end});

  @override
  OutlineInputBorder? lerp(double t) {
    if (identical(begin, end)) {
      return begin;
    }
    if (begin == null) {
      return end!.scale(t);
    }
    if (end == null) {
      return begin?.scale(1.0 - t);
    }
    return OutlineInputBorder(
      borderRadius: BorderRadius.lerp(begin!.borderRadius,end!.borderRadius,t)!,
      borderSide:  BorderSide.lerp(begin!.borderSide, end!.borderSide, t),
      gapPadding: lerpDouble(begin!.gapPadding, end!.gapPadding, t)!,
    );
  }
}
