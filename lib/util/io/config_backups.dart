import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 启动器配置的备份
///
/// **一次运行最多一份**（启动拿到可用配置之后留底）：`config.save()` 有几十处调用点、
/// 切页面与改主题都会触发，按次备份几个槽位几下就被刷满；按启动留底则与写入频率无关，
/// 而且存下来的正是「上个会话结束时那份**能被解析**的状态」——最适合当回滚目标。
///
/// 备份一律用 JSON（debug / release 都能读，用户也能直接打开看），回退时取
/// **最新的那份能解析的**（坏文件自动跳过）
class ConfigBackups {
  ConfigBackups._();

  static const dirName = 'config-backups';
  static const filePrefix = 'config-';
  static const fileSuffix = '.json';

  /// 只留最近这么多份
  static const keep = 5;

  static String dirOf(String root) => p.join(root, dirName);

  /// 留一份底，返回写出的文件；**任何失败都只记日志、不往外抛**（备份不许拦启动）
  static File? write({
    required String root,
    required Map<String, dynamic> json,
    DateTime? now,
  }) {
    final directory = Directory(dirOf(root));
    final file = File(
      p.join(
        directory.path,
        '$filePrefix${_stamp(now ?? DateTime.now())}$fileSuffix',
      ),
    );
    try {
      directory.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
    } catch (error) {
      addLog(.warning, '配置备份写入失败：${removeNewlines('$error')}', tag: 'Config');
      return null;
    }
    prune(root);
    return file;
  }

  /// 最新的那份**能解析**的备份；一份都没有 / 全都解不开时给 null
  static ({File file, Map<String, dynamic> json})? newestReadable(String root) {
    for (final file in _filesNewestFirst(root)) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map) continue;
        return (file: file, json: decoded.cast<String, dynamic>());
      } catch (error) {
        addLog(
          .warning,
          '配置备份读不出来，跳过 ${p.basename(file.path)}：${removeNewlines('$error')}',
          tag: 'Config',
        );
      }
    }
    return null;
  }

  /// 只留最近 [keep] 份（文件名带时刻，倒序即最新在前）
  static void prune(String root) {
    try {
      for (final file in _filesNewestFirst(root).skip(keep)) {
        file.deleteSync();
      }
    } catch (error) {
      addLog(.warning, '清理旧配置备份失败：${removeNewlines('$error')}', tag: 'Config');
    }
  }

  static List<File> _filesNewestFirst(String root) {
    final directory = Directory(dirOf(root));
    if (!directory.existsSync()) return const [];
    final files = <File>[];
    try {
      for (final entity in directory.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith(filePrefix) && name.endsWith(fileSuffix)) {
          files.add(entity);
        }
      }
    } catch (error) {
      addLog(.warning, '配置备份目录列不出来：${removeNewlines('$error')}', tag: 'Config');
      return const [];
    }
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  /// 2026-10-05T11-20-33 这种形态（能被名字排序直接当时间用）
  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
