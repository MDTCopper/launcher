import 'dart:async';

import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/util/host_annotations.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 登录回调的「URL 回软件」通道
///
/// Android 上浏览器授权完会以 `copperlauncher://oauth/callback?code=…&state=…`
/// 唤起启动器：宿主把 URI 交给 `IncomingIntake` 攒着，并推一个 [onAuthCallback]
/// 当敲门声；[wait] 收到敲门声就去 [take] 一次，不再定时轮询通道。
///
/// 冷启动（进程被杀，从浏览器回来才拉起）时事件发不到 Dart，所以 [wait] 开头还会
/// 主动 [take] 一次 —— 和分享 / 快捷方式「热启动推事件、冷启动自己取」是同一套。
/// 桌面端没注册协议，`take()` 拿不到东西，登录仍走 loopback。
class AuthCallbackBridge {
  AuthCallbackBridge._();

  /// 登录回调用的 scheme 前缀（与 AndroidManifest 里的 intent-filter 一致）
  static const schemePrefix = 'copperlauncher://oauth';

  /// 已经取出来、等 [wait] 认领的回调；没人等就丢掉（下次登录重新授权）
  static final _pending = StreamController<Uri>.broadcast();

  /// 宿主推来的「有登录回调了」：只当敲门声
  ///
  /// URI 仍然从 [take] 取：宿主只存一份，这里不再复制状态。
  @KotlinEvent()
  static void onAuthCallback() {
    unawaited(_drain());
  }

  static Future<void> _drain() async {
    final uri = await take();
    if (uri != null) _pending.add(uri);
  }

  /// 取一条待处理的回调 URI；没有就 null
  static Future<Uri?> take() async {
    final String? value;
    try {
      value = await AndroidCall.takeAuthUri();
    } on Object catch (error) {
      addLog(.warning, '取登录回调失败：$error', tag: 'Account');
      return null;
    }
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    addLogAndPrint(.info, '收到登录回调：${uri.scheme}://${uri.host}', tag: 'Account');
    return uri;
  }

  /// 等一条能通过 [accept] 的回调（[timeout] 内没等到就返回 null）
  ///
  /// 先主动取一次兜底冷启动，之后等宿主的敲门声；不再按固定间隔轮询。
  static Future<Uri?> wait({
    required Duration timeout,
    required bool Function(Uri uri) accept,
  }) async {
    final immediate = await take();
    if (immediate != null && accept(immediate)) return immediate;

    final result = Completer<Uri?>();
    final subscription = _pending.stream.listen((uri) {
      if (result.isCompleted || !accept(uri)) return;
      result.complete(uri);
    });
    final timer = Timer(timeout, () {
      if (!result.isCompleted) result.complete(null);
    });
    try {
      return await result.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }
}
