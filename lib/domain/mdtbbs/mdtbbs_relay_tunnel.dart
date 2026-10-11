import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_relay_frames.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 中继信令：服务端在 WSS 上发的 JSON 文本帧
sealed class MdtbbsRelaySignal {
  const MdtbbsRelaySignal();
}

class MdtbbsRelayAuthOk extends MdtbbsRelaySignal {
  const MdtbbsRelayAuthOk({
    required this.sessionId,
    required this.peerId,
    required this.peerRole,
  });

  final String sessionId;
  final String peerId;
  final String peerRole;
}

class MdtbbsRelayTcpOpenPending extends MdtbbsRelaySignal {
  const MdtbbsRelayTcpOpenPending({required this.streamId});

  final int streamId;
}

class MdtbbsRelayTcpOpened extends MdtbbsRelaySignal {
  const MdtbbsRelayTcpOpened({required this.streamId});

  final int streamId;
}

class MdtbbsRelayTcpOpenFailed extends MdtbbsRelaySignal {
  const MdtbbsRelayTcpOpenFailed({required this.streamId});

  final int streamId;
}

class MdtbbsRelayTcpData extends MdtbbsRelaySignal {
  const MdtbbsRelayTcpData({required this.streamId, required this.payload});

  final int streamId;
  final Uint8List payload;
}

class MdtbbsRelayTcpClosed extends MdtbbsRelaySignal {
  const MdtbbsRelayTcpClosed({required this.streamId});

  final int streamId;
}

class MdtbbsRelayUdpDatagram extends MdtbbsRelaySignal {
  const MdtbbsRelayUdpDatagram({
    required this.targetPeerId,
    required this.payload,
  });

  final String targetPeerId;
  final Uint8List payload;
}

class MdtbbsRelayError extends MdtbbsRelaySignal {
  const MdtbbsRelayError({required this.code});

  final String code;
}

class MdtbbsRelayClosed extends MdtbbsRelaySignal {
  const MdtbbsRelayClosed({required this.reason});

  final String reason;
}

/// 官方中继隧道（MLR1 over WSS）
///
/// 生命周期：[start] 建连并发 auth → 等 `auth_ok` → 之后由 [signals] 驱动上层桥接；
/// 凭证 TTL 到期前 [renewBefore] 秒用 [allocateRelay] 重新拿一份并发 reauth；
/// 续签时 `endpoint` / `agent_id` 与当前不一致视为异常（换代理节点必须整体重建）。
///
/// **同时只允许一条待确认的本地 TCP 连接**（`tcp_open_pending` 只回一个 stream_id，
/// 与参考实现一致），上层要排队
class MdtbbsRelayTunnel {
  MdtbbsRelayTunnel({
    required this.allocateRelay,
    this.renewBefore = 20,
    this.authTimeout = const Duration(seconds: 15),
  });

  /// 重新申请中继凭证（续签时调用；首次建连也会先调一次）
  final Future<MdtbbsRelayAllocation> Function() allocateRelay;

  /// 距到期还剩这么多秒就该续签
  final int renewBefore;
  final Duration authTimeout;

  WebSocket? _socket;
  Timer? _renewTimer;
  MdtbbsRelayAllocation? _allocation;
  StreamSubscription<dynamic>? _subscription;
  bool _closing = false;

  final _signals = StreamController<MdtbbsRelaySignal>.broadcast();
  final _authOk = Completer<MdtbbsRelayAuthOk>();

  /// 认证结果；[start] 完成后即已完成
  Future<MdtbbsRelayAuthOk> get authOk => _authOk.future;

  /// 信令与数据都从这里出（广播流，允许多个订阅者各取所需）
  Stream<MdtbbsRelaySignal> get signals => _signals.stream;

  /// 当前凭证到期时间戳（毫秒）；续签后更新
  DateTime? _credentialExpiresAt;
  DateTime? get credentialExpiresAt => _credentialExpiresAt;

