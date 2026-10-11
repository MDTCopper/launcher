import 'dart:typed_data';

/// 官方中继数据通道的二进制帧（MLR1）
///
/// 布局：`[4B magic "MLR1"][1B version=1][1B type][负载]`
/// - TCP 数据：`[4B 大端 stream_id][1..16384B 载荷]`
/// - TCP 关闭：`[4B 大端 stream_id]`（零载荷）
/// - UDP 数据报：`[1B 目标 peerId 长度][ASCII peerId][1..65401B 载荷]`
///
/// 方向语义：房主发出的 UDP 帧填**房客 peerId**，房客发出的填**房主 peerId**
class MdtbbsRelayFrame {
  MdtbbsRelayFrame._();

  static const List<int> _magic = [0x4D, 0x4C, 0x52, 0x31]; // "MLR1"
  static const int version = 1;

  static const int typeTcpData = 1;
  static const int typeTcpClose = 2;
  static const int typeUdpDatagram = 3;

  static const int maxTcpPayload = 16384;
  static const int maxUdpPayload = 65401;
  static const int maxPeerIdLength = 128;

  /// TCP 数据帧；载荷为空或超上限返回 null（调用方应当作编程错误处理）
  static Uint8List? tcpData(int streamId, List<int> payload) {
    if (payload.isEmpty || payload.length > maxTcpPayload) return null;
    final out = Uint8List(10 + payload.length);
    out.setRange(0, 4, _magic);
    out[4] = version;
    out[5] = typeTcpData;
    final id = ByteData(4)..setInt32(0, streamId, Endian.big);
    out.setRange(6, 10, id.buffer.asUint8List());
    out.setRange(10, out.length, payload);
    return out;
  }

  /// TCP 关闭帧
  static Uint8List tcpClose(int streamId) {
    final out = Uint8List(10);
    out.setRange(0, 4, _magic);
    out[4] = version;
    out[5] = typeTcpClose;
    final id = ByteData(4)..setInt32(0, streamId, Endian.big);
    out.setRange(6, 10, id.buffer.asUint8List());
    return out;
  }

  /// UDP 数据报帧；peerId 或载荷超界返回 null
  static Uint8List? udpDatagram(String targetPeerId, List<int> payload) {
    final target = Uint8List.fromList(targetPeerId.codeUnits);
    if (target.isEmpty || target.length > maxPeerIdLength) return null;
    if (payload.isEmpty || payload.length > maxUdpPayload) return null;
    final out = Uint8List(8 + target.length + payload.length);
    out.setRange(0, 4, _magic);
    out[4] = version;
    out[5] = typeUdpDatagram;
    out[6] = target.length;
    out.setRange(7, 7 + target.length, target);
    out.setRange(7 + target.length, out.length, payload);
    return out;
  }

  /// 解析；magic / 版本 / 长度不合法返回 null（静默丢弃，与参考实现一致）
  static MdtbbsRelayFrame? parse(Uint8List frame) {
    if (frame.length < 6) return null;
    for (var i = 0; i < 4; i++) {
      if (frame[i] != _magic[i]) return null;
    }
    if (frame[4] != version) return null;
    final type = frame[5];

    if (type == typeTcpData || type == typeTcpClose) {
      if (frame.length < 10) return null;
      final id = ByteData.sublistView(frame, 6, 10).getInt32(0, Endian.big);
      final payload = Uint8List.sublistView(frame, 10);
      if (type == typeTcpData &&
          (payload.isEmpty || payload.length > maxTcpPayload)) {
        return null;
      }
      if (type == typeTcpClose && payload.isNotEmpty) return null;
      return MdtbbsRelayFrame._(type, id, '', payload);
    }

    if (type == typeUdpDatagram) {
      if (frame.length < 8) return null;
      final targetLength = frame[6];
      if (targetLength < 1 ||
          targetLength > maxPeerIdLength ||
          frame.length <= 7 + targetLength) {
        return null;
      }
      final target = String.fromCharCodes(frame.sublist(7, 7 + targetLength));
      final payload = Uint8List.sublistView(frame, 7 + targetLength);
      if (payload.isEmpty || payload.length > maxUdpPayload) return null;
      return MdtbbsRelayFrame._(type, 0, target, payload);
    }

    return null;
  }

  const MdtbbsRelayFrame._(
    this.type,
    this.streamId,
    this.targetPeerId,
    this.payload,
  );

  final int type;
  final int streamId;

  /// 仅 UDP 帧有值：目标对端
  final String targetPeerId;
  final Uint8List payload;
}
