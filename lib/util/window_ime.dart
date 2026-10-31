import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 捕获键位期间临时摘掉窗口的输入法（Windows）
///
/// Flutter 的 Windows 端即使没有文本框也挂着窗口的 IMM32 输入法上下文，
/// 中文输入法会把按键拦成 VK_PROCESSKEY，Flutter 又跳过这些下键事件，
/// 于是捕获弹窗一个键都收不到。这里走 runner 的
/// `io.github.copper.launcher/window_ime` 通道：IMM32 只能由窗口自己的线程操作，
/// Dart 侧直接 FFI 是跨线程的、不可靠
class WindowIme {
  WindowIme._();

  static const MethodChannel _channel = MethodChannel(
    'io.github.copper.launcher/window_ime',
  );

  /// 摘除请求还在路上（弹窗开得快、关得也快时要在恢复前等它）
  static Future<bool>? _pending;

  static bool _detached = false;

  /// 摘掉主窗口的输入法上下文；返回是否真的摘了
  ///
  /// 重复调用共用同一个请求，[restore] 会等它完成再挂回去
  static Future<bool> detach() {
    if (!Platform.isWindows) return Future.value(false);
    if (_detached) return Future.value(true);
    return _pending ??= _requestDetach();
  }

  /// 把输入法上下文挂回去（没摘过就什么也不做）
  static Future<void> restore() async {
    final pending = _pending;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // 摘除失败就没什么可恢复的
      }
    }
    if (!_detached) return;
    _detached = false;
    try {
      await _channel.invokeMethod<void>('restore');
    } catch (_) {
      // 恢复失败就保持禁用：窗口下次拿到焦点时系统会重建输入法上下文
    }
  }

  static Future<bool> _requestDetach() async {
    try {
      _detached = await _channel.invokeMethod<bool>('detach') ?? false;
    } catch (_) {
      _detached = false;
    } finally {
      _pending = null;
    }
    return _detached;
  }

  /// 清掉静态状态：用例之间共享进程，上一次没走完的摘除会漏到下一次
  @visibleForTesting
  static void resetForTesting() {
    _pending = null;
    _detached = false;
  }
}
