import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/github_mirror.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../math/speed_calculate.dart';

///dio 类型复导出：调用方只需 import 本文件即可同时获得类型（Response、
///CancelToken、Options、DioException…）与网络单例 [cio]。
export 'package:dio/dio.dart';

typedef HttpStatusCallback = void Function(HttpDownloadState state);

enum HttpDownloadStatus {
  idle,
  connecting,
  downloading,
  merging,
  completed,
  failed,
  cancelled,
}

class HttpDownloadState {
  int downloaded;
  int total;
  double speed;
  double progress;
  HttpDownloadStatus status;
  int chunkCount;
  int completedChunks;
  int connectingChunks;
  List<HttpChunkInfo> chunks;

  HttpDownloadState({
    this.downloaded = 0,
    this.total = 0,
    this.speed = 0,
    this.progress = 0,
    this.status = HttpDownloadStatus.idle,
    this.chunkCount = 0,
    this.completedChunks = 0,
    this.connectingChunks = 0,
    List<HttpChunkInfo>? chunks,
  }) : chunks = chunks ?? [];

  void copyFrom(HttpDownloadState other) {
    downloaded = other.downloaded;
    total = other.total;
    speed = other.speed;
    progress = other.progress;
    status = other.status;
    chunkCount = other.chunkCount;
    completedChunks = other.completedChunks;
    connectingChunks = other.connectingChunks;
    chunks = other.chunks;
  }

  String get speedText {
    if (speed < KB) return '${speed.toStringAsFixed(1)} B/s';
    if (speed < MB) return '${(speed / KB).toStringAsFixed(1)} KB/s';
    return '${(speed / MB).toStringAsFixed(1)} MB/s';
  }

  String get progressText {
    if (total == 0) return '0.0%';
    return '${(progress * 100).toStringAsFixed(1)}%';
  }
}

class HttpChunkInfo {
  final int index;
  final int start;
  final int end;
  final int size;
  int received;
  HttpChunkStatus status;

  HttpChunkInfo({
    required this.index,
    required this.start,
    required this.end,
    required this.size,
    this.received = 0,
    this.status = HttpChunkStatus.pending,
  });

  double get progress => size > 0 ? received / size : 0;
}

enum HttpChunkStatus { pending, connecting, downloading, complete, failed }

// --- 共享限速器：基于滑动窗口，精准控制总速率 ---

class _RateLimiter {
  final int bytesPerSecond;
  int _totalBytes = 0;
  final Stopwatch _stopwatch = Stopwatch()..start();
  bool _firstChunk = true;

  _RateLimiter(this.bytesPerSecond);

  Future<void> throttle(int bytes) async {
    if (bytesPerSecond <= 0) return;

    _totalBytes += bytes;
    final elapsedMs = _stopwatch.elapsedMilliseconds;

    // 第一个数据块通常较大（TCP 初始窗口），延后建立基线避免误伤
    if (_firstChunk) {
      _firstChunk = false;
      if (elapsedMs < 200) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      _stopwatch.reset();
      _totalBytes = bytes;
      return;
    }

    final expectedMs = (_totalBytes / bytesPerSecond * 1000).round();
    final deficit = expectedMs - elapsedMs;

    if (deficit > 0) {
      await Future.delayed(Duration(milliseconds: deficit));
    }
  }
}

// --- 全局网络单例 ---

/// Copper 项目唯一的网络入口：合并原 [HttpHelper]（代理/分块下载）与
/// [Downloader]（多分块 task 下载），对外复刻 dio 的方法面。
///
/// 请求工作流：
/// 1. 直连官方 URL，拦截器自动补 UA；请求 api.github.com 且配置了
///    token 时附加 Authorization
/// 2. 直连失败（连接类错误）→ 走 github 镜像（[GithubMirror]）回退，
///    官方优先、错误驱动，镜像选最优并带 TTL 缓存
/// 3. 大文件下载走分块并发（断点续传）或单流回退，限速/线程默认值来自
///    [config]
///
/// 代理三模式（跟随系统/自定义/关闭）与下载默认值在启动或设置页变更后
/// 通过 [applySettings] 同步，无需重启。
final CopperIO cio = CopperIO.instance;

class CopperIO {
  static final CopperIO _instance = CopperIO._();

  static CopperIO get instance => _instance;

  factory CopperIO() => _instance;

  CopperIO._();

  Dio? _dio;
  bool _initialized = false;

