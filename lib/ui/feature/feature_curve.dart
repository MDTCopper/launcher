import 'package:flutter/widgets.dart';

abstract class FeatureCurves {
  static const Curve reboundIn = Cubic(0.20, 0.15, 0.20, 1.30);
  static const Curve reboundOut = Cubic(0.80, -0.29, 0.75, 0.80);
  static const Curve reboundInOut = Cubic(0.80, -0.30, 0.20, 1.30);
  static const Curve reboundInStrong = Cubic(0.16, 0.20, 0.16, 1.43);
  static const Curve reboundOutStrong = Cubic(0.23, -0.90, 0.75, 0.80);
}