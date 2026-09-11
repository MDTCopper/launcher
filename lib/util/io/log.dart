import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';

void addLog(RunTimeLogType type, String message) => Log.add(type, message);

void addLogAndPrint(RunTimeLogType type, String message) {
  Log.add(type, message);
  debugPrint('[${DateTime.now().toIso8601String()}]-[${type.name}] $message\n');
}

void addCustomLog(String message) => Log.addCustom(message);

void addCustomLogAndPrint(String message) {
  Log.addCustom(message);
  debugPrint('[${DateTime.now().toIso8601String()}] $message\n');
}

///运行时日志，记录程序运行时的事件和错误，需先初始化
abstract class Log {
  static File? _file;

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
      'Launch Time : ${DateTime.now().toIso8601String()}\n'
      'Platform : $platform ($version)\n'
      '------------------\n',
    );
    // 全部就绪后再挂上，避免中途失败留下半初始化的日志文件
    _file = logFile;
  }

  static Future<void> add(RunTimeLogType type, String message) async {
    // 未初始化（例如单测里直接调用）时静默跳过，别让记日志反而把调用方搞崩
    final logFile = _file;
    if (logFile == null) return;
    await logFile.writeAsString(
      '[${DateTime.now().toIso8601String()}]-[${type.name}] $message\n',
      mode: .append,
    );
  }

  static Future<void> addCustom(String message) async {
    final logFile = _file;
    if (logFile == null) return;
    await logFile.writeAsString(
      '[${DateTime.now().toIso8601String()}] $message\n',
      mode: .append,
    );
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
