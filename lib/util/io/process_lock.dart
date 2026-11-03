import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/util/io/log.dart';

/// 进程间文件锁：靠「独占创建锁文件」实现，用来保护小文件的读-改-写
///
/// **只包住临界区**：不要跨网络请求持有，否则另一个进程会等很久
class ProcessFileLock {
  const ProcessFileLock._();

  static const _retryGap = Duration(milliseconds: 30);

  /// 等锁时的上限与「上个进程崩了没删锁」的判定
  static const defaultTimeout = Duration(seconds: 5);
  static const defaultStaleAfter = Duration(seconds: 20);

  /// 拿锁执行 [action]；拿不到就等，等不到就放行（宁可冒一次并发，也别把用户卡死）
  static Future<T> run<T>(
    String lockPath,
    FutureOr<T> Function() action, {
    Duration timeout = defaultTimeout,
    Duration staleAfter = defaultStaleAfter,
  }) async {
    final lockFile = File(lockPath);
    final deadline = DateTime.now().add(timeout);
    var acquired = false;
    while (true) {
      try {
        lockFile.parent.createSync(recursive: true);
        lockFile.createSync(exclusive: true);
        lockFile.writeAsStringSync(
          '$pid ${DateTime.now().toIso8601String()}',
          flush: true,
        );
        acquired = true;
        break;
      } on FileSystemException {
        // 锁文件很旧：持有者多半崩了没删，直接接管
        try {
          final modified = lockFile.statSync().modified;
          if (DateTime.now().difference(modified) > staleAfter) {
            lockFile.deleteSync();
            continue;
          }
        } catch (_) {
          // 锁刚被别人删掉：下一轮再抢
        }
        if (!DateTime.now().isBefore(deadline)) {
          addLog(
            .warning,
            '等文件锁超时（$lockPath），这次不加锁继续',
            tag: 'Lock',
          );
          break;
        }
        await Future<void>.delayed(_retryGap);
      }
    }
    try {
      return await action();
    } finally {
      if (acquired) {
        try {
          lockFile.deleteSync();
        } catch (_) {
          // 已经没了就不用管
        }
      }
    }
  }
}
