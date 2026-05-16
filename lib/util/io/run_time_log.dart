import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_config.dart';
import '../app_paths.dart';

///运行时日志，记录程序运行时的事件和错误，需先初始化
abstract class RunTimeLog {
  static late File file;

  static Future<void> init() async {
    final logDir = Directory(AppPaths.logsDir);
    await logDir.create(recursive: true);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.log';
    file = File(p.join(logDir.path, fileName));
    await file.create();
    final platform = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    await file.writeAsString(
      '${DateTime.now().toIso8601String()}\n'
      'AppVersion: ${config.version}\n'
      'Platform: $platform ($version)\n'
      '------------------\n',
    );
  }

  static Future<void> add(LogType type, String message) async {
    await file.writeAsString(
      '${DateTime.now().toIso8601String()} [${type.name}] $message\n',
    );
  }

  static Future<void> addCustom(String message) async {
    await file.writeAsString('${DateTime.now().toIso8601String()} $message\n');
  }
}

enum LogType { info, error, warning, debug }
