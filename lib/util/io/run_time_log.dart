import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_config.dart';
import '../app_paths.dart';

///运行时日志，记录程序运行时的事件和错误，需先初始化
abstract class RunTimeLog {
  static late File file;

  static Future<void> init() async {
    final logDir = Directory(AppPaths.logs);
    await logDir.create(recursive: true);
    // 每次启动时清理一周前的日志
    await cleanOutdatedLogs();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.log';
    file = File(p.join(logDir.path, fileName));
    await file.create();
    final platform = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    await file.writeAsString(
      'Copper Launcher Run Time Log\n\n'
      'Launch Time : ${DateTime.now().toIso8601String()}\n'
      'AppVersion : ${config.version}\n'
      'Platform : $platform ($version)\n'
      '------------------\n',
    );
  }

  static Future<void> add(RunTimeLogType type, String message) async {
    await file.writeAsString(
      '${DateTime.now().toIso8601String()} [${type.name}] $message\n',
    );
  }

  static Future<void> addCustom(String message) async {
    await file.writeAsString('${DateTime.now().toIso8601String()} $message\n');
  }

  /// 清理过时的日志文件。
  ///
  /// 日志文件名以创建时间戳（毫秒）命名，遍历日志目录并删除
  /// 超过 [retention] 时长的日志文件。
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

enum RunTimeLogType { info, error, warning, debug }
