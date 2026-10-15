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
    required this.expiresAt,
  });

  final String sessionId;
  final String peerId;
  final String peerRole;
  final String? expiresAt;
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

class MdtbbsRelayTcpOpenResult extends MdtbbsRelaySignal {
  const MdtbbsRelayTcpOpenResult({required this.streamId, required this.ok});
  final int streamId;
  final bool ok;
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

class MdtbbsRelayException implements Exception {
  const MdtbbsRelayException(this.message, {this.authRejected = false});
  final String message;
  final bool authRejected;

  @override
  String toString() => message;
}

/// 官方中继隧道（MLR1 over WSS）
///
/// 生命周期：[start] 申请凭证 → 建连 → auth → 等 `auth_ok` → 之后由 [signals]
/// 驱动上层桥接；凭证到期前 [renewBefore] 秒用 [allocateRelay] 拿续签凭证发 reauth。
///
/// 尚未连上的 active allocation 不能重复申请；已经 connected 的 allocation
/// 由控制面复用原 allocation / connection_id 签发续签凭证。
class MdtbbsRelayTunnel {
  MdtbbsRelayTunnel({
    required this.allocateRelay,
    this.renewBefore = 20,
    this.authTimeout = const Duration(seconds: 15),
  });

  final Future<MdtbbsRelayAllocation> Function() allocateRelay;
  final int renewBefore;
  final Duration authTimeout;

  WebSocket? _socket;
  Timer? _renewTimer;
  MdtbbsRelayAllocation? _allocation;
  StreamSubscription<dynamic>? _subscription;
  bool _closing = false;

  final _signals = StreamController<MdtbbsRelaySignal>.broadcast();
  Completer<MdtbbsRelayAuthOk>? _authCompleter;
  Completer<void>? _reauthCompleter;

  /// tcp_open_pending 没有请求 ID，多个 open 并发时无法把响应归属到调用方。
  Future<void> _tcpOpenTail = Future<void>.value();

  Stream<MdtbbsRelaySignal> get signals => _signals.stream;

  DateTime? _credentialExpiresAt;
  DateTime? get credentialExpiresAt => _credentialExpiresAt;

