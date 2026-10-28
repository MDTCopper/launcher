import 'dart:async';

import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/services.dart';

/// 登录回调的「URL 回软件」通道
///
/// Android 上浏览器授权完会以 `copperlauncher://oauth/callback?code=…&state=…`
/// 唤起启动器（宿主 `MainActivity` 收下后攒着），这里把它取回来。
/// 桌面端暂未注册协议，`take()` 直接返回 null，登录仍走 loopback。
class AuthCallbackBridge {
  AuthCallbackBridge._();

  static const _channel = MethodChannel('io.github.copper.launcher/host');

  /// 登录回调用的 scheme 前缀（与 AndroidManifest 里的 intent-filter 一致）
  static const schemePrefix = 'copperlauncher://oauth';

  /// 取一条待处理的回调 URI；没有就 null
  static Future<Uri?> take() async {
    try {
      final value = await _channel.invokeMethod<String>('takeAuthUri');
      if (value == null || value.isEmpty) return null;
      final uri = Uri.tryParse(value);
      if (uri == null) return null;
      addLogAndPrint(.info, '收到登录回调：${uri.scheme}://${uri.host}', tag: 'Account');
      return uri;
    } on MissingPluginException {
      // 桌面 / 测试环境没这条通道
      return null;
    } on PlatformException catch (error) {
      addLog(.debug, '取登录回调失败：${error.message}', tag: 'Account');
      return null;
    }
  }

  /// 在登录等待期间轮询回调 URI（[timeout] 内没等到就返回 null）
  static Future<Uri?> wait({
    required Duration timeout,
    required bool Function(Uri uri) accept,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final uri = await take();
      if (uri != null && accept(uri)) return uri;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return null;
  }
}
