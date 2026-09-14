import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;

import '../../core/app_constant.dart';
import '../app_paths.dart';

///日志时间戳统一到秒（够用且短），形如 `2026-09-14T21:46:12`
final DateFormat _logStampFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

String _logTimestamp([DateTime? now]) =>
    _logStampFormat.format(now ?? DateTime.now());

void addLog(RunTimeLogType type, String message) => Log.add(type, message);

void addLogAndPrint(RunTimeLogType type, String message) {
  Log.add(type, message);
  debugPrint('[${_logTimestamp()}]-[${type.name}] $message\n');
}

void addCustomLog(String message) => Log.addCustom(message);

void addCustomLogAndPrint(String message) {
  Log.addCustom(message);
  debugPrint('[${_logTimestamp()}] $message\n');
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
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.log';
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
  }

  static Future<void> add(RunTimeLogType type, String message) =>
      _append('[${_logTimestamp()}]-[${type.name}] $message\n');

  static Future<void> addCustom(String message) =>
      _append('[${_logTimestamp()}] $message\n');

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

      // 解析文件名中的创建时间戳；非时间戳命名的文件跳过（容错）
      final createdMs = int.tryParse(p.basenameWithoutExtension(entity.path));
      if (createdMs == null) continue;

      final created = DateTime.fromMillisecondsSinceEpoch(createdMs);
      if (now.difference(created) > retention) {
        try {
          await entity.delete();
        } catch (_) {
          // 删除失败忽略（文件可能被占用）
        }
      }
    }
  }
}

enum RunTimeLogType { info, error, warning, debug, fault }