  /// 发送锁不需要：dart 的 WebSocket.add 是同步入队
  Future<MdtbbsRelayAuthOk> start() async {
    _allocation = await allocateRelay();
    final endpoint = _allocation!.endpoint;
    addLog(.info, '连接官方中继：$endpoint', tag: 'Multiplayer');
    final socket = await WebSocket.connect(endpoint);
    _socket = socket;
    _subscription = socket.listen(
      _onMessage,
      onDone: () => _finish('中继连接已断开'),
      onError: (Object error) => _finish('中继连接异常：$error'),
      cancelOnError: true,
    );
    _sendJson({
      'op': 'auth',
      'version': MdtbbsRelayFrame.version,
      'credential': _allocation!.credential,
    });
    _scheduleRenewal();
    return _authOk.future.timeout(
      authTimeout,
      onTimeout: () => throw const MdtbbsRelayException('中继 auth_ok 超时'),
    );
  }

  /// 申请一条到目标对端的 TCP 流；返回中继分配的 streamId
  ///
  /// 上层在拿到 streamId 前不要往这条流写数据；`tcp_opened / tcp_open_failed`
  /// 会作为信号继续送达
  Future<int> openTcpStream(String targetPeerId) async {
    _sendJson({'op': 'tcp_open', 'target_peer_id': targetPeerId});
    final pending = await signals
        .firstWhere((s) => s is MdtbbsRelayTcpOpenPending)
        .timeout(const Duration(seconds: 15));
    return (pending as MdtbbsRelayTcpOpenPending).streamId;
  }

  void sendTcpData(int streamId, List<int> payload) {
    final frame = MdtbbsRelayFrame.tcpData(streamId, payload);
    if (frame != null) _socket?.add(frame);
  }

  void closeTcpStream(int streamId) {
    _socket?.add(MdtbbsRelayFrame.tcpClose(streamId));
  }

  /// 发 UDP 数据报；[targetPeerId] 按方向语义填对端
  void sendUdpDatagram(String targetPeerId, List<int> payload) {
    final frame = MdtbbsRelayFrame.udpDatagram(targetPeerId, payload);
    if (frame != null) _socket?.add(frame);
  }

  Future<void> dispose() async {
    _closing = true;
    _renewTimer?.cancel();
    _renewTimer = null;
    try {
      await _socket?.close();
    } on Object {
      // 已经断了
    }
    await _subscription?.cancel();
    _subscription = null;
    _socket = null;
    _finish('已关闭');
    await _signals.close();
  }

  // ── 内部 ────────────────────────────────────────────────────

  void _onMessage(dynamic message) {
    if (message is String) {
      _onText(message);
      return;
    }
    if (message is Uint8List) {
      _onBinary(message);
      return;
    }
    if (message is List<int>) {
      _onBinary(Uint8List.fromList(message));
    }
  }

