import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;

import '../../core/app_constant.dart';
import '../app_paths.dart';

///日志内容里的时间只写到秒（日期靠跨天时插的那行区分），形如 `21:46:12`
final DateFormat _logTimeFormat = DateFormat('HH:mm:ss');

///跨天时插的日期行，形如 `2026-09-14`
final DateFormat _logDateFormat = DateFormat('yyyy-MM-dd');

///文件头里的启动时间（唯一带完整日期的地方），形如 `2026-09-14T21:46:12`
final DateFormat _logStampFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

///日志文件名格式：**不记年份**——日志最多保留 7 天，跨年也活不过保留期
final DateFormat _logFileNameFormat = DateFormat('MM-ddTHH-mm-ss.SSS');

String _logTimestamp([DateTime? now]) =>
    _logStampFormat.format(now ?? DateTime.now());

///最后一条日志所在的日子：换天时先插一行日期，之后的行只写时间
String? _lastLogDay;

///拼一条日志：跨天先插 `[日期]` 行；内容里的换行保留，续行缩进四格以示同属一条
String _withLogPrefix(String header, String message) {
  final day = _logDateFormat.format(DateTime.now());
  final isNewDay = day != _lastLogDay;
  _lastLogDay = day;

  final lines = message.split('\n');
  final buffer = StringBuffer();
  if (isNewDay) buffer.writeln('[$day]');
  buffer.write('$header ${lines.first}');
  for (final line in lines.skip(1)) {
    buffer.write('\n    $line');
  }
  return buffer.toString();
}

///一条日志的固定格式：`[时间]-[级别]-[模块] 内容`（模块可缺省）
String _logLine(RunTimeLogType type, String message, String? tag) {
  final time = _logTimeFormat.format(DateTime.now());
  return _withLogPrefix(
    '[$time]-[${type.name}]${tag == null ? '' : '-[$tag]'}',
    message,
  );
}

///自定义日志（无级别与模块）：`[时间] 内容`
String _logCustomLine(String message) =>
    _withLogPrefix('[${_logTimeFormat.format(DateTime.now())}]', message);

///写运行时日志。[tag] 是模块标识，约定用英文短名（如 `ModIcon` / `Download`）以便过滤
void addLog(RunTimeLogType type, String message, {String? tag}) =>
    Log.add(type, message, tag: tag);

void addLogAndPrint(RunTimeLogType type, String message, {String? tag}) {
  Log.add(type, message, tag: tag);
  debugPrint('${_logLine(type, message, tag)}\n');
}

void addCustomLog(String message) => Log.addCustom(message);

void addCustomLogAndPrint(String message) {
  Log.addCustom(message);
  debugPrint('${_logCustomLine(message)}\n');
}

///运行时日志，记录程序运行时的事件和错误，需先初始化
abstract class Log {
  static File? _file;

  ///写入队列：`addLog` 这类调用几乎都不 await，而且经常背靠背连着调（游戏输出转发尤其密集），
  ///并发 append 同一个文件会互相覆盖丢行——这里把写入排成一条串行链
  static Future<void> _writeQueue = Future.value();

  static Future<void> init() async {
    final logDir = Directory(AppPaths.logs);
    await logDir.create(recursive: true);
    // 每次启动时清理一周前的日志
    await cleanOutdatedLogs();
    final fileName = '${_logFileNameFormat.format(DateTime.now())}.log';
    final logFile = File(p.join(logDir.path, fileName));
    await logFile.create();
    final platform = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    await logFile.writeAsString(
      'Copper Launcher Run Time Log\n\n'
      'Launch Time : ${_logTimestamp()}\n'
      'Platform : $platform ($version)\n'
      'Version : $appVersion (Build $appBuildNumber)\n'
      '------------------\n',
    );
    // 全部就绪后再挂上，避免中途失败留下半初始化的日志文件
    _file = logFile;
    // 文件头已经带了完整启动时间，首条日志不必再插一行日期
    _lastLogDay = _logDateFormat.format(DateTime.now());
  }

  static Future<void> add(RunTimeLogType type, String message, {String? tag}) =>
      _append('${_logLine(type, message, tag)}\n');

  static Future<void> addCustom(String message) =>
      _append('${_logCustomLine(message)}\n');

  ///把一行排进写入队列（串行 append，避免并发写同一文件丢行）
  static Future<void> _append(String line) {
    final logFile = _file;
    //未初始化（例如单测里直接调用）时静默跳过，别让记日志反而把调用方搞崩
    if (logFile == null) return Future.value();
    _writeQueue = _writeQueue
        .then((_) async {
          await logFile.writeAsString(line, mode: .append);
        })
        //写日志失败只能忽略（不能反过来再记一条日志），但队列得继续往下走
        .catchError((_) {});
    return _writeQueue;
  }

  static Future<void> cleanOutdatedLogs({
    Duration retention = const Duration(days: 7),
  }) async {
    final logDir = Directory(AppPaths.logs);
    if (!await logDir.exists()) return;

    final now = DateTime.now();
    await for (final entity in logDir.list()) {
      if (entity is! File) continue;

      // 文件名不带年份，没法从名字解析创建时间，统一按修改时间算保留期；
      // 旧命名（毫秒纪元）的文件也因此一视同仁，超期即清
      if (now.difference(entity.statSync().modified) <= retention) continue;

      try {
        await entity.delete();
      } catch (_) {
        // 删除失败忽略（文件可能被占用）
      }
    }
  }
}

enum RunTimeLogType { info, error, warning, debug, fault }
