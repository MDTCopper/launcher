import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// STUN 查询到的公网端点
class StunEndpoint {
  const StunEndpoint(this.address, this.port, this.server);

  final String address;
  final int port;
  final String server;

  String get text => '$address:$port';
}

class StunDiscovery {
  StunDiscovery(this.endpoints);

  final List<StunEndpoint> endpoints;

  bool get ok => endpoints.isNotEmpty;

  /// 不同 STUN 服务器看到不同端口 ⇒ 大概率是对称 NAT（打洞成功率低）
  bool get symmetric {
    if (endpoints.length < 2) return false;
    return endpoints.map((endpoint) => endpoint.port).toSet().length > 1;
  }

  /// 不同 STUN 看到不同公网 IP ⇒ 多出口 / 负载均衡，打洞更难
  bool get multipleAddresses {
    if (endpoints.length < 2) return false;
    return endpoints.map((endpoint) => endpoint.address).toSet().length > 1;
  }

  /// 只有一个结果时判断不了 NAT 类型
  bool get undetermined => endpoints.length < 2;
}

class P2pPunchResult {
  const P2pPunchResult({
    required this.ok,
    required this.message,
    this.peer,
    this.rtt,
  });

  final bool ok;
  final String message;
  final String? peer;
  final Duration? rtt;
}

class _Datagram {
  const _Datagram(this.data, this.address, this.port);
  final Uint8List data;
  final InternetAddress address;
  final int port;
}

/// 只做两件事：
/// 1. 用 STUN 查出本机 UDP 的公网端点（多个服务器对比，顺便判断是不是对称 NAT）
/// 2. 对指定端点发探测包，做 UDP 打洞 + 双向 RTT 验证
///
/// **不碰游戏、不碰联机代码**，只用于判断两台机器之间能不能 P2P
class P2pProbe {
  static const defaultServers = [
    'stun.miwifi.com:3478',
    'stun.l.google.com:19302',
    'stun.cloudflare.com:3478',
  ];

  RawDatagramSocket? _socket;
  final _incoming = StreamController<_Datagram>.broadcast();
  final _random = Random.secure();