  void _onText(String text) {
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(text) as Map).cast<String, dynamic>();
    } on Object {
      addLog(.warning, '中继返回了非 JSON 文本帧', tag: 'Multiplayer');
      return;
    }
    switch ('${json['op'] ?? ''}') {
      case 'auth_ok':
        final signal = MdtbbsRelayAuthOk(
          sessionId: '${json['session_id'] ?? ''}',
          peerId: '${json['peer_id'] ?? ''}',
          peerRole: '${json['peer_role'] ?? ''}',
        );
        addLog(.info, '中继已认证：role=${signal.peerRole}', tag: 'Multiplayer');
        if (!_authOk.isCompleted) _authOk.complete(signal);
        _emit(signal);
      case 'reauth_ok':
        addLog(.info, '中继凭证已续签', tag: 'Multiplayer');
      case 'tcp_open_pending':
        _emit(
          MdtbbsRelayTcpOpenPending(
            streamId: (json['stream_id'] as num?)?.toInt() ?? 0,
          ),
        );
      case 'tcp_opened':
        _emit(
          MdtbbsRelayTcpOpened(
            streamId: (json['stream_id'] as num?)?.toInt() ?? 0,
          ),
        );
      case 'tcp_open_failed':
        _emit(
          MdtbbsRelayTcpOpenFailed(
            streamId: (json['stream_id'] as num?)?.toInt() ?? 0,
          ),
        );
      case 'error':
        _emit(MdtbbsRelayError(code: '${json['code'] ?? ''}'));
      default:
        addLog(.info, '未处理的中继 op：${json['op']}', tag: 'Multiplayer');
    }
  }

  void _onBinary(Uint8List frame) {
    final parsed = MdtbbsRelayFrame.parse(frame);
    if (parsed == null) {
      addLog(
        .warning,
        '收到无法解析的 MLR1 帧（长度 ${frame.length}）',
        tag: 'Multiplayer',
      );
      return;
    }
    switch (parsed.type) {
      case MdtbbsRelayFrame.typeTcpData:
        _emit(
          MdtbbsRelayTcpData(
            streamId: parsed.streamId,
            payload: parsed.payload,
          ),
        );
      case MdtbbsRelayFrame.typeTcpClose:
        _emit(MdtbbsRelayTcpClosed(streamId: parsed.streamId));
      case MdtbbsRelayFrame.typeUdpDatagram:
        _emit(
          MdtbbsRelayUdpDatagram(
            targetPeerId: parsed.targetPeerId,
            payload: parsed.payload,
          ),
        );
    }
  }

  /// TTL 到期前 [renewBefore] 秒续签；续签失败且已不足 8 秒才收尾
  void _scheduleRenewal() {
    final allocation = _allocation;
    if (allocation == null || _closing) return;
    final ttl = allocation.expiresIn > 0
        ? allocation.expiresIn
        : MdtbbsRelayFrameMaxTtl.capabilitiesFallback;
    _credentialExpiresAt = DateTime.now().add(Duration(seconds: ttl));
    final delaySeconds = ttl - renewBefore;
    _renewTimer?.cancel();
    _renewTimer = Timer(
      Duration(seconds: delaySeconds <= 0 ? 0 : delaySeconds),
      () => unawaited(_renew()),
    );
  }

  Future<void> _renew() async {
    if (_closing) return;
    try {
      final next = await allocateRelay();
      if (_allocation != null &&
          (next.endpoint != _allocation!.endpoint ||
              next.agentId != _allocation!.agentId)) {
        throw MdtbbsRelayException(
          '中继换了节点（${_allocation!.agentId} → ${next.agentId}），需要整体重建',
        );
      }
      _allocation = next;
      _sendJson({
        'op': 'reauth',
        'version': MdtbbsRelayFrame.version,
        'credential': next.credential,
      });
      _scheduleRenewal();
    } on Object catch (error) {
      final expiresAt = _credentialExpiresAt;
      final secondsLeft = expiresAt == null
          ? 0
          : expiresAt.difference(DateTime.now()).inSeconds;
      if (secondsLeft < 8) {
        addLog(
          .error,
          '续签失败且凭证即将到期（剩 $secondsLeft 秒）：$error',
          tag: 'Multiplayer',
        );
        _finish('中继凭证续签失败');
        return;
      }
      addLog(
        .warning,
        '续签失败（剩 $secondsLeft 秒），稍后重试：$error',
        tag: 'Multiplayer',
      );
      _renewTimer?.cancel();
      _renewTimer = Timer(
        const Duration(seconds: 5),
        () => unawaited(_renew()),
      );
    }
  }

  void _sendJson(Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null || _closing) return;
    try {
      socket.add(jsonEncode(payload));
    } on Object catch (error) {
      addLog(.warning, '中继信令发送失败：$error', tag: 'Multiplayer');
    }
  }

  void _emit(MdtbbsRelaySignal signal) {
    if (!_signals.isClosed) _signals.add(signal);
  }

  void _finish(String reason) {
    if (_closing) return;
    _closing = true;
    _renewTimer?.cancel();
    _emit(MdtbbsRelayClosed(reason: reason));
  }
}

/// 续签间隔的兜底值（服务端没给 ttl 时按 120 秒）
class MdtbbsRelayException implements Exception {
  const MdtbbsRelayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 与 capabilities 的 ttl 兜底保持一致；这里单列避免反向依赖模型文件
class MdtbbsRelayFrameMaxTtl {
  MdtbbsRelayFrameMaxTtl._();

  static const int capabilitiesFallback = 120;
}
