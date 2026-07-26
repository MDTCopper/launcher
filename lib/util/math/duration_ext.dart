extension DurationExt on Duration {
  /// 加法：两个 Duration 相加。
  Duration operator +(Duration other) =>
      Duration(microseconds: inMicroseconds + other.inMicroseconds);

  /// 减法：两个 Duration 相减。
  Duration operator -(Duration other) =>
      Duration(microseconds: inMicroseconds - other.inMicroseconds);

  /// 乘法：Duration × 数字。
  Duration operator *(num factor) =>
      Duration(microseconds: (inMicroseconds * factor).round());

  /// 除法：Duration ÷ 数字。
  Duration operator /(num divisor) =>
      Duration(microseconds: (inMicroseconds / divisor).round());
}
