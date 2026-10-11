import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/util/io/log.dart';

/// 把远端 LanLink 房间桥成本机的局域网房间
///
/// 只做两件事，都是字节搬运，不碰游戏协议：
/// 1. 在 `127.0.0.1:<本地端口>` 起 TCP + UDP 转发，拨向房间节点地址；
///    节点那个端口就是原生 Mindustry 端口，所以转发过去等于直连房间
/// 2. 加入 Mindustry 的组播发现组，回一份「本机有房间」的数据报，
///    回包 socket 绑在 `127.0.0.1` 上，于是游戏把它显示成 `127.0.0.1:<本地端口>`
///
/// 第 2 步是这条路能顺起来的关键：Mindustry 没有 `-join` 之类的命令行参数，
/// 启动器无法直接把游戏拉进某个服务器，只能把房间喂进「局域网游戏」列表让玩家点
class LanLinkJoinSession {
  LanLinkJoinSession({
    required this.roomCode,
    required this.remoteHost,
    required this.remotePort,
    required this.roomName,
    this.preferredLocalPort = defaultLocalPort,
  });

  /// 与游戏默认端口一致，方便玩家在列表里一眼认出来
  static const int defaultLocalPort = 6567;

  /// 首选端口被占时往后试几个
  static const int portFallbackCount = 10;
  static const String multicastGroup = '227.2.7.7';
  static const int multicastPort = 20151;

  final String roomCode;
  final String remoteHost;
  final int remotePort;
  final String roomName;

  /// 期望的本地端口；被占用时会自动往后找，实际值看 [localPort]
  final int preferredLocalPort;

  /// 收尾时统一关掉，省得每个字段都写一遍
  final List<void Function()> _closers = [];
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<Socket> _openSockets = [];

  InternetAddress? _remoteAddress;
  InternetAddress? _gameUdpAddress;
  int _gameUdpPort = 0;
  int _localPort = 0;
  bool _running = false;

  bool get isRunning => _running;

  /// 实际绑上的本地端口
  int get localPort => _localPort == 0 ? preferredLocalPort : _localPort;

  /// 游戏侧应该连的地址
  String get localAddress => '127.0.0.1:$localPort';

  /// 起转发与局域网广播；失败时抛异常，调用方负责提示
  Future<void> start() async {
    if (_running) return;
    final addresses = await InternetAddress.lookup(remoteHost);
    if (addresses.isEmpty) {
      throw const SocketException('房间节点地址解析不出结果');
    }
    _remoteAddress = addresses.first;

    await _startTcpForward();
    await _startUdpForward();
    await _startLanBroadcast();
    _running = true;
    addLog(
      .info,
      '联机桥已启动：$localAddress → $remoteHost:$remotePort（房间 $roomCode）',
      tag: 'LanLink',
    );
  }

