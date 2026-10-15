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

  /// 凭证到期时间（续签按它排，比 ttl 倒数准）
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

/// 房主侧：本机游戏连接的结果（服务端回给房主）
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

  /// 认证被拒（AUTH_INVALID）：分配凭证后代理节点要异步同步几秒，
  /// 立即连会撞上；这类失败等几秒重试即可
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
/// 则由控制面复用原 allocation / connection_id 签发续签凭证。
/// 因此首次 auth 的 `AUTH_INVALID` 重试只复用原凭证，不重新占一条 allocation。
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
  Completer<MdtbbsRelayAuthOk>? _authCompleter;

  /// tcp_open_pending 没有请求 ID，多个 open 并发时无法把响应归属到调用方。
  /// 所以握手必须串行，等一条 opened / failed 收口后再发下一条。
  Future<void> _tcpOpenTail = Future<void>.value();

  /// 信令与数据都从这里出（广播流，允许多个订阅者各取所需）
  Stream<MdtbbsRelaySignal> get signals => _signals.stream;

  /// 当前凭证到期时间；续签后更新
  DateTime? _credentialExpiresAt;
  DateTime? get credentialExpiresAt => _credentialExpiresAt;

  /// 建连并认证
  ///
  /// 认证被拒（`AUTH_INVALID`）只用**同一份凭证**退避重试，
  /// 避免尚未 connected 时重复申请撞上 allocation 限制。
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
      if (identical(_authCompleter, completer)) {
        _authCompleter = null;
      }
    }
  }

  Future<void> _connect() async {
    final endpoint = _allocation!.endpoint;
    addLogAndPrint(.info, '连接官方中继：$endpoint', tag: 'Multiplayer');
    // 中继端口可能整个不可达：不设超时会永远挂住，把上层卡死
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

  /// 申请一条到目标对端的 TCP 流。
  ///
  /// 中继的 `tcp_open_pending` 没有客户端请求 ID，所以 open 握手串行执行；
  /// `tcp_opened` 到达后才把 streamId 交给上层，避免在流尚未就绪时发送游戏数据。
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
    await _teardownSocket();
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
        if (completer != null && !completer.isCompleted) {
          completer.complete(signal);
        }
        _emit(signal);
      case 'reauth_ok':
        addLogAndPrint(.info, '中继凭证已续签', tag: 'Multiplayer');
      case 'tcp_open_pending':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        addLogAndPrint(.info, '中继分配 stream $streamId', tag: 'Multiplayer');
        _emit(MdtbbsRelayTcpOpenPending(streamId: streamId));
      case 'tcp_opened':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        addLogAndPrint(.info, 'stream $streamId 已就绪', tag: 'Multiplayer');
        _emit(MdtbbsRelayTcpOpened(streamId: streamId));
      case 'tcp_open_failed':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        addLogAndPrint(.warning, 'stream $streamId 打开失败', tag: 'Multiplayer');
        _emit(MdtbbsRelayTcpOpenFailed(streamId: streamId));
      case 'tcp_open_result':
        final streamId = (json['stream_id'] as num?)?.toInt() ?? 0;
        final ok = json['ok'] == true || json['success'] == true;
        addLogAndPrint(
          .info,
          'stream $streamId 本机连接结果：$ok',
          tag: 'Multiplayer',
        );
        _emit(MdtbbsRelayTcpOpenResult(streamId: streamId, ok: ok));
      case 'error':
        final code = '${json['code'] ?? ''}';
        addLogAndPrint(.warning, '中继报错：code=$code', tag: 'Multiplayer');
        if (code == 'AUTH_INVALID') {
          // 诊断行：不含凭证本体，管理员可凭这些 id 去中继侧查
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
        final completer = _authCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            MdtbbsRelayException(
              code.isEmpty ? '中继认证失败' : '中继认证被拒（$code）',
              authRejected: code == 'AUTH_INVALID',
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

  /// 到期前 [renewBefore] 秒续签；auth_ok 带的 `expires_at` 比 ttl 倒数准
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
    final secondsLeft = _credentialExpiresAt!
        .difference(DateTime.now())
        .inSeconds;
    final delaySeconds = secondsLeft - renewBefore;
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

  void _finish(String reason) {
    if (_closing) return;
    _closing = true;
    _renewTimer?.cancel();
    final completer = _authCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(MdtbbsRelayException(reason));
    }
    addLogAndPrint(.warning, '中继连接结束：$reason', tag: 'Multiplayer');
    _emit(MdtbbsRelayClosed(reason: reason));
  }
}

/// 续签间隔的兜底值（服务端没给 ttl 时按 120 秒）
class MdtbbsRelayFrameMaxTtl {
  MdtbbsRelayFrameMaxTtl._();

  static const int capabilitiesFallback = 120;
}