import 'dart:convert';

import 'package:copper_launcher/data/net/lanlink/lanlink_models.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';

/// LanLink 控制面调用的失败
///
/// 控制面的错误体是自有形状 `{ok:false, code, message}`，稳定判据是 [code]
class LanLinkException implements Exception {
  const LanLinkException({this.statusCode, this.code = '', this.message = ''});

  final int? statusCode;

  /// 稳定错误码，如 `auth_required`、`phone_verification_required`
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401 || code == 'auth_required';
  bool get isNotFound => statusCode == 404;
  bool get isPhoneRequired => code == 'phone_verification_required';

  @override
  String toString() =>
      'LanLink 请求失败：${statusCode == null ? '' : 'HTTP $statusCode '}$code $message';
}

/// LanLink 控制面客户端
///
/// 三条链路里本项目只做「客人侧」的 HTTP 与本地转发：房间码解析、公开房间列表、
/// 节点列表、好友在线状态；控制面与 Mod 之间的 WSS 信令不在这里
class LanLinkApi {
  LanLinkApi._();

  /// 与模组 `LanLinkUi.DEFAULT_CONTROL_URL` 一致
  static const defaultControlUrl = 'll.mdtbbs.cn';

  /// 把用户填的地址补成 `https://host` 形状；留空用官方服务
  static String normalizeBaseUrl(String? raw) {
    var text = (raw ?? '').trim();
    if (text.isEmpty) text = defaultControlUrl;
    if (text.startsWith('https://') || text.startsWith('http://')) {
      return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
    }
    return 'https://${text.endsWith('/') ? text.substring(0, text.length - 1) : text}';
  }