  ///自定义代理；为 null 表示未设置自定义代理
  String? _proxyHost;
  int? _proxyPort;
  String? _proxyUsername;
  String? _proxyPassword;

  ///显式关闭代理（既不自定义也不跟随系统）
  bool _proxyOff = false;

  ///从 [config] 读取的默认下载限速（字节/秒），<=0 表示不限速
  int _defaultSpeedLimitBytes = 0;

  ///从 [config] 读取的默认分块数
  int _defaultChunkCount = 8;

  ///github token（明文），请求 api.github.com 时自动附加
  String _githubToken = '';

  ///镜像使用策略（由 [applySettings] 注入，默认优先官方源）
  MirrorStrategy _mirrorStrategy = MirrorStrategy.githubFirst;

  Duration _connectTimeout = const Duration(seconds: 20);
  Duration _receiveTimeout = const Duration(seconds: 600);

  int _maxRetries = 5;

  String get userAgent => 'CopperLauncher/$appVersion';

  ///应用设置：token / 代理 / 下载默认值 / 镜像策略全部由**入参**提供，
  ///cio 自身不读全局 config（便于测试与其它调用方复用）。
  ///
  ///启动在 [initAppConfig] 之后调用；下载设置页每次改动 config 后也调用，
  ///保证新请求（含新开始的下载）即时生效。
  void applySettings(Setting setting) {
    //trim 防止历史配置残留空白 token（`token   ` 也会触发 GitHub 401）
    _githubToken = setting.githubToken.trim();
    _defaultSpeedLimitBytes = setting.downloadOptions.speedLimitBytes;
    _defaultChunkCount = setting.downloadOptions.maxTread;
    _mirrorStrategy = setting.mirrorOptions.strategy;

    applyProxySetting(setting.proxyOptions);
    GithubMirror.instance.applySettings(setting.mirrorOptions);
  }

  /// 当前镜像策略（供调试 / 测试查看）
  MirrorStrategy get mirrorStrategy => _mirrorStrategy;

  ///应用配置里的代理（跟随系统 / 自定义 / 关闭三种模式）。
  void applyProxySetting(ProxyOptions options) {
    switch (options.mode) {
      case ProxyMode.system:
        clearProxy();
      case ProxyMode.custom:
        final host = options.host.trim();
        if (host.isEmpty || options.port <= 0) {
          //无效自定义代理 → 回落跟随系统，避免产生畸形 PROXY 串
          clearProxy();
        } else {
          setProxy(
            host: host,
            port: options.port,
            username: options.username,
            password: options.password,
          );
        }
      case ProxyMode.off:
        disableProxy();
    }
  }

  Dio get dio {
    _ensureInit();
    return _dio!;
  }

  void _ensureInit() {
    if (!_initialized) {
      _recreateClient();
      _initialized = true;
      unawaited(_detectWindowsSystemProxy());
    }
  }

  void _recreateClient() {
    final baseOptions = BaseOptions(
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
    );

    final adapter = IOHttpClientAdapter(
      // ignore: deprecated_member_use
      onHttpClientCreate: (client) {
        client.findProxy = (url) {
          if (_hasValidCustomProxy) {
            return 'PROXY $_proxyHost:$_proxyPort';
          }
          if (_proxyOff) return 'DIRECT';
          final proxy = _detectSystemProxy(url);
          if (proxy != null) return 'PROXY $proxy';
          return 'DIRECT';
        };
        if ((_proxyUsername?.isNotEmpty ?? false) && _hasValidCustomProxy) {
          client.addProxyCredentials(
            _proxyHost!,
            _proxyPort ?? 0,
            'realm',
            HttpClientBasicCredentials(_proxyUsername!, _proxyPassword ?? ''),
          );
        }
        return client;
      },
    );

    _dio = Dio(baseOptions);
    _dio!.httpClientAdapter = adapter;
    _dio!.interceptors.add(_buildAuthInterceptor());
  }

  ///自动 UA + github token 注入：请求自身没带对应头时才补。
  InterceptorsWrapper _buildAuthInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        final headers = options.headers;
        bool hasHeader(String name) =>
            headers.keys.any((key) => key.toLowerCase() == name.toLowerCase());

        if (!hasHeader('User-Agent')) {
          headers['User-Agent'] = userAgent;
        }

