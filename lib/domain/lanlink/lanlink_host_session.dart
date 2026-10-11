import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/data/net/lanlink/lanlink_models.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 房主侧的端点隧道
///
/// 协议见社区模组仓库的 `proto/PROTOCOL.md` §3：端点有两类监听，
/// **房间公网端口**（面向客人，原生 Mindustry 协议）与**隧道端口**（面向房主）。
/// 这里负责后者：
///
/// - 控制链：一条 TCP，握手后走换行分隔的 JSON，端点用它通知「有客人接入」
/// - 数据链：每个客人一条 TCP，握手后就是裸字节流，与 `127.0.0.1:<游戏端口>` 对接
/// - UDP：一条隧道 socket 收发包，**每个客人会话再各占一个本地 socket**
///   —— ArcNet 按源地址路由，混用一个 socket 会串包
class LanLinkHostSession {
  LanLinkHostSession({required this.room, required this.gamePort});

  /// 隧道握手魔术字：TCP 用 `LLK1`，UDP 用 `LLKU`
  static const String tcpMagic = 'LLK1';
  static const String udpMagic = 'LLKU';
  static const int _tcpTypeControl = 0x01;
  static const int _tcpTypeData = 0x02;
  static const int _udpTypeData = 0x01;
  static const int _udpTypeClose = 0x02;
  static const int _udpTypeRegister = 0x03;

  /// 与上游一致：15 秒一次保活（家用 NAT 的 UDP 映射常见 30 秒超时）
  static const Duration _keepAliveInterval = Duration(seconds: 15);

  /// 空闲会话回收：端点侧 2 分钟过期且可能不发关闭帧，这边自己收干净
  static const Duration _sessionIdleLimit = Duration(seconds: 150);
  static const int _maxUdpSessions = 64;

  final LanLinkHostRoom room;
  final int gamePort;

  Socket? _control;
  RawDatagramSocket? _udpTunnel;
  StreamSubscription<Object?>? _controlSubscription;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  Timer? _keepAliveTimer;
  bool _running = false;

  /// 解析一次存下来；节点地址可能是域名，每包都 tryParse 会静默丢包
  InternetAddress? _nodeAddress;

  final Map<int, _DataBridge> _bridges = {};
  final Map<int, _UdpSession> _udpSessions = {};
  final StringBuffer _controlBuffer = StringBuffer();

  bool get isRunning => _running;
  int get guestTcpCount => _bridges.length;
  int get guestUdpSessions => _udpSessions.length;