  Future<void> dispose() async {
    _running = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final socket in _openSockets) {
      try {
        socket.destroy();
      } on Object {
        // 已经断了就不用管
      }
    }
    _openSockets.clear();
    for (final close in _closers) {
      try {
        close();
      } on Object {
        // 同上
      }
    }
    _closers.clear();
    _gameUdpAddress = null;
    addLog(.info, '联机桥已关闭（房间 $roomCode）', tag: 'LanLink');
  }

  // -- TCP 转发 ----------------------------------------------------------

  Future<void> _startTcpForward() async {
    ServerSocket? server;
    Object? lastError;
    for (var offset = 0; offset <= portFallbackCount; offset++) {
      final candidate = preferredLocalPort + offset;
      if (candidate > 65535) break;
      try {
        server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          candidate,
          shared: false,
        );
        break;
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (server == null) {
      throw SocketException('本地端口 $preferredLocalPort 起不来：$lastError');
    }
    _localPort = server.port;
    _closers.add(server.close);
    _subscriptions.add(server.listen(_handleTcpClient, onError: (_) {}));
  }

  Future<void> _handleTcpClient(Socket client) async {
    Socket upstream;
    try {
      upstream = await Socket.connect(remoteHost, remotePort);
    } on Object catch (error) {
      addLog(.warning, '转发到 $remoteHost:$remotePort 失败：$error', tag: 'LanLink');
      client.destroy();
      return;
    }
    _openSockets
      ..add(client)
      ..add(upstream);
    client.setOption(SocketOption.tcpNoDelay, true);
    upstream.setOption(SocketOption.tcpNoDelay, true);

    void closeBoth() {
      _openSockets
        ..remove(client)
        ..remove(upstream);
      client.destroy();
      upstream.destroy();
    }

    _subscriptions.add(
      client.listen(
        upstream.add,
        onDone: closeBoth,
        onError: (_) => closeBoth(),
        cancelOnError: true,
      ),
    );
    _subscriptions.add(
      upstream.listen(
        client.add,
        onDone: closeBoth,
        onError: (_) => closeBoth(),
        cancelOnError: true,
      ),
    );
  }

  // -- UDP 转发 ----------------------------------------------------------

  /// 两条腿分工明确：
  /// - 本机 socket 绑 `127.0.0.1:<本地端口>`，只跟游戏说话
  /// - 上行 socket 绑 `anyIPv4:0`，只跟远端说话
  ///
  /// 不能合成一条：绑在 127.0.0.1 上的 socket 发往外网的包走回环口，出不去
  Future<void> _startUdpForward() async {
    final local = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      localPort,
      reuseAddress: true,
    );
    final upstream = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _closers
      ..add(local.close)
      ..add(upstream.close);

    final remote = _remoteAddress;
    _subscriptions.add(
      local.listen((event) {
        if (event != RawSocketEvent.read || remote == null) return;
        final datagram = local.receive();
        if (datagram == null) return;
        _gameUdpAddress = datagram.address;
        _gameUdpPort = datagram.port;
        upstream.send(datagram.data, remote, remotePort);
      }),
    );
    _subscriptions.add(
      upstream.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = upstream.receive();
        final gameAddress = _gameUdpAddress;
        if (datagram == null || gameAddress == null) return;
        local.send(datagram.data, gameAddress, _gameUdpPort);
      }),
    );
  }

  // -- 伪局域网广播 ------------------------------------------------------

  Future<void> _startLanBroadcast() async {
    RawDatagramSocket multicast;
    try {
      multicast = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        multicastPort,
        reuseAddress: true,
      );
    } on Object catch (error) {
      // 本机正在开房时会占住这个端口；转发照常，只是房间不会出现在列表里
      addLog(.warning, '绑定组播端口 $multicastPort 失败：$error', tag: 'LanLink');
      return;
    }
    try {
      multicast.joinMulticast(InternetAddress(multicastGroup));
    } on Object catch (error) {
      addLog(.warning, '加入组播组失败：$error', tag: 'LanLink');
      multicast.close();
      return;
    }

    // 关键：回包 socket 绑在 127.0.0.1，游戏看到的房间地址才会是 127.0.0.1
    final reply = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _closers
      ..add(multicast.close)
      ..add(reply.close);

    final payload = _buildServerData();
    _subscriptions.add(
      multicast.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = multicast.receive();
        if (datagram == null) return;
        // 只回本机自己的探测：广告的是 127.0.0.1，回给别人只会在人家列表里塞个连不上的房间
        if (!datagram.address.isLoopback) return;
        reply.send(payload, InternetAddress.loopbackIPv4, datagram.port);
      }),
    );
  }

  /// `NetworkIO.writeServerData` 的等价实现；版本填 -1 跳过客户端版本门禁
  Uint8List _buildServerData() {
    final builder = BytesBuilder();
    _writeString(builder, roomName, 100);
    _writeString(builder, 'LanLink', 64);
    _writeInt32(builder, 1); // 当前人数
    _writeInt32(builder, 0); // 波次
    _writeInt32(builder, -1); // 版本：-1 让客户端跳过门禁
    _writeString(builder, '', 32); // 版本类型
    builder.addByte(0); // 玩法：0 = 生存
    _writeInt32(builder, 8); // 人数上限
    _writeString(builder, 'LanLink 房间 $roomCode', 100);
    _writeString(builder, '', 50); // 模式名
    _writeInt16(builder, localPort); // v152 起客户端从这里取端口
    return builder.toBytes();
  }

  void _writeString(BytesBuilder builder, String text, int maxLength) {
    final bytes = utf8.encode(text);
    final length = bytes.length > maxLength ? maxLength : bytes.length;
    builder.addByte(length);
    builder.add(bytes.sublist(0, length));
  }

  void _writeInt32(BytesBuilder builder, int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.big);
    builder.add(data.buffer.asUint8List());
  }

  void _writeInt16(BytesBuilder builder, int value) {
    final data = ByteData(2)..setInt16(0, value, Endian.big);
    builder.add(data.buffer.asUint8List());
  }
}
