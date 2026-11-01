// AUTO GENERATED FILE - DO NOT EDIT.
// 由 tool/android_bridge/generate.dart 依据 Dart @KotlinEvent 静态方法生成。
// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。

import 'package:copper_launcher/domain/account/auth_callback_bridge.dart';
import 'package:copper_launcher/domain/shortcut_launch.dart';
import 'package:copper_launcher/util/share_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 非安卓平台没有宿主通道：这里统一短路，调用点不用各自判断平台。
bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

/// Android → Dart 的事件通道
///
/// 事件方法都是静态的，没东西好「注册」：这里只装一次 handler，
/// 收到就按方法名直接调用 @KotlinEvent 标注的那个静态方法。
/// 载荷是位置参数列表；结构体（Dart 侧 @KotlinData）过通道是 Map，
/// 用下面生成的 _xxxFromMap 构造函数还原成 Dart 对象。
class AndroidEvent {
  AndroidEvent._();

  static const _channel = MethodChannel(
    'io.github.copper.launcher/flutter',
    StandardMethodCodec(),
  );

  static bool _started = false;

  /// 装一次宿主事件通道（启动时调一次即可；非安卓平台什么也不做）
  ///
  /// 装之前就发出去的事件会丢：冷启动那次的数据由各功能自己的
  /// `take*` 补取，这里不缓存。
  static void start() {
    if (!_isAndroid || _started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAuthCallback':
          AuthCallbackBridge.onAuthCallback();
        case 'onSharedFiles':
          final args = call.arguments as List<Object?>;
          ShareIn.onSharedFiles((args[0] as List<Object?>).cast<String>());
        case 'onShortcutLaunch':
          final args = call.arguments as List<Object?>;
          ShortcutLaunch.onShortcutLaunch(args[0] as String, args[1] as bool);
      }
      return null;
    });
  }
}