        // 只对 GitHub API 域名注入 token，避免 token 暴露给 codeload/raw 等 CDN
        final host = Uri.tryParse(options.path)?.host;
        if (host == Uri.parse(githubAPI).host &&
            _githubToken.isNotEmpty &&
            !hasHeader('Authorization')) {
          headers['Authorization'] = 'token $_githubToken';
        }
        handler.next(options);
      },
    );
  }

  ///按镜像策略决定 GitHub 请求走哪条路。
  ///
  /// - [MirrorStrategy.githubFirst]（默认）：直连优先，网络类错误才回退镜像
  ///   （对齐 Mindustry 的错误驱动回退；镜像用 TTL 缓存 10 分钟，过期才测速）
  /// - [MirrorStrategy.mirrorFirst]：先走镜像（校园网 / 直连不通时更快），
  ///   失败再回退官方源
  /// - [MirrorStrategy.githubOnly]：只用官方源
  Future<R> _githubFallback<R>(
    String url,
    Future<R> Function(String effectiveUrl) send,
  ) async {
    if (!GithubMirror.isGithubUrl(url)) return send(url);

    switch (_mirrorStrategy) {
      case MirrorStrategy.githubOnly:
        return send(url);

      case MirrorStrategy.mirrorFirst:
        if (!GithubMirror.instance.enabled) return send(url);
        try {
          return await _sendViaMirror(url, send);
        } catch (e) {
          //镜像拿到真实 HTTP 响应（404 等）就原样抛出，别再回退直连：
          //否则「资源不存在」会被伪装成连接错误，且直连 raw 在部分网络注定失败
          if (e is DioException && !isNetworkFailure(e)) rethrow;
          //镜像不可用 / 无可用节点 → 回退官方源兜底
          return send(url);
        }

      case MirrorStrategy.githubFirst:
        try {
          return await send(url);
        } catch (e) {
          if (!_shouldFallbackToMirror(e, url)) rethrow;
          return _sendViaMirror(url, send);
        }
    }
  }

  ///经镜像发一次请求：取最优节点前缀（TTL 缓存优先，过期才测速）后重发
  Future<R> _sendViaMirror<R>(
    String url,
    Future<R> Function(String effectiveUrl) send,
  ) async {
    final mirror = GithubMirror.instance;
    if (!mirror.enabled) throw StateError('镜像未启用');

    String? prefix = mirror.freshBestMirrorFor(url);
    if (prefix == null) {
      try {
        //按目标域名选探针（api / raw 节点能力不同），但不用本次请求 URL 本身：
        //目标自身不存在（404）会让所有节点「测速失败」，节点选择被带偏
        prefix = await mirror.selectBestMirror(GithubMirror.probeUrlFor(url));
      } catch (_) {
        //测速失败不阻塞，用现有同类最优镜像继续
        prefix = mirror.bestMirrorFor(url);
      }
    }
    if (prefix == null) throw StateError('无可用镜像节点');
    return send('$prefix$url');
  }

  ///是否值得回退镜像：网络类错误一律回退；GitHub 的 401/403（空/失效 token、
  ///匿名限流）也回退——镜像请求不带 token，换 IP 常能绕过
  bool _shouldFallbackToMirror(Object error, String url) {
    if (error is! DioException) return false;
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    if (error.type == DioExceptionType.badResponse &&
        GithubMirror.isGithubUrl(url)) {
      final status = error.response?.statusCode;
      return status == 401 || status == 403;
    }
    return false;
  }

  String? _detectSystemProxy(Uri url) {
    final scheme = url.scheme;

    final proxyEnv =
        Platform.environment['${scheme}_proxy'] ??
        Platform.environment['${scheme.toUpperCase()}_PROXY'] ??
        Platform.environment['all_proxy'] ??
        Platform.environment['ALL_PROXY'];

    if (proxyEnv != null && proxyEnv.isNotEmpty) {
      return proxyEnv.replaceFirst(RegExp(r'^https?://'), '');
    }

    if (Platform.isWindows) {
      //缓存过期时后台重检一次（reg 是进程调用，不能阻塞请求路径）；
      //本次连接仍用旧值，后续连接生效——代理软件开关后最多一个保鲜期内自愈
      if (shouldRedetectSystemProxy(
        checked: _windowsSystemProxyChecked,
        at: _windowsSystemProxyAt,
        refreshing: _windowsSystemProxyRefreshing,
        now: DateTime.now(),
      )) {
        unawaited(_detectWindowsSystemProxy());
      }
      return _windowsSystemProxyChecked ? _windowsSystemProxy : null;
    }

    return null;
  }

  ///Windows 系统代理检测结果（null = 无代理）；由异步检测填充
  String? _windowsSystemProxy;

  ///是否已完成过检测（区分「未检测」与「无代理」两种 null）
  bool _windowsSystemProxyChecked = false;

  ///最近一次检测完成的时间，用于缓存保鲜期判断
  DateTime? _windowsSystemProxyAt;

  ///是否正在后台重检
  bool _windowsSystemProxyRefreshing = false;

  ///系统代理缓存的保鲜期：过期后请求路径会触发后台重检。
  ///否则代理软件开关后，注册表里已变化的代理会被一直使用
  static const _systemProxyTtl = Duration(seconds: 30);

  ///异步检测 Windows 系统代理并缓存结果。
  ///
  ///`reg` 是进程调用，不能在请求路径同步执行——否则每个连接都
  ///`Process.runSync` 阻塞主 isolate 导致 UI 卡顿。启动时检测一次，
  ///缓存过期（[_systemProxyTtl]）后由请求路径再次触发，保证代理软件
  ///开关后注册表的变化能在保鲜期之内被感知。
  Future<void> _detectWindowsSystemProxy() async {
    if (_windowsSystemProxyRefreshing) return;
    _windowsSystemProxyRefreshing = true;
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      ], runInShell: true);
      if (result.exitCode == 0) {
        _windowsSystemProxy = parseWindowsSystemProxy(result.stdout.toString());
      }
    } catch (_) {
      //检测失败保持旧值（可能只是 reg 暂时不可用），下个保鲜期再试
    } finally {
      _windowsSystemProxyRefreshing = false;
      _windowsSystemProxyChecked = true;
      _windowsSystemProxyAt = DateTime.now();
    }
  }

  ///是否需要（重新）检测系统代理：没检测过、结果过期时为 true；
  ///已有检测在跑时不重复触发
  @visibleForTesting
  static bool shouldRedetectSystemProxy({
    required bool checked,
    required DateTime? at,
    required bool refreshing,
    required DateTime now,
  }) {
    if (refreshing) return false;
    if (!checked || at == null) return true;
    return now.difference(at) >= _systemProxyTtl;
  }

  ///从 `reg query` 输出解析系统代理。
  ///
  ///必须同时满足 `ProxyEnable = 1` 才启用，否则即使 `ProxyServer` 残留历史值
  ///（关停的代理软件常留下 `127.0.0.1:<port>`）也视为无代理，避免把已关闭的
  ///代理当成有效路由导致请求全部被拒。
  @visibleForTesting
  static String? parseWindowsSystemProxy(String regOutput) {
    final enableMatch = RegExp(
      r'ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)',
    ).firstMatch(regOutput);
    if (enableMatch == null) return null;
    if (int.tryParse(enableMatch.group(1)!, radix: 16) != 1) return null;

    final serverMatch = RegExp(
      r'ProxyServer\s+REG_SZ\s+(.+)',
    ).firstMatch(regOutput);
    if (serverMatch == null) return null;
    final proxy = serverMatch.group(1)!.trim();
    return proxy.isEmpty ? null : proxy;
  }

  ///切换为跟随系统代理（取消自定义 / 关闭状态）。
  void clearProxy() {
    _proxyHost = null;
    _proxyPort = null;
    _proxyUsername = null;
    _proxyPassword = null;
    _proxyOff = false;
    _recreateClient();
  }

  ///设置自定义代理。
  void setProxy({
    required String host,
    required int port,
    String? username,
    String? password,
  }) {
    _proxyHost = host;
    _proxyPort = port;
    _proxyUsername = username;
    _proxyPassword = password;
    _proxyOff = false;
    _recreateClient();
  }

  ///显式关闭代理（直连）。
  void disableProxy() {
    _proxyHost = null;
    _proxyPort = null;
    _proxyUsername = null;
    _proxyPassword = null;
    _proxyOff = true;
    _recreateClient();
  }

  ///自定义代理是否有效（host 非空且 port 合法）
  bool get _hasValidCustomProxy =>
      (_proxyHost?.isNotEmpty ?? false) && (_proxyPort ?? 0) > 0;

  bool get hasCustomProxy => _hasValidCustomProxy;

  String get proxyInfo {
    if (!_hasValidCustomProxy) return _proxyOff ? 'off' : 'system';
    final auth = (_proxyUsername?.isNotEmpty ?? false)
        ? '$_proxyUsername@'
        : '';
    return '$auth$_proxyHost:$_proxyPort';
  }

  void setTimeout({
    Duration connectTimeout = const Duration(seconds: 20),
    Duration receiveTimeout = const Duration(seconds: 60),
  }) {
    _connectTimeout = connectTimeout;
    _receiveTimeout = receiveTimeout;
    _recreateClient();
  }

  void setMaxRetries(int maxRetries) {
    _maxRetries = maxRetries;
  }

  // ---- HTTP methods ----

  Future<Response<T>> get<T>(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) async {
    _ensureInit();
    return _githubFallback(url, (effectiveUrl) => _dio!.get<T>(
      effectiveUrl,
      options: Options(headers: headers, responseType: responseType),
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    ));
  }

  Future<Response<T>> getUri<T>(
    Uri uri, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) async {
    _ensureInit();
    return _githubFallback(uri.toString(), (effectiveUrl) => _dio!.getUri<T>(
      Uri.parse(effectiveUrl),
      options: Options(headers: headers, responseType: responseType),
      cancelToken: cancelToken,
    ));
  }

  Future<Response> head(
    String url, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    _ensureInit();
    return _githubFallback(url, (effectiveUrl) => _dio!.head(
      effectiveUrl,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    ));
  }

  Future<Response<T>> post<T>(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) async {
    _ensureInit();
    return _githubFallback(url, (effectiveUrl) => _dio!.post<T>(
      effectiveUrl,
      data: data,
      options: Options(headers: headers, responseType: responseType),
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    ));
  }

  Future<bool> supportsRange(String url) async {
    try {
      final resp = await head(url);
      final acceptRanges = resp.headers.value('accept-ranges');
      return acceptRanges != null && acceptRanges.toLowerCase() == 'bytes';
    } catch (_) {
      return false;
    }
  }

  Future<int?> contentLength(String url) async {
    try {
      final resp = await head(url);
      final length = resp.headers.value('content-length');
      if (length != null) return int.tryParse(length);
    } catch (_) {}
    return null;
  }

  // ---- Download ----

  ///统一分块下载：能拿到大小且服务端支持 Range 且足够大 → 多分块并发
  ///（临时分块可断点续传）；否则退化为单流下载。
  ///
  ///[speedLimit] / [chunkCount] 不传时使用 config 默认值；speedLimit<=0 表示不限速。
  ///进度通过 [onStatus] 持续回调 [HttpDownloadState]（含分块明细）。
  ///
  ///官方直连失败（网络类错误）时自动回退到最优镜像重试一次。
  Future<void> download({
    required String url,
    required String savePath,
    int? speedLimit,
    int? chunkCount,
    String? tempPath,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    HttpStatusCallback? onStatus,
    Map<String, String>? headers,
    int? maxRetries,
  }) async {
    _ensureInit();
    if (maxRetries != null) _maxRetries = maxRetries;
    await _githubFallback(
      url,
      (effectiveUrl) => _downloadOnce(
        url: effectiveUrl,
        savePath: savePath,
        speedLimit: speedLimit,
        chunkCount: chunkCount,
        tempPath: tempPath,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        onStatus: onStatus,
        headers: headers,
      ),
    );
  }

  Future<void> _downloadOnce({
    required String url,
    required String savePath,
    int? speedLimit,
    int? chunkCount,
    String? tempPath,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    HttpStatusCallback? onStatus,
    Map<String, String>? headers,
  }) async {
    final effectiveSpeedLimit = speedLimit ?? _defaultSpeedLimitBytes;
    final effectiveChunkCount = max(1, chunkCount ?? _defaultChunkCount);

    // HEAD 只为探大小 / Range 支持，失败不该让整个下载失败：有些站点（如
    // api.mindustry.top）不允许 HEAD，会返回 405。此时按「未知大小、无 Range」
    // 退化为单流，大小改由 GET 响应头补齐（见 _downloadSingleStream）
    var totalSize = 0;
    var rangeSupported = false;
    try {
      final headResp = await _dio!.head(
        url,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      totalSize =
          int.tryParse(headResp.headers.value('content-length') ?? '0') ?? 0;
      rangeSupported =
          headResp.headers.value('accept-ranges')?.toLowerCase() == 'bytes';
    } on DioException catch (e) {
      // 用户取消照旧抛出；HEAD 被拒 / 网络类失败则退化为单流，不在这里终止
      if (CancelToken.isCancel(e)) rethrow;
    }

    if (totalSize <= 0 || !rangeSupported || totalSize < 2 * MB) {
      await _downloadSingleStream(
        url: url,
        savePath: savePath,
        totalSize: totalSize,
        speedLimit: effectiveSpeedLimit,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        onStatus: onStatus,
        headers: headers,
      );
      return;
    }

    await _downloadChunked(
      url: url,
      savePath: savePath,
      totalSize: totalSize,
      chunkCount: effectiveChunkCount,
      speedLimit: effectiveSpeedLimit,
      tempPath: tempPath,
      cancelToken: cancelToken,
      deleteOnError: deleteOnError,
      onStatus: onStatus,
      headers: headers,
    );
  }

  Future<void> _downloadSingleStream({
    required String url,
    required String savePath,
    required int totalSize,
    int? speedLimit,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    HttpStatusCallback? onStatus,
    Map<String, String>? headers,
  }) async {
    final file = File(savePath);
    await file.parent.create(recursive: true);

    final rateLimiter = speedLimit != null && speedLimit > 0
        ? _RateLimiter(speedLimit)
        : null;

    final state = HttpDownloadState(
      total: totalSize,
      status: HttpDownloadStatus.connecting,
    );

    // 分工：notifier → SpeedCalculator → state.speed
    //       stream loop → state.downloaded, state.progress
    //       timer → 只读取 state 回调
    final notifier = ValueNotifier<int>(0);
    final speedCalc = SpeedCalculator(
      dataNotifier: notifier,
      updateCallback: (s) => state.speed = s,
    );

    Timer? periodicTimer;
    try {
      onStatus?.call(state);

      final response = await _dio!.get(
        url,
        options: Options(responseType: ResponseType.stream, headers: headers),
        cancelToken: cancelToken,
      );

      if (state.total <= 0) {
        state.total =
            int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      }

      state.status = HttpDownloadStatus.downloading;
      periodicTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        onStatus?.call(state);
      });

      await for (final chunk in (response.data as ResponseBody).stream) {
        if (cancelToken?.isCancelled == true) break;

        if (rateLimiter != null) {
          await rateLimiter.throttle(chunk.length);
        }

        file.writeAsBytesSync(chunk, mode: FileMode.append);
        state.downloaded += chunk.length;
        if (state.total > 0) state.progress = state.downloaded / state.total;
        notifier.value = state.downloaded;
      }

      periodicTimer.cancel();
      speedCalc.cancel();

      if (cancelToken?.isCancelled == true) {
        state.status = HttpDownloadStatus.cancelled;
        if (deleteOnError) await file.delete();
        onStatus?.call(state);
        return;
      }

      state.progress = 1.0;
      state.speed = 0;
      state.status = HttpDownloadStatus.completed;
      onStatus?.call(state);
    } on DioException catch (e) {
      periodicTimer?.cancel();
      speedCalc.cancel();
      if (cancelToken?.isCancelled == true || CancelToken.isCancel(e)) {
        state.status = HttpDownloadStatus.cancelled;
      } else {
        state.status = HttpDownloadStatus.failed;
        if (deleteOnError && await file.exists()) await file.delete();
      }
      onStatus?.call(state);
      rethrow;
    } catch (e) {
      periodicTimer?.cancel();
      speedCalc.cancel();
      state.status = HttpDownloadStatus.failed;
      if (deleteOnError && await file.exists()) await file.delete();
      onStatus?.call(state);
      rethrow;
    }
  }

  Future<void> _downloadChunked({
    required String url,
    required String savePath,
    required int totalSize,
    int chunkCount = 8,
    int? speedLimit,
    String? tempPath,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    HttpStatusCallback? onStatus,
    Map<String, String>? headers,
  }) async {
    if (totalSize < 2 * MB) {
      chunkCount = totalSize ~/ (500 * KB);
    } else {
      chunkCount = min(chunkCount, totalSize ~/ (2 * MB));
    }
    chunkCount = max(1, chunkCount);

    final chunkSize = totalSize ~/ chunkCount;
    tempPath ??= '$savePath.temp.';

    final List<_Chunk> chunks = [];
    for (int i = 0; i < chunkCount; i++) {
      final start = i * chunkSize;
      final end = i == chunkCount - 1 ? totalSize - 1 : (i + 1) * chunkSize - 1;
      final size = end - start + 1;
      final path = '$tempPath$i';
      final file = File(path);

      int received = 0;
      if (await file.exists()) {
        received = await file.length();
        if (received > size) {
          await file.delete();
          received = 0;
        }
      }

      final chunk = _Chunk(path, i, start + received, end, received, size);
      if (chunk.start > chunk.end) {
        chunk.status = HttpChunkStatus.complete;
      }
      chunks.add(chunk);
    }

    // HttpDownloadState 即缓存 —— 各部分各写各的，不冲突
    final state = HttpDownloadState(
      total: totalSize,
      chunkCount: chunkCount,
      status: HttpDownloadStatus.connecting,
    );

    // 分工：
    //   各分块 stream loop → state.downloaded (汇总), state.chunks[i].received, state.progress
    //   chunk 状态变更 → state.completedChunks, state.connectingChunks, state.chunks
    //   SpeedCalculator → state.speed
    //   Timer → 只读 state 回调
    final notifier = ValueNotifier<int>(0);
    final speedCalc = SpeedCalculator(
      dataNotifier: notifier,
      updateCallback: (s) => state.speed = s,
    );

    final periodicTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) {
      state.chunks = chunks
          .map(
            (c) => HttpChunkInfo(
              index: c.index,
              start: c.start,
              end: c.end,
              size: c.size,
              received: c.received,
              status: c.status,
            ),
          )
          .toList();
      onStatus?.call(state);
    });

    // 共享限速器 —— 所有分块共用，控制总速率
    final rateLimiter = speedLimit != null && speedLimit > 0
        ? _RateLimiter(speedLimit)
        : null;

    void refreshChunkStats() {
      state.downloaded = chunks.fold<int>(0, (s, c) => s + c.received);
      if (state.total > 0) state.progress = state.downloaded / state.total;
      state.completedChunks = chunks
          .where((c) => c.status == HttpChunkStatus.complete)
          .length;
      state.connectingChunks = chunks
          .where((c) => c.status == HttpChunkStatus.connecting)
          .length;
    }

    onStatus?.call(state);

    Future<bool> checkConnection(_Chunk chunk, {int tryTime = 0}) async {
      if (chunk.status == HttpChunkStatus.complete) return true;
      chunk.status = HttpChunkStatus.connecting;
      refreshChunkStats();
      final rangeHeader = {'Range': 'bytes=${chunk.start}-${chunk.end}'};
      try {
        final res = await _dio!.head(
          url,
          options: Options(headers: {...?headers, ...rangeHeader}),
          cancelToken: cancelToken,
        );
        if (res.statusCode == 206) {
          chunk.status = HttpChunkStatus.downloading;
          refreshChunkStats();
          return true;
        }
        throw DioException(requestOptions: RequestOptions());
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        if (tryTime < _maxRetries) {
          await Future.delayed(const Duration(milliseconds: 500));
          return checkConnection(chunk, tryTime: tryTime + 1);
        }
        return false;
      }
    }

    final connectionsOk = await Future.wait(
      chunks.map((c) => checkConnection(c)),
    );
    if (!connectionsOk.every((ok) => ok)) {
      periodicTimer.cancel();
      speedCalc.cancel();
      state.status = HttpDownloadStatus.failed;
      onStatus?.call(state);
      throw Exception('部分分块无法连接服务器');
    }

    state.status = HttpDownloadStatus.downloading;

    Future<void> downloadChunk(_Chunk chunk, {int tryTime = 0}) async {
      if (chunk.status == HttpChunkStatus.complete) return;
      final rangeHeader = {'Range': 'bytes=${chunk.start}-${chunk.end}'};

      try {
        final resp = await _dio!.get(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: {...?headers, ...rangeHeader},
          ),
          cancelToken: cancelToken,
        );

        final file = File(chunk.path);
        final sink = file.openWrite(mode: FileMode.append);

        await for (final data in (resp.data as ResponseBody).stream) {
          if (cancelToken?.isCancelled == true) {
            await sink.close();
            return;
          }

          if (rateLimiter != null) {
            await rateLimiter.throttle(data.length);
          }

          sink.add(data);
          //累计收到的字节数（含续传部分），避免每块重复打开文件句柄
          chunk.received += data.length;
          refreshChunkStats();
          notifier.value = state.downloaded;
        }

        await sink.close();
        chunk.status = HttpChunkStatus.complete;
        refreshChunkStats();
        notifier.value = state.downloaded;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        await Future.delayed(const Duration(milliseconds: 500));
        if (tryTime < _maxRetries) {
          await downloadChunk(chunk, tryTime: tryTime + 1);
        } else {
          chunk.status = HttpChunkStatus.failed;
          refreshChunkStats();
          throw Exception('分块 [${chunk.index}] 下载失败');
        }
      }
    }

    try {
      await Future.wait(chunks.map((c) => downloadChunk(c)), eagerError: true);

      periodicTimer.cancel();
      speedCalc.cancel();

      state.status = HttpDownloadStatus.merging;
      state.speed = 0;
      onStatus?.call(state);

      final file = File(savePath);
      final sink = file.openWrite();
      for (final chunk in chunks) {
        final tempFile = File(chunk.path);
        await sink.addStream(tempFile.openRead());
        await _deleteWithRetry(tempFile);
      }
      await sink.close();

      state.status = HttpDownloadStatus.completed;
      state.progress = 1.0;
      state.completedChunks = chunkCount;
      onStatus?.call(state);
    } on DioException {
      periodicTimer.cancel();
      speedCalc.cancel();
      if (deleteOnError) {
        for (final c in chunks) {
          await _deleteWithRetry(File(c.path));
        }
      }
      state.status = HttpDownloadStatus.failed;
      onStatus?.call(state);
      rethrow;
    } catch (_) {
      periodicTimer.cancel();
      speedCalc.cancel();
      if (deleteOnError) {
        for (final c in chunks) {
          await _deleteWithRetry(File(c.path));
        }
      }
      state.status = HttpDownloadStatus.failed;
      onStatus?.call(state);
      rethrow;
    }
  }

  ///删除临时文件并在被占用时短暂重试（Windows 下句柄释放是异步的）。
  Future<void> _deleteWithRetry(File file, {int maxTry = 10}) async {
    for (int i = 0; i < maxTry; i++) {
      try {
        if (await file.exists()) await file.delete();
        return;
      } on FileSystemException {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }
  }
}

