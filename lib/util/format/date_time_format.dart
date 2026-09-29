import 'package:intl/intl.dart';

extension DateTimeFormatExt on DateTime {
  /// 按 pattern 格式化，底层使用 intl 的 DateFormat
  String format([String pattern = 'yyyy-MM-dd HH:mm:ss']) {
    return DateFormat(pattern).format(this);
  }

  /// 常用快捷方法
  String toDateString() => format('yyyy-MM-dd');
  String toTimeString() => format('HH:mm:ss');
  String toDateTimeString() => format('yyyy-MM-dd HH:mm');
  String toFileNameString() => format('yyyyMMdd_HHmmss');
  String toIsoString() => toIso8601String();

  /// 带本地化的格式化
  String formatWithLocale(String pattern, String locale) {
    return DateFormat(pattern, locale).format(this);
  }
}
