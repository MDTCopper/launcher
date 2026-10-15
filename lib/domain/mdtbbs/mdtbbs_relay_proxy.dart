import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/domain/mdtbbs/mdtbbs_relay_tunnel.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 官方中继的本机代理：把游戏流量在 `127.0.0.1` 与中继隧道之间搬运
///
/// **两条腿**同样适用：TCP 服务端与 UDP 套接字绑**同一个**本机端口
/// （游戏按源地址路由，混用会串包）；UDP 回程发给游戏最后使用的来源地址
class MdtbbsRelayProxyPorts {
  MdtbbsRelayProxyPorts._(this.tcpServer, this.udpSocket, this.port);

  final ServerSocket tcpServer;
  final RawDatagramSocket udpSocket;

  /// 实际绑定的本机端口（首选被占时顺延）
  final int port;
}

/// 绑定本机代理端口：首选 [preferred] 被占则顺延尝试 [fallbackCount] 次
Future<MdtbbsRelayProxyPorts?> bindRelayProxyPorts({
  int preferred = 6567,
  int fallbackCount = 10,
}) async {
  for (var offset = 0; offset <= fallbackCount; offset++) {
    final candidate = preferred + offset;
    if (candidate > 65535) break;
    try {
      final tcp = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        candidate,
      );
      final udp = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        candidate,
      );
      return MdtbbsRelayProxyPorts._(tcp, udp, tcp.port);
    } on Object {
      continue;
    }
  }
  return null;
}

/// **房客侧**：本机 `127.0.0.1:<port>` 上的 TCP+UDP 代理，
/// 把游戏流量经中继送到房主（房主侧桥到它自己的游戏端口）
///
/// 协议口径（与参考实现一致）：
/// - 游戏连上本地 TCP → 发 `tcp_open{target_peer_id=房主}`；**同一时刻只允许一条待确认**，
///   服务端回 `tcp_open_pending{stream_id}` 绑定、`tcp_opened` 之后才能写数据
/// - UDP 无需握手：游戏的数据报直接封 MLR1 UDP 帧、目标填房主 peerId
class MdtbbsRelayGuestProxy {
  MdtbbsRelayGuestProxy({
    required this.tunnel,
    required this.ownerPeerId,
    required this.ports,
  });

  final MdtbbsRelayTunnel tunnel;
  final String ownerPeerId;
  final MdtbbsRelayProxyPorts ports;

  final _streams = <int, Socket>{};
  StreamSubscription<MdtbbsRelaySignal>? _subscription;
  InternetAddress? _gameAddress;
  int? _gamePort;
  bool _disposed = false;

  /// 实际监听的本机地址
  String get localAddress => '127.0.0.1:${ports.port}';