class _Chunk {
  final int index;
  final int start;
  final int end;
  final int size;
  int received;
  final String path;
  HttpChunkStatus status;

  _Chunk(this.path, this.index, this.start, this.end, this.received, this.size)
    : status = HttpChunkStatus.pending;
}

/// 是否连接类失败（网络不通 / 代理不可用，属于「可重试」的网络问题）。
///
/// 与 404 这类「资源不存在」、403 这类「接口拒绝」区分开——UI 侧据此决定
/// 显示「网络问题（可重试）」还是「确实没有资源」
bool isNetworkFailure(DioException error) => switch (error.type) {
  DioExceptionType.connectionError ||
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout => true,
  _ => false,
};

/// 把响应体解成对象：已经是对象（dio 帮着解过）就原样返回，别再来一次 [jsonDecode]
///
/// 这个坑项目里踩过：dio 只在 content-type 是 JSON 时才帮解析，真 API 上已经解好，
/// 再 `jsonDecode` 会抛 `type 'List<dynamic>' is not a subtype of type 'String'`
@visibleForTesting
Object? decodeJsonBody(Object? data) =>
    data is String ? jsonDecode(data) : data;

/// 取 JSON 并解析成对象：**固定按纯文本取**，再自己解析
///
/// 不能拿 [cio] 返回的 data 直接当对象用：镜像节点回包常常不是 JSON content-type
/// （甚至是 HTML 错误页），此时 data 是 String，当对象用会抛
/// `type 'String' is not a subtype of type 'List<dynamic>?'`
Future<Object?> fetchJsonBody(String url, {Map<String, String>? headers}) async {
  final response = await cio.get<String>(
    url,
    headers: headers ?? const {'User-Agent': 'CopperLauncher'},
    responseType: ResponseType.plain,
  );
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}');
  }

  final raw = response.data ?? '';
  try {
    return decodeJsonBody(raw);
  } catch (_) {
    throw FormatException('响应不是 JSON：${previewResponseBody(raw)}');
  }
}

/// 异常信息里的响应预览：压成一行并截断，别把整页 HTML 打进日志
String previewResponseBody(String raw) {
  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 120 ? text : '${text.substring(0, 120)}…';
}
