import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';
import 'package:copper_launcher/util/io/copper_io.dart';

/// MDTBBS 接口调用的失败
///
/// 控制流只认 HTTP 状态码与稳定的 [code]，**不匹配中文消息**
/// （官方约定：错误文案会变，`error.code` 才是不变量）
class MdtbbsException implements Exception {
  const MdtbbsException({
    this.statusCode,
    this.code = '',
    this.message = '',
    this.requestId,
    this.retryable = false,
    this.details = const [],
  });

  final int? statusCode;

  /// 稳定错误码，如 `INSUFFICIENT_SCOPE`、`RATE_LIMITED`、`PHONE_NOT_VERIFIED`
  final String code;

  /// 服务端给的中文说明，**只用于展示**，不拿它做判断
  final String message;

  /// 报障时提供给维护者的 `meta.request_id`
  final String? requestId;

  final bool retryable;

  /// `error.details` 原样保留：不同接口的补充信息（例如冲突时的当前快照 ID）在这里
  final List<Object?> details;

  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  /// scope 不够：`error.details` 里会带 `requiredScopes`
  bool get isInsufficientScope => code == 'INSUFFICIENT_SCOPE';

  bool get isRateLimited => statusCode == 429 || code == 'RATE_LIMITED';

  /// 云端 head 变过 ⇒ 上传被拒，details 里应有当前快照 ID
  bool get isConflict => statusCode == 409;