  Future<void> start() async {
    _subscription = tunnel.signals.listen(_onSignal);
    ports.tcpServer.listen(_onGameTcpConnected, onError: (_) {});
    ports.udpSocket.listen(_onUdpEvent);
    addLogAndPrint(
      .info,
      '房客代理已就绪：$localAddress → 房主 $ownerPeerId',
      tag: 'Multiplayer',
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    for (final socket in _streams.values) {
      socket.destroy();
    }
    _streams.clear();
    ports.tcpServer.close();
    ports.udpSocket.close();
    addLogAndPrint(.info, '房客代理已关闭', tag: 'Multiplayer');
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = ports.udpSocket.receive();
    if (datagram == null || datagram.data.isEmpty) return;
    _gameAddress = datagram.address;
    _gamePort = datagram.port;
    tunnel.sendUdpDatagram(ownerPeerId, datagram.data);
  }

  void _onGameTcpConnected(Socket socket) {
    if (_disposed) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    unawaited(
      tunnel
          .openTcpStream(ownerPeerId)
          .then((streamId) {
            if (_disposed) {
              socket.destroy();
              return;
            }
            _streams[streamId] = socket;
            addLogAndPrint(.info, '中继分配 stream $streamId', tag: 'Multiplayer');
            socket.listen(
              (Uint8List data) => tunnel.sendTcpData(streamId, data),
              onDone: () => _dropStream(streamId),
              onError: (_) => _dropStream(streamId),
              cancelOnError: true,
            );
          })
          .catchError((Object error) {
            addLogAndPrint(.warning, '申请中继通道失败：$error', tag: 'Multiplayer');
            socket.destroy();
          }),
    );
  }

  void _onSignal(MdtbbsRelaySignal signal) {
    if (_disposed) return;
    switch (signal) {
      case MdtbbsRelayTcpData(:final streamId, :final payload):
        _streams[streamId]?.add(payload);
      case MdtbbsRelayTcpClosed(:final streamId):
        _dropStream(streamId);
      case MdtbbsRelayTcpOpenFailed(:final streamId):
        _dropStream(streamId);
      case MdtbbsRelayUdpDatagram(:final payload):
        final address = _gameAddress;
        final port = _gamePort;
        if (address == null || port == null) return;
        ports.udpSocket.send(payload, address, port);
      default:
        break;
    }
  }

  void _dropStream(int streamId) {
    final socket = _streams.remove(streamId);
    if (socket == null) return;
    socket.destroy();
    tunnel.closeTcpStream(streamId);
  }
}

/// **房主侧**：把中继上对端发来的流量桥到本机游戏端口
///
/// ⚠ **对端接入的信令尚未经实测**（参考实现只覆盖房客侧）：目前按与房客对称的
/// 方式处理中继分派的流，实际信令名联调时以隧道日志校准
///
/// **不绑本机端口**：6567 是游戏自己监听的；这里只有出站 TCP 连接与
/// 按对端分（临时端口）的 UDP 套接字
class MdtbbsRelayHostBridge {
  MdtbbsRelayHostBridge({required this.tunnel, this.gamePort = 6567});

  final MdtbbsRelayTunnel tunnel;

  /// 本机游戏监听端口
  final int gamePort;

  final _bridges = <int, Socket>{};
  final _pendingTcpBridges = <int, Future<void>>{};
  final _bufferedTcp = <int, List<Uint8List>>{};
  final _closedTcpStreams = <int>{};

  final _udpBridges = <String, RawDatagramSocket>{};
  final _pendingUdpBridges = <String, Future<void>>{};

  /// 绑定是异步的，先到的数据报按对端缓冲，套接字就绪后补发
  final _bufferedUdp = <String, List<Uint8List>>{};

  StreamSubscription<MdtbbsRelaySignal>? _subscription;
  bool _disposed = false;

  Future<void> start() async {
    _subscription = tunnel.signals.listen(_onSignal);
    addLogAndPrint(
      .info,
      '房主桥已就绪：中继 → 127.0.0.1:$gamePort',
      tag: 'Multiplayer',
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    for (final socket in _bridges.values) {
      socket.destroy();
    }
    _bridges.clear();
    _pendingTcpBridges.clear();
    _bufferedTcp.clear();
    _closedTcpStreams.clear();
    for (final socket in _udpBridges.values) {
      socket.close();
    }
    _udpBridges.clear();
    _pendingUdpBridges.clear();
    _bufferedUdp.clear();
    addLogAndPrint(.info, '房主桥已关闭', tag: 'Multiplayer');
  }

  void _onSignal(MdtbbsRelaySignal signal) {
    if (_disposed) return;
    switch (signal) {
      case MdtbbsRelayTcpData(:final streamId, :final payload):
        _bridgeFor(streamId, payload);
      case MdtbbsRelayTcpClosed(:final streamId):
        _dropBridge(streamId);
      case MdtbbsRelayTcpOpenFailed(:final streamId):
        _dropBridge(streamId);
      case MdtbbsRelayUdpDatagram(:final targetPeerId, :final payload):
        unawaited(_forwardUdpToGame(targetPeerId, payload));
      default:
        break;
    }
  }

  /// 每条流只建立一条到本机游戏的 TCP 连接；连接建立期间的帧先缓存。
  void _bridgeFor(int streamId, Uint8List payload) {
    if (_closedTcpStreams.contains(streamId)) return;

    final existing = _bridges[streamId];
    if (existing != null) {
      existing.add(payload);
      return;
    }

    _bufferedTcp.putIfAbsent(streamId, () => <Uint8List>[]).add(payload);
    if (_pendingTcpBridges.containsKey(streamId)) return;

    late final Future<void> task;
    task = _bindTcpBridge(streamId).whenComplete(() {
      if (identical(_pendingTcpBridges[streamId], task)) {
        _pendingTcpBridges.remove(streamId);
      }
    });
    _pendingTcpBridges[streamId] = task;
    unawaited(task);
  }

  Future<void> _bindTcpBridge(int streamId) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        gamePort,
      );
      if (_disposed || _closedTcpStreams.contains(streamId)) {
        socket.destroy();
        return;
      }