  Future<MdtbbsRelayAuthOk> start() async {
    _allocation = await allocateRelay();
    final alloc = _allocation!;
    _credentialExpiresAt = DateTime.now().add(
      Duration(seconds: alloc.expiresIn > 0 ? alloc.expiresIn : 120),
    );
    addLogAndPrint(
      .info,
      '中继凭证已分配：agent=${alloc.agentId} alloc=${alloc.allocationId} '
      'ttl=${alloc.expiresIn}s 分配请求=${alloc.requestId ?? '—'}',
      tag: 'Multiplayer',
    );
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final auth = await _connectAndAuth();
        _scheduleRenewal(expiresAt: auth.expiresAt);
        return auth;
      } on MdtbbsRelayException catch (error) {
        lastError = error;
        await _teardownSocket();
        if (!error.authRejected || attempt == 3) rethrow;
        addLogAndPrint(
          .info,
          '中继认证被拒（第 $attempt 次），${5 * attempt} 秒后用同一份凭证重试…',
          tag: 'Multiplayer',
        );
        await Future<void>.delayed(Duration(seconds: 5 * attempt));
      }
    }
    throw lastError ?? const MdtbbsRelayException('中继认证失败');
  }

  Future<MdtbbsRelayAuthOk> _connectAndAuth() async {
    final completer = Completer<MdtbbsRelayAuthOk>();
    _authCompleter = completer;
    try {
      await _connect();
      addLogAndPrint(
        .info,
        '已发送中继认证（op=auth，agent=${_allocation!.agentId}，凭证不落日志）',
        tag: 'Multiplayer',
      );
      _sendJson({
        'op': 'auth',
        'version': MdtbbsRelayFrame.version,
        'credential': _allocation!.credential,
      });
      return await completer.future.timeout(
        authTimeout,
        onTimeout: () {
          unawaited(_teardownSocket());
          throw const MdtbbsRelayException('中继 auth_ok 超时');
        },
      );
    } finally {
      if (identical(_authCompleter, completer)) _authCompleter = null;
    }
  }

  Future<void> _connect() async {
    final endpoint = _allocation!.endpoint;
    addLogAndPrint(.info, '连接官方中继：$endpoint', tag: 'Multiplayer');
    final socket = await WebSocket.connect(endpoint).timeout(
      authTimeout,
      onTimeout: () {
        throw MdtbbsRelayException('连接中继超时（$endpoint）');
      },
    );
    _socket = socket;
    _subscription = socket.listen(
      _onMessage,
      onDone: () => _finish('中继连接已断开'),
      onError: (Object error) => _finish('中继连接异常：$error'),
      cancelOnError: true,
    );
  }

  Future<void> _teardownSocket() async {
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    await subscription?.cancel();
    try {
      await socket?.close();
    } on Object {
      // 已经断了
    }
  }

  Future<int> openTcpStream(String targetPeerId) {
    final result = Completer<int>();
    _tcpOpenTail = _tcpOpenTail.then((_) async {
      try {
        result.complete(await _openTcpStreamOnce(targetPeerId));
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<int> _openTcpStreamOnce(String targetPeerId) async {
    if (_closing || _socket == null) {
      throw const MdtbbsRelayException('中继尚未连接');
    }

    final result = Completer<int>();
    int? pendingStreamId;
    late final StreamSubscription<MdtbbsRelaySignal> subscription;
    subscription = signals.listen((signal) {
      if (result.isCompleted) return;
      if (signal is MdtbbsRelayTcpOpenPending && pendingStreamId == null) {
        if (signal.streamId <= 0) {
          result.completeError(const MdtbbsRelayException('中继返回了无效 stream_id'));
          return;
        }
        pendingStreamId = signal.streamId;
        return;
      }
      if (signal is MdtbbsRelayTcpOpened &&
          pendingStreamId != null &&
          signal.streamId == pendingStreamId) {
        result.complete(signal.streamId);
        return;
      }
      if (signal is MdtbbsRelayTcpOpenFailed &&
          (pendingStreamId == null || signal.streamId == pendingStreamId)) {
        result.completeError(
          MdtbbsRelayException('中继 TCP stream ${signal.streamId} 打开失败'),
        );
        return;
      }
      if (signal is MdtbbsRelayClosed) {
        result.completeError(MdtbbsRelayException(signal.reason));
      }
    });

    try {
      _sendJson({'op': 'tcp_open', 'target_peer_id': targetPeerId});
      return await result.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const MdtbbsRelayException('中继 TCP stream 打开超时'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  void sendTcpData(int streamId, List<int> payload) {
    final socket = _socket;
    if (socket == null || _closing || payload.isEmpty) return;
    for (var offset = 0; offset < payload.length;) {
      final remaining = payload.length - offset;
      final chunkLength = remaining > MdtbbsRelayFrame.maxTcpPayload
          ? MdtbbsRelayFrame.maxTcpPayload
          : remaining;
      final end = offset + chunkLength;
      final frame = MdtbbsRelayFrame.tcpData(
        streamId,
        payload.sublist(offset, end),
      );
      if (frame != null) socket.add(frame);
      offset = end;
    }
  }

  void closeTcpStream(int streamId) {
    if (streamId <= 0 || _closing) return;
    _socket?.add(MdtbbsRelayFrame.tcpClose(streamId));
  }

  void sendUdpDatagram(String targetPeerId, List<int> payload) {
    final frame = MdtbbsRelayFrame.udpDatagram(targetPeerId, payload);
    if (frame != null) _socket?.add(frame);
  }

  Future<void> dispose() async {
    if (_signals.isClosed) return;
    _closing = true;
    _renewTimer?.cancel();
    _renewTimer = null;
    _completePendingWaiters('已关闭');
    await _teardownSocket();
    if (!_signals.isClosed) await _signals.close();
  }

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
      addLogAndPrint(.warning, '中继返回了非 JSON 文本帧', tag: 'Multiplayer');
      return;
    }
    switch ('${json['op'] ?? ''}') {
      case 'auth_ok':
        final signal = MdtbbsRelayAuthOk(
          sessionId: '${json['session_id'] ?? ''}',
          peerId: '${json['peer_id'] ?? ''}',
          peerRole: '${json['peer_role'] ?? ''}',
          expiresAt: json['expires_at']?.toString(),
        );
        addLogAndPrint(
          .info,
          '中继已认证：role=${signal.peerRole}，凭证到 ${signal.expiresAt}',
          tag: 'Multiplayer',
        );
        final completer = _authCompleter;
        if (completer != null && !completer.isCompleted) completer.complete(signal);
        _emit(signal);
      case 'reauth_ok':
        final completer = _reauthCompleter;
        if (completer != null && !completer.isCompleted) completer.complete();
        addLogAndPrint(.info, '中继凭证已续签', tag: 'Multiplayer');
      case 'tcp_open_pending':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        _emit(MdtbbsRelayTcpOpenPending(streamId: streamId));
      case 'tcp_opened':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        _emit(MdtbbsRelayTcpOpened(streamId: streamId));
      case 'tcp_open_failed':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        _emit(MdtbbsRelayTcpOpenFailed(streamId: streamId));
      case 'tcp_open_result':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        final ok = json['ok'] == true || json['success'] == true;
        _emit(MdtbbsRelayTcpOpenResult(streamId: streamId, ok: ok));
      case 'error':
        final code = '${json['code'] ?? ''}';
        addLogAndPrint(.warning, '中继报错：code=$code', tag: 'Multiplayer');
        if (code == 'AUTH_INVALID') {
          final allocation = _allocation;
          final expiresAt = _credentialExpiresAt?.toIso8601String() ?? '—';
          addLogAndPrint(
            .warning,
            '中继拒绝认证（诊断用）：'
            'alloc=${allocation?.allocationId ?? '—'} '
            'agent=${allocation?.agentId ?? '—'} '
            '分配请求=${allocation?.requestId ?? '—'} '
            '凭证到期=$expiresAt',
            tag: 'Multiplayer',
          );
        }
        final auth = _authCompleter;
        if (auth != null && !auth.isCompleted) {
          auth.completeError(
            MdtbbsRelayException(
              code.isEmpty ? '中继认证失败' : '中继认证被拒（$code）',
              authRejected: code == 'AUTH_INVALID',
            ),
          );
        }
        final reauth = _reauthCompleter;
        if (reauth != null && !reauth.isCompleted) {
          reauth.completeError(
            MdtbbsRelayException(
              code.isEmpty ? '中继续签失败' : '中继续签被拒（$code）',
            ),
          );
        }
        _emit(MdtbbsRelayError(code: code));
      default:
        addLogAndPrint(.info, '未处理的中继 op：${json['op']}', tag: 'Multiplayer');
    }
  }

  void _onBinary(Uint8List frame) {
    final parsed = MdtbbsRelayFrame.parse(frame);
    if (parsed == null) {
      addLogAndPrint(
        .warning,
        '收到无法解析的 MLR1 帧（长度 ${frame.length}）',
        tag: 'Multiplayer',
      );
      return;
    }
    switch (parsed.type) {
      case MdtbbsRelayFrame.typeTcpData:
        _emit(MdtbbsRelayTcpData(streamId: parsed.streamId, payload: parsed.payload));
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

  void _scheduleRenewal({String? expiresAt}) {
    final allocation = _allocation;
    if (allocation == null || _closing) return;
    final fallback = DateTime.now().add(
      Duration(
        seconds: allocation.expiresIn > 0
            ? allocation.expiresIn
            : MdtbbsRelayFrameMaxTtl.capabilitiesFallback,
      ),
    );
    final parsed = expiresAt == null ? null : DateTime.tryParse(expiresAt);
    _credentialExpiresAt = parsed ?? fallback;
    final secondsLeft = _credentialExpiresAt!.difference(DateTime.now()).inSeconds;
    final delaySeconds = secondsLeft - renewBefore;
    _renewTimer?.cancel();
    _renewTimer = Timer(
      Duration(seconds: delaySeconds <= 0 ? 0 : delaySeconds),
      () => unawaited(_renew()),
    );
  }

  Future<void> _renew() async {
    if (_closing || _reauthCompleter != null) return;
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
      final completer = Completer<void>();
      _reauthCompleter = completer;
      try {
        _sendJson({
          'op': 'reauth',
          'version': MdtbbsRelayFrame.version,
          'credential': next.credential,
        });
        await completer.future.timeout(
          authTimeout,
          onTimeout: () => throw const MdtbbsRelayException('中继 reauth_ok 超时'),
        );
      } finally {
        if (identical(_reauthCompleter, completer)) _reauthCompleter = null;
      }
      _scheduleRenewal();
    } on Object catch (error) {
      final expiresAt = _credentialExpiresAt;
      final secondsLeft = expiresAt == null
          ? 0
          : expiresAt.difference(DateTime.now()).inSeconds;
      if (secondsLeft < 8) {
        addLogAndPrint(
          .error,
          '续签失败且凭证即将到期（剩 $secondsLeft 秒）：$error',
          tag: 'Multiplayer',
        );
        _finish('中继凭证续签失败');
        return;
      }
      addLogAndPrint(
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
      addLogAndPrint(.warning, '中继信令发送失败：$error', tag: 'Multiplayer');
    }
  }

  void _emit(MdtbbsRelaySignal signal) {
    if (!_signals.isClosed) _signals.add(signal);
  }

  void _completePendingWaiters(String reason) {
    final error = MdtbbsRelayException(reason);
    final auth = _authCompleter;
    if (auth != null && !auth.isCompleted) auth.completeError(error);
    final reauth = _reauthCompleter;
    if (reauth != null && !reauth.isCompleted) reauth.completeError(error);
  }

  void _finish(String reason) {
    if (_closing) return;
    _closing = true;
    _renewTimer?.cancel();
    _completePendingWaiters(reason);
    addLogAndPrint(.warning, '中继连接结束：$reason', tag: 'Multiplayer');
    _emit(MdtbbsRelayClosed(reason: reason));
  }
}

class MdtbbsRelayFrameMaxTtl {
  MdtbbsRelayFrameMaxTtl._();
  static const int capabilitiesFallback = 120;
}