  Future<void> start() async {
    if (_running) return;
    if (!room.canOpenTunnel) {
      throw StateError('房间信息不完整，开不了隧道');
    }
    final token = _hexToBytes(room.roomTokenHex);

    // 控制链
    final control = await Socket.connect(room.nodeAddr, room.tunnelPort);
    control.setOption(SocketOption.tcpNoDelay, true);
    control.add(_handshake(token, _tcpTypeControl, 0));
    await control.flush();
    _control = control;
    _controlSubscription = control.listen(
      _onControlData,
      onDone: _onControlDone,
      onError: (_) => _onControlDone(),
      cancelOnError: true,
    );

    // UDP 隧道
    final tunnel = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _udpTunnel = tunnel;
    _nodeAddress =
        InternetAddress.tryParse(room.nodeAddr) ??
        (await InternetAddress.lookup(room.nodeAddr)).first;
    final nodeAddress = _nodeAddress!;
    _udpSubscription = tunnel.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = tunnel.receive();
      if (datagram != null) _onUdpFrame(datagram.data);
    });

    final registerFrame = Uint8List.fromList([
      ...utf8.encode(udpMagic),
      _udpTypeRegister,
      ...token,
    ]);
    void keepAlive() {
      try {
        tunnel.send(registerFrame, nodeAddress, room.tunnelPort);
      } on Object catch (error) {
        addLog(.warning, 'UDP 保活失败：$error', tag: 'LanLink');
      }
      _sweepIdleSessions();
    }

    keepAlive();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) => keepAlive());

    _running = true;
    addLog(
      .info,
      '开房隧道已就绪：房间 ${room.code}，公网地址 ${room.publicAddress}',
      tag: 'LanLink',
    );
  }

  Future<void> dispose() async {
    _running = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await _controlSubscription?.cancel();
    await _udpSubscription?.cancel();
    for (final bridge in _bridges.values) {
      bridge.close();
    }
    _bridges.clear();
    for (final session in _udpSessions.values) {
      session.close();
    }
    _udpSessions.clear();
    _control?.destroy();
    _control = null;
    _udpTunnel?.close();
    _udpTunnel = null;
    addLog(.info, '开房隧道已关闭（房间 ${room.code}）', tag: 'LanLink');
  }

  // -- 控制链 ------------------------------------------------------------

  /// 换行分隔的 JSON 可能跨 chunk，所以要自己攒行
  void _onControlData(Uint8List chunk) {
    _controlBuffer.write(utf8.decode(chunk, allowMalformed: true));
    var text = _controlBuffer.toString();
    var index = text.indexOf('\n');
    while (index >= 0) {
      final line = text.substring(0, index).trim();
      text = text.substring(index + 1);
      if (line.isNotEmpty) _onControlLine(line);
      index = text.indexOf('\n');
    }
    _controlBuffer
      ..clear()
      ..write(text);
  }

  void _onControlLine(String line) {
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(line) as Map).cast<String, dynamic>();
    } on Object {
      return;
    }
    switch ('${json['op'] ?? ''}') {
      case 'new_conn':
        final id = (json['id'] as num?)?.toInt() ?? -1;
        if (id >= 0) unawaited(_openDataChain(id));
      case 'conn_closed':
        final id = (json['id'] as num?)?.toInt() ?? -1;
        _bridges.remove(id)?.close();
      case 'ping':
        _sendControl({'op': 'pong'});
      default:
        break;
    }
  }

  void _onControlDone() {
    if (!_running) return;
    addLog(.warning, '房主隧道控制链断开', tag: 'LanLink');
    _running = false;
  }

  void _sendControl(Map<String, Object?> payload) {
    final control = _control;
    if (control == null) return;
    try {
      control
        ..add(utf8.encode('${jsonEncode(payload)}\n'))
        ..flush();
    } on Object catch (error) {
      addLog(.warning, '控制链发送失败：$error', tag: 'LanLink');
    }
  }

  // -- 数据链 ------------------------------------------------------------

  Future<void> _openDataChain(int id) async {
    // 自动放行（审批开关属上游的后续里程碑）
    _sendControl({'op': 'accept_conn', 'id': id});
    try {
      final data = await Socket.connect(room.nodeAddr, room.tunnelPort);
      data.setOption(SocketOption.tcpNoDelay, true);
      data.add(_handshake(_hexToBytes(room.roomTokenHex), _tcpTypeData, id));
      await data.flush();

      final game = await Socket.connect(InternetAddress.loopbackIPv4, gamePort);
      game.setOption(SocketOption.tcpNoDelay, true);

      final bridge = _DataBridge(id, data, game);
      bridge.onClosed = () {
        _bridges.remove(id);
      };
      _bridges[id] = bridge;
      bridge.start();
    } on Object catch (error) {
      addLog(.warning, '为客人 $id 建数据链失败：$error', tag: 'LanLink');
    }
  }

  // -- UDP ---------------------------------------------------------------

  void _onUdpFrame(Uint8List data) {
    if (data.length < 5) return;
    if (String.fromCharCodes(data.sublist(0, 4)) != udpMagic) return;
    final type = data[4];
    if (type == _udpTypeData) {
      if (data.length < 7) return;
      final sessionId = (data[5] << 8) | data[6];
      var session = _udpSessions[sessionId];
      if (session == null) {
        if (_udpSessions.length >= _maxUdpSessions) return;
        session = _UdpSession(
          sessionId,
          room,
          gamePort,
          _udpTunnel!,
          _nodeSink,
        );
        _udpSessions[sessionId] = session;
      }
      session.sendToGame(data.sublist(7));
    } else if (type == _udpTypeClose) {
      if (data.length < 7) return;
      final sessionId = (data[5] << 8) | data[6];
      _udpSessions.remove(sessionId)?.close();
    }
  }

  void _nodeSink(Uint8List frame) {
    final tunnel = _udpTunnel;
    final address = _nodeAddress;
    if (tunnel == null || address == null) return;
    try {
      tunnel.send(frame, address, room.tunnelPort);
    } on Object catch (error) {
      addLog(.warning, 'UDP 回程发送失败：$error', tag: 'LanLink');
    }
  }

  void _sweepIdleSessions() {
    final now = DateTime.now();
    final expired = _udpSessions.entries
        .where(
          (entry) =>
              now.difference(entry.value.lastActivity) > _sessionIdleLimit,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in expired) {
      _udpSessions.remove(id)?.close();
    }
  }

  // -- 工具 --------------------------------------------------------------

  /// 25 字节握手：`[4B magic][1B type][16B roomToken][4B connId 大端]`
  Uint8List _handshake(Uint8List token, int type, int connId) {
    final buffer = Uint8List(25);
    buffer.setRange(0, 4, utf8.encode(tcpMagic));
    buffer[4] = type;
    final copyLength = token.length > 16 ? 16 : token.length;
    if (copyLength > 0) buffer.setRange(5, 5 + copyLength, token);
    final idBytes = ByteData(4)..setUint32(0, connId, Endian.big);
    buffer.setRange(21, 25, idBytes.buffer.asUint8List());
    return buffer;
  }

  Uint8List _hexToBytes(String hex) {
    final text = hex.trim();
    if (text.length.isOdd) return Uint8List(0);
    final out = Uint8List(text.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(text.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return Uint8List(0);
      out[i] = byte;
    }
    return out;
  }
}

