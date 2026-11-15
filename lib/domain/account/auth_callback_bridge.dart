import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/util/host_annotations.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 登录回调的「URL 回软件」通道
///
/// Android 上浏览器授权完会以 `copper://oauth/callback?code=…&state=…`
/// 唤起启动器：宿主把 URI 交给 `IncomingIntake` 攒着，并推一个 [onAuthCallback]
/// 当敲门声；[wait] 收到敲门声就去 [take] 一次，另外按低频补取兜住丢失的事件。
///
/// 宿主的 URI 只存一份，但 Dart 侧要能承受「敲门声比 [wait] 先到」：
/// [onAuthCallback] 取出来的 URI 先放进 [_buffered]，[wait] 订阅后再认领，
/// 不再依赖 broadcast 流把事件送到一个此刻还没挂上的监听者。
///
/// 冷启动（进程被杀，从浏览器回来才拉起）时事件发不到 Dart，所以 [wait] 开头还会
/// 主动 [take] 一次 —— 和分享 / 快捷方式「热启动推事件、冷启动自己取」是同一套。
/// 桌面端没注册协议，`take()` 拿不到东西，登录仍走 loopback。
class AuthCallbackBridge {
  AuthCallbackBridge._();

  /// 登录回调用的 scheme 前缀（与 AndroidManifest 里的 intent-filter 一致）
  static const schemePrefix = 'copper://oauth';

  /// 已经从宿主取出来、等 [wait] 认领的回调
  ///
  /// 用队列而不是 broadcast 流：宿主事件可能比 [wait] 先到（例如浏览器返回得很快，
  /// 或者 App 刚从挂起状态恢复），流会把没有监听者的那次事件直接丢掉。
  static final List<Uri> _buffered = [];

  /// 「队列里多了一条」的敲门声；没有监听者也没关系，[wait] 订阅后会自己扫队列
  static final _notify = StreamController<void>.broadcast();

  /// 宿主推来的「有登录回调了」：只当敲门声
  ///
  /// URI 仍然从 [take] 取：宿主只存一份，这里不再复制状态。
  @KotlinEvent()
  static void onAuthCallback() {
    unawaited(_drain());
  }

  static Future<void> _drain() async {
    final uri = await take();
    if (uri == null) return;
    _buffered.add(uri);
    // 极端情况下反复失败会留下无效回调；留一小段就够，别无限堆
    while (_buffered.length > 8) {
      _buffered.removeAt(0);
    }
    _notify.add(null);
  }

  static Uri? _takeBuffered() =>
      _buffered.isEmpty ? null : _buffered.removeAt(0);

  static void _putBack(Uri uri) {
    if (_buffered.length < 8) _buffered.insert(0, uri);
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
  /// 先认领已缓冲的 / 主动取一次兜底冷启动，之后等宿主的敲门声；
  /// Android 上再低频补取一次，补上挂起期间丢掉的事件。
  static Future<Uri?> wait({
    required Duration timeout,
    required bool Function(Uri uri) accept,
  }) async {
    final buffered = _takeBuffered();
    final immediate = buffered ?? await take();
    if (immediate != null) {
      if (accept(immediate)) return immediate;
      // 状态对不上（上一次登录留下的）：放回队列，让它随下一次登录自然过期
      _putBack(immediate);
    }

    final result = Completer<Uri?>();
    void claim() {
      if (result.isCompleted) return;
      while (_buffered.isNotEmpty) {
        final uri = _buffered.removeAt(0);
        if (accept(uri)) {
          result.complete(uri);
          return;
        }
      }
    }

    final subscription = _notify.stream.listen((_) => claim());
    // 订阅之前可能已经有回调进了队列（_drain 先跑完的那一段）
    claim();

    // 挂起期间宿主推的事件可能到不了 Dart：低频去取一次，别让 URI 已经在
    // IncomingIntake 里躺着、登录却等到超时。并发取只允许一个。
    // 只有 Android 有宿主通道；桌面端强制走协议时不去打一个不存在的通道。
    var taking = false;
    final poll = Platform.isAndroid
        ? Timer.periodic(const Duration(milliseconds: 600), (_) async {
            if (result.isCompleted || taking) return;
            taking = true;
            try {
              final uri = await take();
              if (uri == null || result.isCompleted) return;
              if (accept(uri)) {
                result.complete(uri);
              } else {
                _putBack(uri);
              }
            } finally {
              taking = false;
            }
          })
        : null;

    final timeoutTimer = Timer(timeout, () {
      if (!result.isCompleted) result.complete(null);
    });
    try {
      return await result.future;
    } finally {
      timeoutTimer.cancel();
      poll?.cancel();
      await subscription.cancel();
    }
  }
}
