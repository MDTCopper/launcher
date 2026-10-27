import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';
import 'package:dio/dio.dart';

/// BBS 官方好友 API（`/api/v1/friends*`、`/api/v1/social/friends/presence`）
///
/// 第三方客户端可用的就这几条（都在官方 public 白名单里，scope = `friends.read`）：
/// - `GET    /social/friends/presence` 好友 + 在线 + 活动 + **按钮门禁**（列表走这条）
/// - `GET    /friends/requests` 待处理好友请求
/// - `POST   /friends/requests` 发好友请求，`target_user_id` 是**整数**
/// - `POST   /friends/requests/{id}/accept|reject`，`{id}` 是**请求 ID**
/// - `DELETE /friends/{userId}` 删好友，`{userId}` 是**整数用户 ID**
///
/// ⚠ 论坛自己的 `/api/friends/search` 等**没有 v1 的那套不在公开白名单里** ⇒
/// 第三方客户端拿不到「按用户名搜人」，加好友只能由用户自己填用户 ID
/// （从会话成员列表里加是另一条路：`MdtbbsPeer.userId` 就是论坛用户 ID）
class MdtbbsFriendsApi {
  MdtbbsFriendsApi._();

  static const _base = '/friends';
  static const _presencePath = '/social/friends/presence';

  /// 联机与好友接口都是快请求：cio 默认的 600 秒超时会把界面卡死，这里统一收紧
  static const Duration _callTimeout = Duration(seconds: 30);

  /// 好友在线聚合的一页；`limit` 上限 50，`page` 从 1 起
  static Future<MdtbbsFriendPage> friendsPresence({
    required String accessToken,
    int page = 1,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      _presencePath,
      accessToken: accessToken,
      queryParameters: {'page': page, 'limit': limit},
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    // 文档写的是 `data.data` + `data.pagination`；万一某天直接把数组塞在 `data` 里也认
    if (data is List) return MdtbbsFriendPage.fromJson({'data': data});
    return MdtbbsFriendPage.fromJson(_map(data));
  }

  /// 待处理的好友请求（收到的）
  static Future<MdtbbsFriendRequestPage> requests({
    required String accessToken,
    int page = 1,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/requests',
      accessToken: accessToken,
      queryParameters: {'page': page, 'limit': limit},
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    if (data is List) return MdtbbsFriendRequestPage.fromJson({'data': data});
    return MdtbbsFriendRequestPage.fromJson(_map(data));
  }

  /// 发好友请求；[targetUserId] 是**论坛整数用户 ID**（文档写死是 number，别传字符串）
  /// 按用户名搜人（`GET /users/search?q=`，2026-10-26 起公开）
  ///
  /// 服务端已排除：调用者自己、已经是好友的人、被我屏蔽的人
  static Future<List<MdtbbsFriendUser>> searchUsers({
    required String accessToken,
    required String query,
    int limit = 10,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '/users/search',
      accessToken: accessToken,
      queryParameters: {'q': query, 'limit': limit},
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    final list = data is Map ? data['data'] ?? data['items'] : data;
    return ((list as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MdtbbsFriendUser.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
  static Future<void> sendRequest({
    required String accessToken,
    required int targetUserId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      '$_base/requests',
      body: {'target_user_id': targetUserId},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  /// 接受好友请求；[requestId] 是**请求 ID**（不是用户 ID）
  static Future<void> acceptRequest({
    required String accessToken,
    required String requestId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      '$_base/requests/$requestId/accept',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  /// 拒绝好友请求；[requestId] 是**请求 ID**
  static Future<void> rejectRequest({
    required String accessToken,
    required String requestId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      '$_base/requests/$requestId/reject',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  /// 删好友；[userId] 是**整数用户 ID**
  static Future<void> removeFriend({
    required String accessToken,
    required int userId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.deleteJson(
      '$_base/$userId',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  static Map<String, dynamic> _map(Object? data) =>
      (data as Map?)?.cast<String, dynamic>() ?? const {};
}
