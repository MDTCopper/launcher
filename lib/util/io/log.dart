import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;

import '../../core/app_constant.dart';
import '../../core/app_paths.dart';
import '../../core/app_runtime.dart';

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

/// 日志只做格式化，**不做脱敏兜底**：
/// token、Authorization / Cookie、请求体、带 query 的 URL 都不能进日志，
/// 必须在调用点拼消息时就不传进来（需要记 URL 时用 [logSafeUrl]）。
///
/// 日志里会带凭证的 query 键：这些键的值一律不打印
const _sensitiveQueryKeys = {
  'access_token',
  'refresh_token',
  'id_token',
  'token',
  'code',
  'state',
  'ticket',
  'client_secret',
  'password',
  'passwd',
  'code_verifier',
  'authorization',
  'cookie',
  'api_key',
  'x-api-key',
  'join_code',
  'room_token',
  'resume_token',
  'lanlink_token',
  'session_token',
  'pending_refresh_token',
  'pending_refresh_key',
};

/// 凭证类值的中段打码：保留前 2 / 后 2 个字符，中间换成 `***`。
///
/// 不整段删除：既保留“有没有值、大致长度、前后缀”的排查信息，
/// 又不把完整 token / 房间码写进日志。
String maskForLog(String value) {
  if (value.isEmpty) return value;
  if (value.length <= 4) return '***';
  return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
}

/// 写日志时的 URL 文本：userinfo 的密码、敏感 query 参数只打码中段，
/// 其余部分（包括普通 query）原样保留，方便排查。
///
/// 调用方在拼日志消息时显式用它；这是按 key 精确打码，不是对整条日志做兜底。
String logSafeUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    // 解析不了就不要回写原文：原文本身可能带凭证
    return '<url>';
  }
  final buffer = StringBuffer('${uri.scheme}://');
  final userInfo = uri.userInfo;
  if (userInfo.isNotEmpty) {
    final separator = userInfo.indexOf(':');
    if (separator < 0) {
      buffer.write('${maskForLog(userInfo)}@');
    } else {
      buffer.write(
        '${userInfo.substring(0, separator)}:'
        '${maskForLog(userInfo.substring(separator + 1))}@',
      );
    }
  }
  buffer.write(uri.host);
  if (uri.hasPort) buffer.write(':${uri.port}');
  buffer.write(uri.path.isEmpty ? '/' : uri.path);

  final safeQuery = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    safeQuery[key] = _sensitiveQueryKeys.contains(key.toLowerCase())
        ? maskForLog(value)
        : value;
  });
  if (safeQuery.isNotEmpty) {
    final query = safeQuery.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&')
        // Uri 的 query 编码会把 *** 变成 %2A%2A%2A；日志里保留可读的 ***
        .replaceAll('%2A', '*');
    buffer.write('?$query');
  }
  if (uri.hasFragment) buffer.write('#${uri.fragment}');
  return buffer.toString();
}

/// 把一段文本里的 URL 逐个按 [logSafeUrl] 打码；用于 WebSocket 异常文案，
/// 既保留错误描述，又不会把 `?ticket=…` 原样带出去。
final RegExp _urlInTextPattern = RegExp(
  r'[a-z][a-z0-9+.-]*://[^\s]+',
  caseSensitive: false,
);

String maskUrlsInText(String text) =>
    text.replaceAllMapped(_urlInTextPattern, (match) => logSafeUrl(match[0]!));

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

  /// 日志文件是否已就绪：首帧早于 `Log.init()` 的场景（无界面代理）里，
  /// 写日志的调用点要先看一眼，否则那几行会被静默丢掉
  static bool get ready => _file != null;

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
      'Copper Launcher 运行时日志\n\n'
      '启动时间 : ${_logTimestamp()}\n'
      '平台 : $platform ($version)\n'
      '启动器版本 : $appVersion (Build $appBuildNumber)\n'
      '构建模式 : ${kDebugMode ? 'Debug' : 'Release'}\n'
      '启动形态 : ${AppRuntime.form.label}\n'
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
