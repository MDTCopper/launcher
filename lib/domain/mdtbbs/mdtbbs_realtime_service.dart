import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_realtime_api.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';

/// `/realtime/v1` 的事件
class MdtbbsRealtimeEvent {
  const MdtbbsRealtimeEvent({
    required this.id,
    required this.event,
    required this.data,
  });

  /// 事件流里的游标（断线重连用）
  final String id;
  final String event;
  final Map<String, dynamic> data;

  factory MdtbbsRealtimeEvent.fromJson(Map<String, dynamic> json) =>
      MdtbbsRealtimeEvent(
        id: '${json['id'] ?? ''}',
        event: '${json['event'] ?? ''}',
        data: (json['data'] is Map)
            ? (json['data'] as Map).cast<String, dynamic>()
            : const {},
      );
}

/// 实时通道：拿一次性票据 → 连 `/realtime/v1` → 心跳 + 断线重连
///
/// 协议（文档「实时事件」一节）：
/// - 连接：`/realtime/v1?ticket=...`，票据一次有效、60 秒不用也过期
/// - 服务端首帧 `hello` 带心跳间隔；客户端 `{"type":"heartbeat"}` 保活
/// - 事件帧 `{id, event, timestamp, data}`；用户流与会话流可分别订阅
/// - 断线重连先发 `resume`（带 `last_event_id`），失败会收到 `resume_failed`，
///   这时唯一正确的做法是重新拉一次快照（我们交给通知服务重拉）
///
/// 这条通道只负责「连上 + 把事件抛出去」，业务处理在
/// `MdtbbsNotificationService.handleRealtimeEvent`
class MdtbbsRealtimeService {
  MdtbbsRealtimeService._() {
    _accounts.snapshot.addListener(_onAccountChanged);
    if (_accounts.isLoggedIn) unawaited(_start());
  }

  static final MdtbbsRealtimeService instance = MdtbbsRealtimeService._();

  /// 事件回调：`(事件名, 数据)`
  void Function(MdtbbsRealtimeEvent event)? onEvent;

  /// `resume_failed` / 长时间断线时回调，让上层重拉快照
  void Function()? onNeedSnapshot;

  /// 事件流里「跟会话有关」的推送（房间关闭、对端离开等）走这个回调
  void Function(MdtbbsRealtimeEvent event)? onSessionEvent;

  /// 当前是否连着（界面可以据此显示「实时 / 轮询」）
  final ValueNotifier<bool> connected = ValueNotifier(false);

  /// 当前订阅的会话（重连后要重新发一遍）
  final Set<String> _subscribedSessions = {};

  /// 订阅某个会话的事件（进房后调用）
  void subscribeSessions(Iterable<String> ids) {
    _subscribedSessions.addAll(ids);
    if (_subscribedSessions.isEmpty) return;
    _send({'type': 'subscribe', 'sessions': _subscribedSessions.toList()});
  }

  /// 退房时取消订阅
  void unsubscribeSessions(Iterable<String> ids) {
    _subscribedSessions.removeAll(ids);
  }

  AccountManager get _accounts => AccountManager.instance;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _connecting = false;
  int _attempt = 0;
  bool _running = false;
  bool _wasLoggedIn = false;

  /// 每条事件流各自的游标（我们只用用户流，会话流留着扩展）
  String? _lastEventId;

  Future<void> _start() async {
    // 已连上或正在连就别再起一条：账号恢复会再通知一次，容易连出两条
    if (_running && (_socket != null || _connecting)) return;
    _running = true;
    await _connect();
  }

  void _stop() {
    _running = false;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_socket?.close());
    _socket = null;
    connected.value = false;
  }

  void _onAccountChanged() {
    final loggedIn = _accounts.isLoggedIn;
    if (loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = loggedIn;
    if (loggedIn) {
      unawaited(_start());
    } else {
      _stop();
      _lastEventId = null;
    }
  }

  Future<void> _connect() async {
    if (!_running || _connecting) return;
    _connecting = true;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    await _socket?.close();
    _socket = null;
    connected.value = false;

    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        _scheduleReconnect();
        return;
      }
      final ticket = await MdtbbsRealtimeApi.ticket(accessToken: token);
      final socket = await WebSocket.connect(ticket.socketUrl);
      _socket = socket;
      connected.value = true;
      _attempt = 0;
      addLogAndPrint(.info, '实时通道已连接', tag: 'Realtime');
      _subscription = socket.listen(
        _onFrame,
        onDone: () {
          addLog(.info, '实时通道断开', tag: 'Realtime');
          connected.value = false;
          _scheduleReconnect();
        },
        onError: (Object error) {
          addLog(.warning, '实时通道出错：$error', tag: 'Realtime');
          connected.value = false;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } on Object catch (error) {
      addLog(.debug, '实时通道连接失败：$error', tag: 'Realtime');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _attempt = (_attempt + 1).clamp(1, 6);
    // 1s → 2s → 4s … 最多 30s，别把服务端打爆
    final seconds = (1 << (_attempt - 1)).clamp(1, 30);
    _reconnect = Timer(Duration(seconds: seconds), () => unawaited(_connect()));
  }

  void _send(Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(jsonEncode(payload));
    } on Object catch (error) {
      addLog(.debug, '实时通道发送失败：$error', tag: 'Realtime');
    }
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final frame = decoded.cast<String, dynamic>();
    switch (frame['type']) {
      case 'hello':
        _startHeartbeat((frame['heartbeat_interval'] as num?)?.toInt() ?? 30);
        if (_subscribedSessions.isNotEmpty) {
          _send({'type': 'subscribe', 'sessions': _subscribedSessions.toList()});
        }
        if (_lastEventId != null) {
          _send({'type': 'resume', 'last_event_id': _lastEventId});
        }
      case 'event':
        final event = MdtbbsRealtimeEvent.fromJson(frame);
        if (event.id.isNotEmpty) _lastEventId = event.id;
        if (event.event.isNotEmpty) {
          addLog(.debug, '实时事件：${event.event}', tag: 'Realtime');
          onEvent?.call(event);
          // 会话事件（房间关闭 / 对端变化）另外抛一路
          if (event.event.startsWith('multiplayer.session') ||
              event.event.startsWith('session.')) {
            onSessionEvent?.call(event);
          }
        }
      case 'resume_failed':
        addLog(.warning, '实时通道恢复失败，需要重拉快照', tag: 'Realtime');
        _lastEventId = null;
        onNeedSnapshot?.call();
      case 'error':
        addLog(.warning, '实时通道服务端报错：${frame['message'] ?? frame['code']}', tag: 'Realtime');
      default:
        break;
    }
  }

  void _startHeartbeat(int seconds) {
    _heartbeat?.cancel();
    final interval = Duration(seconds: seconds.clamp(10, 120));
    // 连上就先打一次：服务端约 30 秒收不到心跳就断开（实测每 32 秒掉一次），
    // 按整间隔发正好卡在边界上，所以按半间隔打
    _send({'type': 'heartbeat'});
    final tick = Duration(milliseconds: interval.inMilliseconds ~/ 2);
    addLog(.debug, '实时通道心跳 ${tick.inSeconds}s', tag: 'Realtime');
    _heartbeat = Timer.periodic(tick, (_) {
      _send({'type': 'heartbeat'});
    });
  }
}
