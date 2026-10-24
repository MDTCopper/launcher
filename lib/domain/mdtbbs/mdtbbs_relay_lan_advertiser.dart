import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/util/io/log.dart';

/// Mindustry 局域网发现用的组播组与端口（`NetworkIO` 的硬编码值）
const kMindustryDiscoveryGroup = '227.2.7.7';
const kMindustryDiscoveryPort = 20151;

/// Mindustry 的局域网探测包，等价 `ArcNetProvider.pingHostImpl` 里的 `{-2, 1}`
const List<int> kMindustryDiscoveryProbe = [0xFE, 0x01];

/// 官方中继房客侧：把房间伪装成本机局域网里的一个房间
///
/// 游戏只会向 [kMindustryDiscoveryGroup]:[kMindustryDiscoveryPort] 发探测；
/// 这里加入同一个组播组，收到**本机**的探测就回一份服务器信息负载。
/// 回包 socket 绑在 `127.0.0.1`，游戏看到的服务器地址才会是 loopback，
/// 从而连到 [port] 上的中继代理。
///
/// 负载由 [payloadProvider] 现取：房主游戏没在开房时不回，房间就不会出现在列表里
class MdtbbsRelayLanAdvertiser {
  MdtbbsRelayLanAdvertiser({
    required this.port,
    required this.payloadProvider,
    this.replyDelay,
  });

  final int port;

  /// 返回 null 表示这次不回：游戏收不到应答，房间自然不出现
  final Uint8List? Function() payloadProvider;

  /// 回包前压多久：游戏用「探测发出 → 收到应答」算列表里的延迟，
  /// 直接从 loopback 秒回会显示 0ms，而实际数据要绕中继一圈
  final Duration Function()? replyDelay;

  RawDatagramSocket? _multicast;
  RawDatagramSocket? _reply;
  StreamSubscription<RawSocketEvent>? _subscription;
  Set<String> _localAddresses = const {};
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kMindustryDiscoveryPort,
        reuseAddress: true,
      );
      _multicast = socket;
      socket.joinMulticast(InternetAddress(kMindustryDiscoveryGroup));
    } on Object catch (error) {
      // 本机开房时游戏的 MulticastSocket 占着 20151；代理照常，只是房间不出现
      addLogAndPrint(
        .warning,
        '伪局域网：绑定组播端口 $kMindustryDiscoveryPort 失败：$error',
        tag: 'Multiplayer',
      );
      await dispose();
      return;
    }

    try {
      _reply = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    } on Object catch (error) {
      addLogAndPrint(.warning, '伪局域网：绑定回包端口失败：$error', tag: 'Multiplayer');
      await dispose();
      return;
    }

    _localAddresses = await _collectLocalAddresses();

    _subscription = _multicast!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _multicast?.receive();
      if (datagram == null) return;
      // 只回本机自己的探测：广告的是 127.0.0.1，回给别人只会塞个连不上的房间
      if (!_localAddresses.contains(datagram.address.address)) return;
      final payload = payloadProvider();
      if (payload == null) return;
      final delay = replyDelay?.call() ?? Duration.zero;
      final reply = _reply;
      final targetPort = datagram.port;
      if (reply == null) return;
      if (delay <= Duration.zero) {
        reply.send(payload, InternetAddress.loopbackIPv4, targetPort);
        return;
      }
      unawaited(
        Future<void>.delayed(delay, () {
          if (!_running) return;
          reply.send(payload, InternetAddress.loopbackIPv4, targetPort);
        }),
      );
    });
  }

  Future<void> dispose() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
    _multicast?.close();
    _multicast = null;
    _reply?.close();
    _reply = null;
  }

  /// 本机所有 IPv4 地址：组播探测的源地址通常是某张网卡的地址，不是 loopback
  Future<Set<String>> _collectLocalAddresses() async {
    final addresses = <String>{'127.0.0.1'};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: true,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          addresses.add(address.address);
        }
      }
    } on Object catch (error) {
      addLogAndPrint(.warning, '伪局域网：读取本机地址失败：$error', tag: 'Multiplayer');
    }
    return addresses;
  }
}

/// `NetworkIO.writeServerData` 的等价实现；`version = -1` 跳过客户端版本门禁
Uint8List buildMindustryServerData({
  required String roomName,
  required int port,
  int players = 1,
  int maxPlayers = 8,
}) {
  final builder = BytesBuilder();
  _writeString(builder, roomName, 100);
  _writeString(builder, 'Copper 联机', 64);
  _writeInt32(builder, players);
  _writeInt32(builder, 0); // 波次
  _writeInt32(builder, -1); // 版本
  _writeString(builder, '', 32); // 版本类型
  builder.addByte(0); // 玩法：0 = 生存
  _writeInt32(builder, maxPlayers);
  _writeString(builder, 'Copper 联机房间', 100);
  _writeString(builder, '', 50); // 模式名
  _writeInt16(builder, port); // v152 起客户端从这里取端口
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