/// 一个客人的 TCP 数据链：把端点侧与本地游戏对接
class _DataBridge {
  _DataBridge(this.id, this.upstream, this.game);

  final int id;
  final Socket upstream;
  final Socket game;
  final List<StreamSubscription<Uint8List>> _subscriptions = [];

  void Function()? onClosed;
  bool _closed = false;

  void start() {
    _subscriptions
      ..add(
        upstream.listen(
          game.add,
          onDone: close,
          onError: (_) => close(),
          cancelOnError: true,
        ),
      )
      ..add(
        game.listen(
          upstream.add,
          onDone: close,
          onError: (_) => close(),
          cancelOnError: true,
        ),
      );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    upstream.destroy();
    game.destroy();
    onClosed?.call();
  }
}

/// 一个客人的 UDP 会话：独立本地 socket 与游戏通信
class _UdpSession {
  _UdpSession(this.id, this.room, this.gamePort, this.tunnel, this.nodeSink) {
    unawaited(_bind());
  }

  final int id;
  final LanLinkHostRoom room;
  final int gamePort;
  final RawDatagramSocket tunnel;
  final void Function(Uint8List frame) nodeSink;

  RawDatagramSocket? _local;
  StreamSubscription<RawSocketEvent>? _subscription;
  DateTime lastActivity = DateTime.now();

  Future<void> _bind() async {
    try {
      final local = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      _local = local;
      _subscription = local.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = local.receive();
        if (datagram == null) return;
        lastActivity = DateTime.now();
        // 回程：本地游戏 → 封帧 → 端点
        final frame = Uint8List(7 + datagram.data.length);
        frame.setRange(0, 4, utf8.encode(LanLinkHostSession.udpMagic));
        frame[4] = 0x01;
        frame[5] = (id >> 8) & 0xFF;
        frame[6] = id & 0xFF;
        frame.setRange(7, frame.length, datagram.data);
        nodeSink(frame);
      });
    } on Object catch (error) {
      addLog(.warning, 'UDP 会话 $id 起不来：$error', tag: 'LanLink');
    }
  }

  void sendToGame(Uint8List payload) {
    final local = _local;
    if (local == null) return;
    lastActivity = DateTime.now();
    local.send(payload, InternetAddress.loopbackIPv4, gamePort);
  }

  void close() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _local?.close();
    _local = null;
  }
}