  static Future<LanLinkVersion> version({
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    final json = await _getJson('/api/version', controlUrl, cancelToken);
    return LanLinkVersion(
      latest: '${json['latest'] ?? ''}',
      minimum: '${json['min'] ?? ''}',
      downloadUrl: '${json['url'] ?? ''}',
    );
  }

  /// 按房间码解析房间；房间不存在或已关闭返回 null
  ///
  /// 这个接口匿名可读，公开与不公开房间一样能查到，房号本身就是凭证
  static Future<LanLinkRoom?> room(
    LanLinkRoomCode code, {
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    try {
      final json = await _getJson(
        '/api/rooms/${code.value}',
        controlUrl,
        cancelToken,
      );
      if (json['node'] is! Map) {
        throw const LanLinkException(message: '控制面返回的房间缺少节点信息');
      }
      return LanLinkRoom.fromJson(json);
    } on LanLinkException catch (error) {
      if (error.isNotFound) return null;
      rethrow;
    }
  }

  /// 公开房间列表（只含房主勾了「公开到大厅」的房间）
  static Future<List<LanLinkRoom>> publicRooms({
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    final json = await _getJson('/api/rooms/public', controlUrl, cancelToken);
    final rows = json['rooms'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => LanLinkRoom.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// 控制面已注册的在线中继节点
  static Future<List<LanLinkNode>> nodes({
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    final json = await _getJson(
      '/api/nodes/available',
      controlUrl,
      cancelToken,
    );
    final rows = json['nodes'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => LanLinkNode.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// 用论坛账号密码登录控制面
  ///
  /// 控制面目前只提供账号密码这一条路；MindAuth 令牌换 token 的旧端点
  /// （`/api/auth/mindauth/exchange`）已按 client 门禁，第三方客户端换不到
  static Future<LanLinkAuthSession> login({
    required String username,
    required String password,
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    final json = await _postJson(
      '/api/auth/login',
      {'username': username, 'password': password},
      controlUrl,
      cancelToken,
    );
    return _sessionOf(json);
  }

  /// 刷新登录态并同步手机号验证状态
  static Future<LanLinkAuthSession> refresh(
    String token, {
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    final json = await _postJson(
      '/api/auth/refresh',
      null,
      controlUrl,
      cancelToken,
      accessToken: token,
    );
    return _sessionOf(json);
  }

  /// 好友列表（含在线状态与所在房间），需要登录
  static Future<List<LanLinkFriend>> friends(
    String token, {
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    final json = await _getJson(
      '/api/friends',
      controlUrl,
      cancelToken,
      accessToken: token,
    );
    final rows = json['friends'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => LanLinkFriend.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// 用 MindAuth 的 access token 换联机令牌（`POST /api/auth/mindauth/exchange`）
  ///
  /// ⚠ **遗留端点，站长已确认不再维护（2026-10-11）**：旧谱系模组 0.16~0.19.x 的
  /// 登录方式，新版模组（0.1.0 重写）已改回账号密码。实测它只认自家 client ——
  /// 模组客户端（带 openid）能通；本应用的令牌即使带 openid 也 401。
  /// 保留这一方法只为将来若开放第三方免密码登录时复用；当前请走 [login]
  static Future<LanLinkAuthSession> exchangeMindAuthToken({
    required String accessToken,
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    final json = await _postJson(
      '/api/auth/mindauth/exchange',
      {'access_token': accessToken},
      controlUrl,
      cancelToken,
    );
    return _sessionOf(json);
  }

  /// 邀请好友进自己的房间
  static Future<void> sendInvite({
    required String token,
    required String roomCode,
    required String friendUserId,
    String? controlUrl,
    CancelToken? cancelToken,
  }) async {
    await _postJson(
      '/api/invites/send',
      {'room_code': roomCode, 'friend_user_id': friendUserId},
      controlUrl,
      cancelToken,
      accessToken: token,
    );
  }

  // -- 内部 --------------------------------------------------------------

  static LanLinkAuthSession _sessionOf(Map<String, dynamic> json) {
    if (json['ok'] == false) {
      throw LanLinkException(
        code: '${json['code'] ?? ''}',
        message: '${json['message'] ?? '登录失败'}',
      );
    }
    final session = LanLinkAuthSession.fromJson(json);
    if (!session.isLoggedIn) {
      throw const LanLinkException(message: '控制面返回的登录态不完整');
    }
    return session;
  }

  static Future<Map<String, dynamic>> _getJson(
    String path,
    String? controlUrl,
    CancelToken? cancelToken, {
    String? accessToken,
  }) => _send('GET', path, null, controlUrl, cancelToken, accessToken);

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Object? body,
    String? controlUrl,
    CancelToken? cancelToken, {
    String? accessToken,
  }) => _send('POST', path, body, controlUrl, cancelToken, accessToken);

  static Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Object? body,
    String? controlUrl,
    CancelToken? cancelToken,
    String? accessToken,
  ) async {
    final url = '${normalizeBaseUrl(controlUrl)}$path';
    final headers = <String, String>{'Accept': 'application/json'};
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    try {
      final Response<Object?> response = method == 'GET'
          ? await cio.get<Object?>(
              url,
              headers: headers,
              cancelToken: cancelToken,
            )
          : await cio.post<Object?>(
              url,
              data: body ?? const {},
              headers: headers,
              cancelToken: cancelToken,
            );
      return _asJsonMap(response.data);
    } on DioException catch (error) {
      throw _toException(error);
    }
  }

  /// 控制面的成功响应是裸对象（`/api/rooms/:code`）或带 `ok` 的对象，统一成 Map
  static Map<String, dynamic> _asJsonMap(Object? data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } on FormatException {
        // 落到下面的「格式不正确」
      }
    }
    throw const LanLinkException(message: '控制面返回的不是 JSON 对象');
  }

  static LanLinkException _toException(DioException error) {
    final status = error.response?.statusCode;
    var code = '';
    var message = '';

    final data = error.response?.data;
    Map<String, dynamic>? body;
    if (data is Map) {
      body = data.cast<String, dynamic>();
    } else if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) body = decoded.cast<String, dynamic>();
      } on FormatException {
        message = data;
      }
    }
    if (body != null) {
      code = '${body['code'] ?? ''}';
      message = '${body['message'] ?? ''}';
    }
    if (message.isEmpty) message = error.message ?? '';

    // 路径与方法一起记，哪个请求挂的一眼能看出来
    addLog(
      .warning,
      'LanLink 请求失败 ${error.requestOptions.method} ${error.requestOptions.path}：$message',
      tag: 'LanLink',
    );
    return LanLinkException(statusCode: status, code: code, message: message);
  }
}