      socket.setOption(SocketOption.tcpNoDelay, true);
      _bridges[streamId] = socket;
      socket.listen(
        (Uint8List data) => tunnel.sendTcpData(streamId, data),
        onDone: () => _dropBridge(streamId),
        onError: (_) => _dropBridge(streamId),
        cancelOnError: true,
      );

      final buffered = _bufferedTcp.remove(streamId);
      if (buffered != null) {
        for (final payload in buffered) {
          socket.add(payload);
        }
      }

      addLogAndPrint(
        .info,
        '房主侧已为 stream $streamId 接上本机游戏',
        tag: 'Multiplayer',
      );
    } on Object catch (error) {
      _bufferedTcp.remove(streamId);
      if (!_disposed && !_closedTcpStreams.contains(streamId)) {
        addLogAndPrint(.warning, '连本机游戏失败：$error', tag: 'Multiplayer');
        _dropBridge(streamId);
      }
    }
  }

  void _dropBridge(int streamId) {
    final firstClose = _closedTcpStreams.add(streamId);
    _bufferedTcp.remove(streamId);
    _bridges.remove(streamId)?.destroy();
    if (firstClose) {
      tunnel.closeTcpStream(streamId);
    }
  }

  /// UDP 按对端分套接字：游戏按源地址路由，混用会串包；
  /// 绑定是异步的，先到的数据报按对端缓冲，套接字就绪后补发
  Future<void> _forwardUdpToGame(String peerId, Uint8List payload) async {
    final ready = _udpBridges[peerId];
    if (ready != null) {
      ready.send(payload, InternetAddress.loopbackIPv4, gamePort);
      return;
    }
    _bufferedUdp.putIfAbsent(peerId, () => []).add(payload);
    final pending = _pendingUdpBridges[peerId];
    if (pending != null) {
      await pending;
      _flushUdpBuffer(peerId);
      return;
    }
    final task = _bindUdpBridge(peerId);
    _pendingUdpBridges[peerId] = task;
    await task;
    _flushUdpBuffer(peerId);
  }

  Future<void> _bindUdpBridge(String peerId) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      _udpBridges[peerId] = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null || datagram.data.isEmpty) return;
        tunnel.sendUdpDatagram(peerId, datagram.data);
      });
    } on Object catch (error) {
      addLogAndPrint(.warning, '对端 UDP 桥建立失败：$error', tag: 'Multiplayer');
      _bufferedUdp.remove(peerId);
    }
  }

  void _flushUdpBuffer(String peerId) {
    final socket = _udpBridges[peerId];
    final buffered = _bufferedUdp.remove(peerId);
    if (socket == null || buffered == null) return;
    for (final payload in buffered) {
      socket.send(payload, InternetAddress.loopbackIPv4, gamePort);
    }
  }
}
