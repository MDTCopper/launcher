import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:dio/dio.dart';

/// 一条在线连接（`POST /presence/connections` 的应答）
class MdtbbsPresenceConnection {
  const MdtbbsPresenceConnection({
    required this.connectionId,
    required this.heartbeatInterval,
    required this.expiresIn,
  });

  final String connectionId;

  /// 服务端要求的间隔（秒），官方文档给的是 30
  final int heartbeatInterval;

  /// 多久没有心跳算过期（秒），官方文档给的是 90
  final int expiresIn;

  factory MdtbbsPresenceConnection.fromJson(Map<String, dynamic> json) =>
      MdtbbsPresenceConnection(
        connectionId: '${json['connection_id'] ?? ''}',
        heartbeatInterval: _asInt(json['heartbeat_interval']) ?? 30,
        expiresIn: _asInt(json['expires_in']) ?? 90,
      );
}

int? _asInt(Object? value) => switch (value) {
  final int value => value,
  final num value => value.toInt(),
  final String value => int.tryParse(value),
  _ => null,
};

/// BBS 在线状态 API（`/api/v1/presence`，scope = `presence.write`）
///
/// 官方流程（`/api/v1/docs/multiplayer`）：登录后 `POST /presence/connections`
/// 建连接，再按服务端给的间隔心跳；**不上报就一直显示离线**。
/// 2026-10-24 之前没接这一段，所以好友列表里永远是「在线 0」
class MdtbbsPresenceApi {
  MdtbbsPresenceApi._();

  static const _base = '/presence';
  static const Duration _callTimeout = Duration(seconds: 20);

  /// [platform] 取 `web` / `launcher` / `lanlink` / `mindustry_mod` / `android`
  static Future<MdtbbsPresenceConnection> createConnection({
    required String accessToken,
    required String platform,
    String status = 'online',
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/connections',
      body: {'platform': platform, 'status': status},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsPresenceConnection.fromJson(
      (data as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  static Future<void> heartbeat({
    required String accessToken,
    required String connectionId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      '$_base/connections/$connectionId/heartbeat',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  static Future<void> setStatus({
    required String accessToken,
    required String connectionId,
    required String status,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.patchJson(
      '$_base/connections/$connectionId',
      body: {'status': status},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  /// 关掉连接。失败不抛给调用方 —— 退出登录时连接自己会过期
  static Future<void> deleteConnection({
    required String accessToken,
    required String connectionId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.deleteJson(
      '$_base/connections/$connectionId',
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }
}