  /// 从 [details] 里尽力找出「当前快照 ID」；找不到给 null
  ///
  /// 冲突响应的字段名官方文档没写死（`paths` 未导出），所以这里两种常见形态都认
  String? get conflictCurrentSnapshotId {
    for (final detail in details) {
      if (detail is! Map) continue;
      final value =
          detail['current_snapshot_id'] ??
          detail['currentSnapshotId'] ??
          detail['snapshot_id'];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  @override
  String toString() {
    final status = statusCode == null ? '' : 'HTTP $statusCode ';
    final codeText = code.isEmpty ? '' : '$code ';
    final request = requestId == null ? '' : '（request_id: $requestId）';
    return 'MDTBBS 请求失败：$status$codeText$message$request';
  }
}

/// 官方信封 `{ data, meta }`：分页游标与报障用的 request_id 都在 `meta` 里
class MdtbbsEnvelope {
  const MdtbbsEnvelope(this.data, this.meta);

  final Object? data;
  final Map<String, dynamic> meta;

  /// 云存档的槽位列表用 `meta.next_cursor` 翻页（约定里特别注明它不在 `data` 里）
  String? get nextCursor => meta['next_cursor'] as String?;

  String? get requestId => meta['request_id'] as String?;

  factory MdtbbsEnvelope.fromBody(Object? body) {
    if (body is Map) {
      final map = body.cast<String, dynamic>();
      if (map.containsKey('data') || map.containsKey('meta')) {
        return MdtbbsEnvelope(
          map['data'],
          (map['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      }
    }
    return MdtbbsEnvelope(body, const {});
  }
}

/// MDTBBS 接口的统一出入口：信封解包 + 错误映射 + Bearer 注入
///
/// 请求走项目统一的 [cio]（自带代理跟随与 UA），非 github 域名不会进镜像回退；
/// 官方响应一律是 `{ data, meta }`，出错是 `{ error, meta }`
class MdtbbsClient {
  MdtbbsClient._();

  /// 补成绝对地址，三种形态都认：
  /// - 绝对 URL 原样放行（MindAuth 的 token 端点在 issuer 上）
  /// - 服务端回的站内路径（`/api/v1/...`）拼站点源
  /// - 本层的相对路径（`/game-saves/...`）拼 [MdtbbsConfig.apiBase]
  static String urlOf(String path) {
    if (path.startsWith('http')) return path;
    if (path.startsWith('/api/')) return '${MdtbbsConfig.origin}$path';
    return '${MdtbbsConfig.apiBase}$path';
  }

  static Future<Object?> getJson(
    String path, {
    String? accessToken,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) => _send(
    'GET',
    path,
    accessToken: accessToken,
    headers: headers,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
  );

  static Future<Object?> postJson(
    String path, {
    Object? body,
    String? accessToken,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _send(
    'POST',
    path,
    body: body,
    accessToken: accessToken,
    headers: headers,
    cancelToken: cancelToken,
  );

  static Future<Object?> patchJson(
    String path, {
    Object? body,
    String? accessToken,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _send(
    'PATCH',
    path,
    body: body,
    accessToken: accessToken,
    headers: headers,
    cancelToken: cancelToken,
  );

  static Future<Object?> deleteJson(
    String path, {
    Object? body,
    String? accessToken,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _send(
    'DELETE',
    path,
    body: body,
    accessToken: accessToken,
    headers: headers,
    cancelToken: cancelToken,
  );

  /// 上传字节：**原样送**，不压缩不改动（服务端会重新算 sha256 核对）
  static Future<Object?> putBytes(
    String path, {
    required List<int> bytes,
    String? accessToken,
    Map<String, String>? headers,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final merged = <String, String>{
      'Content-Type': 'application/octet-stream',
      ...?headers,
      ...?_authHeader(accessToken),
    };
    try {
      final response = await cio.put(
        urlOf(path),
        data: bytes,
        headers: merged,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      return MdtbbsEnvelope.fromBody(response.data).data;
    } on DioException catch (error) {
      throw _asMdtbbsException(error);
    }
  }

  /// 把文件下到 [savePath]（走 cio 的分块 / 单流统一管线）
  static Future<void> downloadFile({
    required String path,
    required String savePath,
    String? accessToken,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    HttpStatusCallback? onStatus,
  }) async {
    try {
      await cio.download(
        url: urlOf(path),
        savePath: savePath,
        headers: {...?headers, ...?_authHeader(accessToken)},
        cancelToken: cancelToken,
        onStatus: onStatus,
      );
    } on DioException catch (error) {
      throw _asMdtbbsException(error);
    }
  }

  /// 需要读 `meta`（翻页游标 / request_id）时用这个
  static Future<MdtbbsEnvelope> getEnvelope(
    String path, {
    String? accessToken,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) => _sendEnvelope(
    'GET',
    path,
    accessToken: accessToken,
    headers: headers,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
  );

  static Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    String? accessToken,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async => (await _sendEnvelope(
    method,
    path,
    body: body,
    accessToken: accessToken,
    headers: headers,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
  )).data;

  static Future<MdtbbsEnvelope> _sendEnvelope(
    String method,
    String path, {
    Object? body,
    String? accessToken,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final url = urlOf(path);
    final mergedHeaders = <String, String>{
      ...?headers,
      ...?_authHeader(accessToken),
    };
    try {
      final Response<Object?> response;
      switch (method) {
        case 'GET':
          response = await cio.get<Object?>(
            url,
            headers: mergedHeaders,
            queryParameters: queryParameters,
            cancelToken: cancelToken,
          );
        case 'POST':
          response = await cio.post<Object?>(
            url,
            data: body,
            headers: mergedHeaders,
            cancelToken: cancelToken,
          );
        case 'PATCH':
          response = await cio.patch<Object?>(
            url,
            data: body,
            headers: mergedHeaders,
            cancelToken: cancelToken,
          );
        case 'DELETE':
          response = await cio.delete<Object?>(
            url,
            data: body,
            headers: mergedHeaders,
            cancelToken: cancelToken,
          );
        default:
          throw ArgumentError('不支持的方法：$method');
      }
      return MdtbbsEnvelope.fromBody(response.data);
    } on DioException catch (error) {
      throw _asMdtbbsException(error);
    }
  }

  static Map<String, String>? _authHeader(String? accessToken) {
    if (accessToken == null || accessToken.isEmpty) return null;
    return {'Authorization': 'Bearer $accessToken'};
  }

  /// 错误体有两种形态，都要认：
  /// 论坛是 `{ error: { code, message, retryable, details }, meta }`，
  /// MindAuth 是 OAuth 标准的 `{ error: "invalid_grant", error_description }`
  static MdtbbsException _asMdtbbsException(DioException error) {
    final response = error.response;
    final data = response?.data;

    Map<String, dynamic>? errorBody;
    Map<String, dynamic>? meta;
    var code = '';
    var message = '';

    if (data is Map) {
      final map = data.cast<String, dynamic>();
      final rawError = map['error'];
      if (rawError is Map) {
        errorBody = rawError.cast<String, dynamic>();
        code = '${errorBody['code'] ?? ''}';
        message = '${errorBody['message'] ?? ''}';
      } else if (rawError is String) {
        code = rawError;
        message = '${map['error_description'] ?? ''}';
      }
      final rawMeta = map['meta'];
      if (rawMeta is Map) meta = rawMeta.cast<String, dynamic>();
    }

    if (message.isEmpty) message = error.message ?? '';

    return MdtbbsException(
      statusCode: response?.statusCode,
      code: code,
      message: message,
      requestId: meta?['request_id'] as String?,
      retryable: errorBody?['retryable'] == true,
      details: (errorBody?['details'] as List?) ?? const [],
    );
  }
}
