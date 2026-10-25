import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';

/// 一次性 WebSocket 票据（`POST /realtime/tickets`，权限 `friends.read`）
class MdtbbsRealtimeTicket {
  const MdtbbsRealtimeTicket({
    required this.ticket,
    this.expiresIn,
    this.websocketPath = '/realtime/v1',
  });

  /// 连接凭证：只能用在一次连接上，60 秒不用也会过期
  final String ticket;
  final int? expiresIn;

  /// 相对 API 主机的事件流路径
  final String websocketPath;

  /// 拼成 `wss://<API 主机>/realtime/v1?ticket=...`
  String get socketUrl {
    final origin = MdtbbsConfig.origin;
    final scheme = origin.startsWith('https') ? 'wss' : 'ws';
    final host = origin.replaceFirst(RegExp('^https?://'), '');
    final path = websocketPath.startsWith('/')
        ? websocketPath
        : '/$websocketPath';
    return '$scheme://$host$path?ticket=${Uri.encodeQueryComponent(ticket)}';
  }

  factory MdtbbsRealtimeTicket.fromJson(Map<String, dynamic> json) =>
      MdtbbsRealtimeTicket(
        ticket: '${json['ticket'] ?? ''}',
        expiresIn: (json['expires_in'] as num?)?.toInt(),
        websocketPath: '${json['websocket_path'] ?? '/realtime/v1'}',
      );
}

/// 实时事件流的入口接口
class MdtbbsRealtimeApi {
  MdtbbsRealtimeApi._();

  static Future<MdtbbsRealtimeTicket> ticket({
    required String accessToken,
  }) async {
    final response = await MdtbbsClient.postJson(
      '/realtime/tickets',
      accessToken: accessToken,
    );
    final data = _dataOf(response);
    final ticket = MdtbbsRealtimeTicket.fromJson(data);
    if (ticket.ticket.isEmpty) {
      throw const MdtbbsRealtimeException(message: '服务端没有返回票据');
    }
    return ticket;
  }

  /// 公共接口统一 `{data, meta}`；也兼容直接给对象
  static Map<String, dynamic> _dataOf(Object? response) {
    if (response is Map<String, dynamic>) {
      final data = response['data'];
      if (data is Map) return data.cast<String, dynamic>();
      return response;
    }
    if (response is Map) {
      final data = response['data'];
      if (data is Map) return data.cast<String, dynamic>();
      return response.cast<String, dynamic>();
    }
    throw const MdtbbsRealtimeException(message: '票据响应不是对象');
  }
}

class MdtbbsRealtimeException implements Exception {
  const MdtbbsRealtimeException({required this.message});

  final String message;

  @override
  String toString() => '实时通道：$message';
}