  Future<void> _ensureSocket() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || datagram.data.isEmpty) return;
      _incoming.add(
        _Datagram(
          Uint8List.fromList(datagram.data),
          datagram.address,
          datagram.port,
        ),
      );
    });
  }

  /// 先绑定 UDP socket 并返回本地端口（用例里用来互打；STUN 也会复用这个 socket）
  Future<int> bind() async {
    await _ensureSocket();
    return _socket!.port;
  }

  Future<StunDiscovery> discover({
    List<String> servers = defaultServers,
    Duration timeout = const Duration(seconds: 3),
  }) async {    await _ensureSocket();
    final found = <StunEndpoint>[];
    for (final server in servers) {
      try {
        final endpoint = await _query(server, timeout);
        if (endpoint != null) found.add(endpoint);
      } on Object {
        // 某个 STUN 不通不影响其它
      }
    }
    return StunDiscovery(found);
  }

  Future<StunEndpoint?> _query(String server, Duration timeout) async {
    final parts = server.split(':');
    final host = parts.first;
    final port = parts.length > 1 ? int.parse(parts[1]) : 3478;
    final addresses = await InternetAddress.lookup(host);
    final ipv4 = addresses
        .where(
          (address) =>
              address.type == InternetAddressType.IPv4 &&
              !address.isLoopback &&
              address.address != '0.0.0.0',
        )
        .toList();
    if (ipv4.isEmpty) return null;

    final transaction = List<int>.generate(12, (_) => _random.nextInt(256));
    final request = _bindingRequest(transaction);
    final completer = Completer<StunEndpoint?>();
    final subscription = _incoming.stream.listen((datagram) {
      final mapped = _parseBindingResponse(datagram.data, transaction);
      if (mapped != null && !completer.isCompleted) {
        completer.complete(StunEndpoint(mapped.$1, mapped.$2, server));
      }
    });
    _socket!.send(request, ipv4.first, port);
    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
    await subscription.cancel();
    return result;
  }

  /// 同一个 UDP socket 上打洞（换 socket 会换 NAT 映射，STUN 结果就失效了）
  Future<P2pPunchResult> punch({
    required String peerHost,
    required int peerPort,
    String token = 'copper-p2p',
    Duration timeout = const Duration(seconds: 20),
    void Function(String line)? log,
  }) async {
    await _ensureSocket();
    final addresses = await InternetAddress.lookup(peerHost);
    final ipv4 = addresses
        .where((address) => address.type == InternetAddressType.IPv4)
        .toList();
    if (ipv4.isEmpty) {
      return const P2pPunchResult(ok: false, message: '对方地址解析不出 IPv4');
    }
    final peer = ipv4.first;
    final tokenBytes = utf8.encode(token);
    final sentAt = <int, DateTime>{};
    final completer = Completer<P2pPunchResult>();
    String? observedPeer;
    var gotInbound = false;

    final subscription = _incoming.stream.listen((datagram) {
      final packet = _parseProbe(datagram.data, tokenBytes);
      if (packet == null) return;
      observedPeer ??= '${datagram.address.address}:${datagram.port}';
      final (kind, nonce) = packet;
      if (kind == 'P') {
        gotInbound = true;
        _socket!.send(
          _probePacket(tokenBytes, 'A', nonce),
          datagram.address,
          datagram.port,
        );
        log?.call('收到对方探测（来自 $observedPeer），已回 ack');
      } else if (kind == 'A') {
        final at = sentAt[nonce];
        if (at != null && !completer.isCompleted) {
          completer.complete(
            P2pPunchResult(
              ok: true,
              message: '双向打通',
              peer: observedPeer,
              rtt: DateTime.now().difference(at),
            ),
          );
        }
      }
    });

    void sendPing() {
      if (completer.isCompleted) return;
      final nonce = _random.nextInt(1 << 32);
      sentAt[nonce] = DateTime.now();
      _socket!.send(_probePacket(tokenBytes, 'P', nonce), peer, peerPort);
    }

    log?.call('开始向 ${peer.address}:$peerPort 打洞（每 300ms 一次）');
    sendPing();
    final timer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => sendPing(),
    );

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => P2pPunchResult(
        ok: false,
        message: gotInbound
            ? '收到对方探测，但回程没确认（可能是不对称 NAT）'
            : '超时：一个探测都没收到',
        peer: observedPeer,
      ),
    );
    timer.cancel();
    await subscription.cancel();
    return result;
  }

  Future<void> close() async {
    _socket?.close();
    _socket = null;
    await _incoming.close();
  }

  Uint8List _bindingRequest(List<int> transaction) {
    final data = ByteData(20);
    data.setUint16(0, 0x0001);
    data.setUint16(2, 0);
    data.setUint32(4, 0x2112A442);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(8, 20, transaction);
    return bytes;
  }

  (String, int)? _parseBindingResponse(Uint8List data, List<int> transaction) {
    if (data.length < 20) return null;
    final header = ByteData.sublistView(data);
    if (header.getUint16(0) != 0x0101) return null;
    if (header.getUint32(4) != 0x2112A442) return null;
    for (var index = 0; index < 12; index++) {
      if (data[8 + index] != transaction[index]) return null;
    }

    final length = header.getUint16(2);
    var offset = 20;
    final end = 20 + length;
    while (offset + 4 <= end && offset + 4 <= data.length) {
      final type = header.getUint16(offset);
      final size = header.getUint16(offset + 2);
      final value = offset + 4;
      if (value + size > data.length) break;
      if (type == 0x0020 || type == 0x0001) {
        if (size >= 8 && data[value + 1] == 0x01) {
          final port = header.getUint16(value + 2);
          final ip = data.sublist(value + 4, value + 8);
          if (type == 0x0020) {
            final cookie = ByteData(4)..setUint32(0, 0x2112A442);
            final mask = cookie.buffer.asUint8List();
            for (var i = 0; i < 4; i++) {
              ip[i] = ip[i] ^ mask[i];
            }
            return (
              '${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}',
              port ^ (0x2112A442 >> 16),
            );
          }
          return ('${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}', port);
        }
      }
      offset = value + ((size + 3) & ~3);
    }
    return null;
  }

  Uint8List _probePacket(List<int> token, String kind, int nonce) {
    final builder = BytesBuilder();
    builder.add(utf8.encode('CP2P1'));
    builder.addByte(token.length);
    builder.add(token);
    builder.addByte(kind.codeUnitAt(0));
    final data = ByteData(4)..setUint32(0, nonce);
    builder.add(data.buffer.asUint8List());
    return builder.toBytes();
  }

  (String, int)? _parseProbe(Uint8List data, List<int> token) {
    if (data.length < 5 + 1 + token.length + 1 + 4) return null;
    if (utf8.decode(data.sublist(0, 5), allowMalformed: true) != 'CP2P1') {
      return null;
    }
    final tokenLength = data[5];
    if (tokenLength != token.length) return null;
    final tokenBytes = data.sublist(6, 6 + tokenLength);
    for (var i = 0; i < token.length; i++) {
      if (tokenBytes[i] != token[i]) return null;
    }
    final kindOffset = 6 + tokenLength;
    final kind = String.fromCharCode(data[kindOffset]);
    if (kind != 'P' && kind != 'A') return null;
    final nonce = ByteData.sublistView(
      data.sublist(kindOffset + 1, kindOffset + 5),
    ).getUint32(0);
    return (kind, nonce);
  }
}
