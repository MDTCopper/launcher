import 'dart:convert';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';

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

  /// 被写请求的 CSRF 守卫拦下
  ///
  /// 论坛对写操作要求**双提交式令牌**（`Cookie: csrf_token` + `X-CSRF-Token`），
  /// 缺了会返回 403 + `{"success":false,"message":"CSRF token invalid"}` ——
  /// 注意这个错误体**不是 V1 信封**，靠 [message] 认
  bool get isCsrfFailure =>
      statusCode == 403 && message.toUpperCase().contains('CSRF');

  /// [details] 里第一个对象（服务端多数错误把结构化信息放这一条）
  Map<String, dynamic>? get firstDetail {
    for (final detail in details) {
      if (detail is Map) return detail.cast<String, dynamic>();
    }
    return null;
  }

  /// 出问题的文件路径（`SAVE_FILE_TOO_LARGE` / `SAVE_MANIFEST_INVALID` 会带）
  String? get detailPath => firstDetail?['path'] as String?;

  /// 出问题的字段名（`SAVE_MANIFEST_INVALID` 会带）
  String? get detailField => firstDetail?['field'] as String?;

  /// `SAVE_BLOB_MISSING` 时缺哪些 sha：服务端结构没写死，几种形态都认
  List<String> get missingBlobShas {
    final out = <String>[];
    for (final detail in details) {
      final missing = detail is Map ? detail['missing'] : detail;
      final candidates = missing is List ? missing : [if (detail is String) detail];
      for (final item in candidates) {
        if (item is String && item.isNotEmpty) out.add(item);
        if (item is Map) {
          final sha = item['sha256'] ?? item['sha'] ?? item['id'];
          if (sha is String && sha.isNotEmpty) out.add(sha);
        }
      }
    }
    return out;
  }

  /// 建议的冲突处理方式（服务端会在 normal 策略下给 `create_conflict_copy`）
  String? get suggestedConflictResolution =>
      firstDetail?['suggested_resolution'] as String?;

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

  /// 401 时找账号层要一份新 token；账号层在初始化时注册，拿不到就返回 null
  static Future<String?> Function()? renewToken;

  /// 换 token / 撤销 token 这两个端点自己回 401 时**不能**再走「401 自愈」：
  /// 自愈会回头调 `refresh()`，而 refresh 正是这个请求 ⇒ 自己等自己
  /// （Android 上实测能卡十几秒，最后还丢掉 `invalid_grant` 这个码，登不出去）
  static bool _isAuthEndpoint(String url) {
    final target = url.trim();
    return target == MdtbbsConfig.tokenEndpoint ||
        target == MdtbbsConfig.revokeEndpoint;
  }

  /// 这个方法重放安全吗：GET / PUT / DELETE 天然幂等，POST 只有带幂等键才算
  static bool _replayable(String method, Map<String, String>? headers) {
    switch (method) {
      case 'GET':
      case 'PUT':
      case 'DELETE':
        return true;
      case 'POST':
      case 'PATCH':
        if (headers == null) return false;
        return headers.keys.any(
          (key) => key.toLowerCase() == 'idempotency-key',
        );
      default:
        return false;
    }
  }

  /// 401 后强制续期一次并拿新 token；失败返回 null
  static Future<String?> _renewOnUnauthorized() async {
    final hook = renewToken;
    if (hook == null) return null;
    try {
      return await hook();
    } on Object {
      return null;
    }
  }

  /// 只给同源请求带账号凭证
  ///
  /// 服务端可能把上传 / 下载地址换成外部（对象存储 / CDN）的预签名绝对 URL，
  /// 那些地址不该看到本账号的 Bearer 与 CSRF
  static bool _sameOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    for (final base in [MdtbbsConfig.origin, MdtbbsConfig.apiBase]) {
      final origin = Uri.tryParse(base);
      if (origin == null || origin.host.isEmpty) continue;
      if (uri.scheme == origin.scheme && uri.host == origin.host) return true;
    }
    return false;
  }

  static Map<String, String>? _authHeaderIfSameOrigin(
    String? accessToken,
    String url,
  ) => _sameOrigin(url) ? _authHeader(accessToken) : null;

  static Map<String, String>? _csrfHeadersIfSameOrigin(String url) =>
      _sameOrigin(url) ? _csrfHeaders() : null;

  /// 写请求要的 CSRF 令牌（实测 2026-10-03：**不带就一个写操作都做不了**）
  ///
  /// 论坛对写操作做**双提交式**校验：`Cookie: csrf_token=<值>` 与
  /// `X-CSRF-Token: <值>` 要**同时带、且是同一个值**。官方文档的上传流程里
  /// 完全没提这件事，只在 403 的 `{"success":false,"message":"CSRF token invalid"}`
  /// 里露出来。令牌从任意响应的 `set-cookie` 里取（`Max-Age` 一天）
  static String? _csrfToken;

  static Map<String, String>? _csrfHeaders() {
    final token = _csrfToken;
    if (token == null || token.isEmpty) return null;
    return {'Cookie': 'csrf_token=$token', 'X-CSRF-Token': token};
  }

  /// 从响应头里捡 `csrf_token`（服务端会顺手刷新它）
  static void _captureCsrf(Headers? headers) {
    final cookies = headers?.map['set-cookie'];
    if (cookies == null) return;
    for (final cookie in cookies) {
      final matched = RegExp(
        r'(?:^|[;\s])csrf_token=([^;]+)',
      ).firstMatch(cookie);
      if (matched != null) _csrfToken = matched.group(1);
    }
  }

  /// 还没有令牌就先发一个 GET 把它引出来（任意响应都会 set-cookie）
  ///
  /// 先挑与业务无关的公开接口，免得这次「引导」被当成一次业务调用
  /// （比如看起来像「列了一次槽位」）；万一它没带 cookie，再退回一个已知会带的
  static Future<void> _ensureCsrf(
    String? accessToken,
    CancelToken? cancelToken,
  ) async {
    if (_csrfToken != null) return;
    for (final path in const ['/capabilities', '/game-saves']) {
      try {
        final response = await cio.get<Object?>(
          urlOf(path),
          headers: _authHeader(accessToken),
          cancelToken: cancelToken,
        );
        _captureCsrf(response.headers);
      } on DioException catch (error) {
        // 拿不到也不在这一步失败：真发写请求时服务端会再说一次
        _captureCsrf(error.response?.headers);
      }
      if (_csrfToken != null) return;
    }
  }

  /// 用例收尾用：CSRF 是跨用例的静态状态
  @visibleForTesting
  static void resetCsrfToken() => _csrfToken = null;

  static Future<Object?> getJson(
    String path, {
    String? accessToken,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? timeout,
  }) => _send(
    'GET',
    path,
    timeout: timeout,
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
    Duration? timeout,
  }) => _send(
    'POST',
    path,
    timeout: timeout,
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
    Duration? timeout,
  }) => _send(
    'PATCH',
    path,
    timeout: timeout,
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
    Duration? timeout,
  }) => _send(
    'DELETE',
    path,
    timeout: timeout,
    body: body,
    accessToken: accessToken,
    headers: headers,
    cancelToken: cancelToken,
  );

  /// 上传字节：**原样送**，不压缩不改动（服务端会重新算 sha256 核对）
  ///
  /// 也是写请求，同样要 CSRF 令牌
  static Future<Object?> putBytes(
    String path, {
    required List<int> bytes,
    String? accessToken,
    Map<String, String>? headers,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) => _putBytes(
    path,
    bytes: bytes,
    accessToken: accessToken,
    headers: headers,
    onSendProgress: onSendProgress,
    cancelToken: cancelToken,
  );

  static Future<Object?> _putBytes(
    String path, {
    required List<int> bytes,
    String? accessToken,
    Map<String, String>? headers,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
    bool retriedCsrf = false,
    bool retriedAuth = false,
  }) async {
    final url = urlOf(path);
    if (_sameOrigin(url)) await _ensureCsrf(accessToken, cancelToken);
    final merged = <String, String>{
      'Content-Type': 'application/octet-stream',
      ...?headers,
      ...?_authHeaderIfSameOrigin(accessToken, url),
      ...?_csrfHeadersIfSameOrigin(url),
    };
    try {
      final response = await cio.put(
        url,
        data: bytes,
        headers: merged,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      _captureCsrf(response.headers);
      return MdtbbsEnvelope.fromBody(response.data).data;
    } on DioException catch (error) {
      _captureCsrf(error.response?.headers);
      final failure = _asMdtbbsException(error);
      if (!retriedAuth && failure.isUnauthorized && !_isAuthEndpoint(url)) {
        final fresh = await _renewOnUnauthorized();
        if (fresh != null && fresh.isNotEmpty) {
          return _putBytes(
            path,
            bytes: bytes,
            accessToken: fresh,
            headers: headers,
            onSendProgress: onSendProgress,
            cancelToken: cancelToken,
            retriedCsrf: retriedCsrf,
            retriedAuth: true,
          );
        }
      }
      // 重传同一份字节是安全的（服务端按 sha256 校验），所以 CSRF 过期就重试一次
      if (!retriedCsrf && failure.isCsrfFailure) {
        _csrfToken = null;
        return _putBytes(
          path,
          bytes: bytes,
          accessToken: accessToken,
          headers: headers,
          onSendProgress: onSendProgress,
          cancelToken: cancelToken,
          retriedCsrf: true,
        );
      }
      throw failure;
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
    int? chunkCount,
  }) async {
    final url = urlOf(path);
    try {
      await cio.download(
        url: url,
        savePath: savePath,
        headers: {...?headers, ...?_authHeaderIfSameOrigin(accessToken, url)},
        cancelToken: cancelToken,
        onStatus: onStatus,
        chunkCount: chunkCount,
      );
    } on DioException catch (error) {
      throw _asMdtbbsException(error);
    }
  }

  /// 需要读 `meta`（翻页游标 / request_id）时用这个
  /// 与 [getEnvelope] 对应的写请求版本：要 `meta.request_id` 时用它
  static Future<MdtbbsEnvelope> postEnvelope(
    String path, {
    Object? body,
    String? accessToken,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    Duration? timeout,
  }) => _sendEnvelope(
    'POST',
    path,
    body: body,
    accessToken: accessToken,
    headers: headers,
    cancelToken: cancelToken,
  );

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
    Duration? timeout,
  }) async {
    // cio 的 receive 超时是 600 秒，挂一次就把 UI 卡十分钟——调用方可收紧
    final future = _sendEnvelope(
      method,
      path,
      body: body,
      accessToken: accessToken,
      headers: headers,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    );
    final envelope = timeout == null
        ? await future
        : await future.timeout(timeout);
    return envelope.data;
  }

  static Future<MdtbbsEnvelope> _sendEnvelope(
    String method,
    String path, {
    Object? body,
    String? accessToken,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool retriedCsrf = false,
    bool retriedAuth = false,
  }) async {
    final url = urlOf(path);
    final isWrite = method != 'GET';
    addLog(.debug, '$method $url', tag: 'Mdtbbs');
    // 写请求先确保手里有 CSRF 令牌，否则会被守卫直接 403
    if (isWrite) await _ensureCsrf(accessToken, cancelToken);

    final mergedHeaders = <String, String>{
      ...?headers,
      ...?_authHeaderIfSameOrigin(accessToken, url),
      ...?_csrfHeadersIfSameOrigin(url),
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
      _captureCsrf(response.headers);
      return MdtbbsEnvelope.fromBody(response.data);
    } on DioException catch (error) {
      _captureCsrf(error.response?.headers);
      final failure = _asMdtbbsException(error);
      // 401：服务端提前吊销 / 时钟偏差 ⇒ 强制续期一次，只重放幂等请求
      if (!retriedAuth &&
          failure.isUnauthorized &&
          !_isAuthEndpoint(url) &&
          _replayable(method, headers)) {
        final fresh = await _renewOnUnauthorized();
        if (fresh != null && fresh.isNotEmpty) {
          return _sendEnvelope(
            method,
            path,
            body: body,
            accessToken: fresh,
            headers: headers,
            queryParameters: queryParameters,
            cancelToken: cancelToken,
            retriedCsrf: retriedCsrf,
            retriedAuth: true,
          );
        }
      }
      // 令牌过期（Max-Age 一天）或服务端换了令牌：丢掉重新引一次，只重试一次
      if (isWrite && !retriedCsrf && failure.isCsrfFailure) {
        _csrfToken = null;
        return _sendEnvelope(
          method,
          path,
          body: body,
          accessToken: accessToken,
          headers: headers,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          retriedCsrf: true,
        );
      }
      throw failure;
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
      } else if (map['success'] == false) {
        // 论坛第一方的错误体（CSRF 这类守卫用它，不是 V1 信封）
        message = '${map['message'] ?? ''}';
        code = '${map['code'] ?? ''}';
      }
      final rawMeta = map['meta'];
      if (rawMeta is Map) meta = rawMeta.cast<String, dynamic>();
    }

    if (message.isEmpty) {
      // 认不出的错误体也要留原文（500 常是空的或另一个形状），否则只剩 dio 那段英文套话，
      // 报障时维护者拿不到任何线索
      message = _rawSnippet(data) ?? '';
    }
    // 500 的错误体常常是纯文本、信封里没有 request_id ⇒ 再去响应头里找一次
    // （报障时要的就是它，服务端多半把追踪 ID 放在头里）
    final requestId = _requestIdOf(meta, response?.headers.map);

    if (message.isEmpty) {
      final status = response?.statusCode;
      message = status == null
          ? (error.message ?? '')
          : 'HTTP $status 且服务端没给错误详情'
                '${requestId == null ? '' : '，request_id $requestId'}';
    }

    final failure = MdtbbsException(
      statusCode: response?.statusCode,
      code: code,
      message: message,
      requestId: requestId,
      retryable: errorBody?['retryable'] == true,
      details: (errorBody?['details'] as List?) ?? const [],
    );

    // 路径与方法一起记：哪个请求挂的、服务端说了什么，日志里一眼能看出来；
    // 追踪 ID 不论从哪来都记上 —— 报障时靠的就是这一行
    addLog(
      .warning,
      '请求失败 ${error.requestOptions.method} ${error.requestOptions.path}'
      '：${failure.message}'
      '${failure.details.isEmpty ? '' : '；details: ${failure.details.join('; ')}'}'
      '${requestId == null ? '' : '（request_id: $requestId）'}',
      tag: 'Mdtbbs',
    );
    return failure;
  }

  /// 追踪 ID 可能藏在响应头里 —— `meta.request_id` 只有 V1 信封的错误体才有
  static const _requestIdHeaders = [
    'x-request-id',
    'x-requestid',
    'request-id',
    'x-trace-id',
    'x-amzn-trace-id',
    'cf-ray',
  ];

  /// 先认信封里的 `meta.request_id`，没有再去响应头里找常见的追踪 ID
  static String? _requestIdOf(
    Map<String, dynamic>? meta,
    Map<String, List<String>>? headers,
  ) {
    final fromBody = meta?['request_id'];
    if (fromBody is String && fromBody.trim().isNotEmpty) {
      return fromBody.trim();
    }
    if (headers == null) return null;
    for (final entry in headers.entries) {
      if (!_requestIdHeaders.contains(entry.key.toLowerCase())) continue;
      for (final value in entry.value) {
        if (value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  /// 认不出的错误体截一段原文（换行压平、超长截断）
  static String? _rawSnippet(Object? data) {
    final text = switch (data) {
      final String value => value,
      final Map value => jsonEncode(value),
      final List value => jsonEncode(value),
      null => null,
      _ => '$data',
    };
    if (text == null) return null;
    final trimmed = removeNewlines(text).trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= _rawSnippetLimit
        ? trimmed
        : '${trimmed.substring(0, _rawSnippetLimit)}…';
  }

  /// 错误体最多留这么长：够看出是 HTML 错误页还是 JSON 就行
  static const _rawSnippetLimit = 300;
}
