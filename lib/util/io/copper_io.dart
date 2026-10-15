import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/github_mirror.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../math/speed_calculate.dart';

///dio 类型复导出：调用方只需 import 本文件即可同时获得类型（Response、
///CancelToken、Options、DioException…）与网络单例 [cio]
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
/// [Downloader]（多分块 task 下载），对外复刻 dio 的方法面
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
/// 通过 [applySettings] 同步，无需重启
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

  ///下载的停滞看门狗：单个连接这么久没有新字节就断掉，交给重试接管
  ///
  ///dio 在两次数据之间计时（`handleResponseStream`），所以这就是「时间戳 + 周期
  ///tick」的现成实现；全局 [_receiveTimeout] 的 600 秒是给普通 API 请求的宽限，
  ///下载沿用会让「连接活着却不发数据」白挂十分钟
  static const Duration _downloadIdleTimeout = Duration(seconds: 30);

  ///失败重试的退避区间：第 n 次等 random(0, min(cap, base * 2^n))，全抖动
  static const int _retryBackoffBaseMs = 500;
  static const int _retryBackoffCapMs = 5000;

  ///进度批量上报的门槛：累计这么多字节才做一次分块汇总与速率通知
  static const int _progressReportBytes = 256 * KB;

  ///动态并发的启用门槛：小文件爬坡的预热成本大于收益，走固定并发
  static const int _dynamicScaleMinSize = 32 * MB;

  ///扩容决策的采样窗口；窗口速率取最近 2 个的均值，抹掉块切换 / 慢启动的抖
  ///
  ///取 500ms 是为了「多块同时在跑」的那一段能采到样：块下得快时 1 秒的窗口
  ///会整段错过，慢块也就永远没得比；平滑只用 2 个窗口是为了跟扩容冷却期对齐
  ///（冷却期一过，窗口里就全是扩容之后的速率了）
  static const Duration _scaleSampleWindow = Duration(milliseconds: 500);

  ///单连接已到这个速率就认为带宽池充足，不再加连接
  static const double _sufficientBytesPerSecond = 1.5 * MB;

  ///扩容的最小增益：低于它说明带宽池已饱和，多加连接只是多开销
  static const double _scaleMinGain = 0.10;

  ///慢块判定：窗口速率低于「链路跑得到多快」这个经验基准的比例，且连续这么多窗口
  static const double _slowChunkRatio = 0.15;
  static const int _slowChunkStreak = 4;

  ///慢块拆出来的每半至少这么多字节，太短不值得拆
  static const int _minSplitBytes = 512 * KB;

  final Random _random = Random();

  String get userAgent => 'CopperLauncher/$appVersion';

  ///应用设置：token / 代理 / 下载默认值 / 镜像策略全部由**入参**提供，
  ///
  ///启动在 [initAppConfig] 之后调用；下载设置页每次改动 config 后也调用，
  ///保证新请求（含新开始的下载）即时生效
  void applySettings(Setting setting) {
    //trim 防止历史配置残留空白 token
    _githubToken = setting.githubToken.trim();
    _defaultSpeedLimitBytes = setting.downloadOptions.speedLimitBytes;
    _defaultChunkCount = setting.downloadOptions.maxTread;
    _mirrorStrategy = setting.mirrorOptions.strategy;

    applyProxySetting(setting.proxyOptions);
    GithubMirror.instance.applySettings(setting.mirrorOptions);
  }

  /// 当前镜像策略（供调试 / 测试查看）
  MirrorStrategy get mirrorStrategy => _mirrorStrategy;

  ///应用配置里的代理（跟随系统 / 自定义 / 关闭三种模式）
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
          // 镜像节点自己走直连
          if (GithubMirror.instance.isMirrorUrl(url.toString())) {
            return 'DIRECT';
          }
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

  ///自动 UA + github token 注入：请求自身没带对应头时才补
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

  ///按镜像策略决定 GitHub 请求走哪条路
  ///
  /// - [MirrorStrategy.githubFirst]（默认）：直连优先，网络类错误才回退镜像
  /// - [MirrorStrategy.mirrorFirst]：先走镜像，
  ///   失败再回退官方源
  /// - [MirrorStrategy.githubOnly]：只用官方源
  ///
  /// [preferRange] 给大文件下载用：挑镜像时优先支持 Range 的节点
  Future<R> _githubFallback<R>(
    String url,
    Future<R> Function(String effectiveUrl) send, {
    bool preferRange = false,
  }) async {
    if (!GithubMirror.isGithubUrl(url)) return send(url);

    switch (_mirrorStrategy) {
      case MirrorStrategy.githubOnly:
        return send(url);

      case MirrorStrategy.mirrorFirst:
        if (!GithubMirror.instance.enabled) return send(url);
        try {
          return await _sendViaMirror(url, send, preferRange: preferRange);
        } catch (e) {
          //镜像拿到真实 HTTP 响应（404 等）就原样抛出，别再回退直连：
          //否则「资源不存在」会被伪装成连接错误，且直连 raw 在部分网络注定失败
          if (e is DioException && !isTransportFailure(e)) rethrow;
          //镜像不可用 / 无可用节点 → 回退官方源兜底
          return send(url);
        }

      case MirrorStrategy.githubFirst:
        //直连这一族最近失败过（链路问题）就别再白等一次：直接走镜像；
        //窗口很短、只在内存里，直连成功或改设置即清（见 GithubMirror.shouldSkipDirect）
        final mirror = GithubMirror.instance;
        if (mirror.enabled && mirror.shouldSkipDirect(url)) {
          addLog(.debug, '直连最近失败过，这次先走镜像：$url', tag: 'Mirror');
          try {
            return await _sendViaMirror(url, send, preferRange: preferRange);
          } catch (e) {
            //镜像不可用 → 下面直连兜底；镜像拿到真实答复（404 等）仍原样抛
            if (e is DioException && !isTransportFailure(e)) rethrow;
          }
        } else if (mirror.enabled && !mirror.isDirectVerified(url)) {
          //这一族还没有结论：直连与镜像**同时探一次**，谁先答复谁赢 ——
          //网络好时只多一个往返，网络坏时省掉一次直连超时
          final isMirrorFaster = await _pickPathByProbe(url);
          if (isMirrorFaster == true) {
            try {
              return await _sendViaMirror(url, send, preferRange: preferRange);
            } catch (e) {
              if (e is DioException && !isTransportFailure(e)) rethrow;
            }
          }
        }
        try {
          final result = await send(url);
          mirror.markDirectOk(url);
          return result;
        } catch (e) {
          if (!_shouldFallbackToMirror(e, url)) rethrow;
          if (e is DioException && isTransportFailure(e)) {
            mirror.markDirectFailed(url);
          }
          addLog(
            .debug,
            '直连失败（${e is DioException ? e.type.name : e.runtimeType}），'
            '改走镜像：$url',
            tag: 'Mirror',
          );
          return _sendViaMirror(url, send, preferRange: preferRange);
        }
    }
  }

  ///并行探一次「直连还是镜像快」，只用探测结果决定走哪条路
  ///
  ///- true：镜像先答复（调用方走镜像）
  ///- false：直连先答复（调用方照旧走直连）
  ///- null：探不出结论（没有可用节点 / 两条都不答复）—— 交回原有的顺序回退
  ///
  ///探测只发 HEAD、不拉正文；结论写进短期记忆，这一族在窗口内就不必再探
  Future<bool?> _pickPathByProbe(String url) async {
    final mirror = GithubMirror.instance;
    var ranked = mirror.freshRankedFor(url);
    if (ranked.isEmpty) {
      try {
        ranked = await mirror.rankFamilyFor(url, preferRange: true);
      } catch (_) {
        return null;
      }
    }
    if (ranked.isEmpty) return null;

    final mirrorUrl = '${ranked.first}$url';
    final winner = await raceReachable([
      url,
      mirrorUrl,
    ], (candidate) => _probeReachable(candidate));
    if (winner == null) return null;

    final isMirrorFaster = winner == mirrorUrl;
    addLog(
      .debug,
      '并行探测：${isMirrorFaster ? '镜像' : '直连'}先答复，这次走'
      '${isMirrorFaster ? '镜像' : '直连'}：$url',
      tag: 'Mirror',
    );
    if (isMirrorFaster) {
      mirror.markDirectFailed(url);
    } else {
      mirror.markDirectOk(url);
    }
    return isMirrorFaster;
  }

  ///同时探几条路，先答复的那条赢；全都不答复返回 null
  ///
  ///输的那条不再理会：探针只是个 HEAD，dio 自己会按连接超时收口，不影响调用方
  @visibleForTesting
  Future<String?> raceReachable(
    List<String> candidates,
    Future<bool> Function(String candidate) probe,
  ) async {
    if (candidates.isEmpty) return null;
    final completer = Completer<String?>();
    var pending = candidates.length;

    for (final candidate in candidates) {
      unawaited(() async {
        var isReachable = false;
        try {
          isReachable = await probe(candidate);
        } catch (_) {
          isReachable = false;
        }
        if (completer.isCompleted) return;
        if (isReachable) {
          completer.complete(candidate);
        } else if (--pending == 0) {
          completer.complete(null);
        }
      }());
    }

    return completer.future;
  }

  ///这条路通不通：发个 HEAD，**只要有 HTTP 答复就算通**（404 / 405 也说明链路是好的）
  Future<bool> _probeReachable(String url) async {
    _ensureInit();
    try {
      await _dio!.head(url, options: Options(validateStatus: (_) => true));
      return true;
    } on DioException {
      return false;
    }
  }

  /// 一次请求最多试几个节点：排名表可能很长，前几个都不通就直接回退直连
  static const _maxMirrorAttempts = 3;

  ///经镜像发一次请求：取该族的排名表（TTL 内直接用，过期才重测）顺着往下试
  ///
  ///节点级失败（连不上 / 403 / 429 / 5xx）就换下一个节点；404 这类「资源不存在」
  ///是上游真实答复，换节点也一样，直接抛出。全部节点都失败时抛
  ///[MirrorUnavailable]（不是 DioException），让 [_githubFallback] 回退直连
  Future<R> _sendViaMirror<R>(
    String url,
    Future<R> Function(String effectiveUrl) send, {
    bool preferRange = false,
  }) async {
    final mirror = GithubMirror.instance;
    if (!mirror.enabled) throw StateError('镜像未启用');

    var ranked = mirror.freshRankedFor(url);
    final isFromCache = ranked.isNotEmpty;
    if (ranked.isEmpty) {
      ranked = await mirror.rankFamilyFor(url, preferRange: preferRange);
    }
    if (ranked.isEmpty) throw StateError('无可用镜像节点');

    Object? lastError;
    for (final prefix in ranked.take(_maxMirrorAttempts)) {
      addLog(
        .debug,
        '镜像${isFromCache ? '用缓存' : '新测速'}：$prefix（目标 $url）',
        tag: 'Mirror',
      );
      try {
        final result = await send('$prefix$url');
        mirror.promoteMirror(url, prefix);
        return result;
      } catch (error) {
        if (error is DioException && !isMirrorNodeFailure(error)) rethrow;
        lastError = error;
        mirror.demoteMirror(url, prefix);
        addLog(
          .debug,
          '镜像节点失败：$prefix（${mirrorFailureReason(error)}），换下一个',
          tag: 'Mirror',
        );
      }
    }
    throw MirrorUnavailable(lastError);
  }

  ///是否值得回退镜像：网络类错误一律回退；GitHub 的 401/403（空/失效 token、
  ///匿名限流）也回退——镜像请求不带 token，换 IP 常能绕过
  bool _shouldFallbackToMirror(Object error, String url) {
    if (error is! DioException) return false;
    if (isTransportFailure(error)) return true;
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

  ///系统代理缓存的保鲜期：过期后请求路径会触发后台重检；
  ///否则代理软件开关后，注册表里已变化的代理会被一直使用
  static const _systemProxyTtl = Duration(seconds: 30);

  ///异步检测 Windows 系统代理并缓存结果
  ///
  ///`reg` 是进程调用，不能在请求路径同步执行——否则每个连接都
  ///`Process.runSync` 阻塞主 isolate 导致 UI 卡顿；启动时检测一次，
  ///缓存过期（[_systemProxyTtl]）后由请求路径再次触发，保证代理软件
  ///开关后注册表的变化能在保鲜期之内被感知
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

  ///从 `reg query` 输出解析系统代理
  ///
  ///必须同时满足 `ProxyEnable = 1` 才启用，否则即使 `ProxyServer` 残留历史值
  ///（关停的代理软件常留下 `127.0.0.1:<port>`）也视为无代理，避免把已关闭的
  ///代理当成有效路由导致请求全部被拒
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

  ///切换为跟随系统代理（取消自定义 / 关闭状态）
  void clearProxy() {
    _proxyHost = null;
    _proxyPort = null;
    _proxyUsername = null;
    _proxyPassword = null;
    _proxyOff = false;
    _recreateClient();
  }

  ///设置自定义代理
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

  ///显式关闭代理（直连）
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
    return _githubFallback(
      url,
      (effectiveUrl) => _dio!.get<T>(
        effectiveUrl,
        options: Options(headers: headers, responseType: responseType),
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      ),
    );
  }

  Future<Response<T>> getUri<T>(
    Uri uri, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) async {
    _ensureInit();
    return _githubFallback(
      uri.toString(),
      (effectiveUrl) => _dio!.getUri<T>(
        Uri.parse(effectiveUrl),
        options: Options(headers: headers, responseType: responseType),
        cancelToken: cancelToken,
      ),
    );
  }

  Future<Response> head(
    String url, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    _ensureInit();
    return _githubFallback(
      url,
      (effectiveUrl) => _dio!.head(
        effectiveUrl,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      ),
    );
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
    return _githubFallback(
      url,
      (effectiveUrl) => _dio!.post<T>(
        effectiveUrl,
        data: data,
        options: Options(headers: headers, responseType: responseType),
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      ),
    );
  }

  ///上传字节（云存档把 zip 传上去走这里）：[onSendProgress] 报发送进度
  Future<Response<T>> put<T>(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
    ProgressCallback? onSendProgress,
  }) => _sendVerb<T>(
    'PUT',
    url,
    data: data,
    headers: headers,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
    responseType: responseType,
    onSendProgress: onSendProgress,
  );

  ///局部更新（云存档的槽位改名、快照固定走这里）
  Future<Response<T>> patch<T>(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) => _sendVerb<T>(
    'PATCH',
    url,
    data: data,
    headers: headers,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
    responseType: responseType,
  );

  ///删除（云存档的删槽位 / 删快照走这里）
  Future<Response<T>> delete<T>(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) => _sendVerb<T>(
    'DELETE',
    url,
    data: data,
    headers: headers,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
    responseType: responseType,
  );

  ///PUT / PATCH / DELETE 共用：dio 的这三个动词只差一个 method 名，
  ///收敛到一处，不写三段几乎相同的样板
  Future<Response<T>> _sendVerb<T>(
    String method,
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
    ProgressCallback? onSendProgress,
  }) async {
    _ensureInit();
    return _githubFallback(
      url,
      (effectiveUrl) => _dio!.request<T>(
        effectiveUrl,
        data: data,
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
        ),
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      ),
    );
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

  ///重试前的等待：指数退避 + 全抖动
  ///
  ///固定间隔会让同时失败的多个分块在同一时刻重试（惊群）；封顶则保证长断网时
  ///重试间隔不会无限拉长
  Duration _retryDelay(int attempt) {
    final ceilingMs = min(_retryBackoffCapMs, _retryBackoffBaseMs << attempt);
    return Duration(milliseconds: _random.nextInt(ceilingMs + 1));
  }

  ///统一分块下载：能拿到大小且服务端支持 Range 且足够大 → 多分块并发
  ///（临时分块可断点续传）；否则退化为单流下载
  ///
  ///[speedLimit] / [chunkCount] 不传时使用 config 默认值；speedLimit<=0 表示不限速；
  ///进度通过 [onStatus] 持续回调 [HttpDownloadState]（含分块明细）
  ///
  ///官方直连失败（网络类错误）时自动回退到最优镜像重试一次
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
    //每次调用的重试上限只作用于这次下载：早先是直接写单例字段，
    //一次传了 maxRetries 会把之后所有下载与请求的上限一起改掉
    final retryLimit = maxRetries ?? _maxRetries;
    addLog(
      .debug,
      '开始下载：$url → $savePath'
      '（镜像策略 ${_mirrorStrategy.name}，重试上限 $retryLimit）',
      tag: 'Download',
    );
    await _githubFallback(
      url,
      (effectiveUrl) => _downloadOnce(
        url: effectiveUrl,
        savePath: savePath,
        speedLimit: speedLimit,
        chunkCount: chunkCount,
        tempPath: tempPath,
        retryLimit: retryLimit,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        onStatus: onStatus,
        headers: headers,
      ),
      //下载优先找支持 Range 的节点：能分块并发 + 断点续传
      preferRange: true,
    );
  }

  Future<void> _downloadOnce({
    required String url,
    required String savePath,
    int? speedLimit,
    int? chunkCount,
    String? tempPath,
    int retryLimit = 5,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    HttpStatusCallback? onStatus,
    Map<String, String>? headers,
  }) async {
    final effectiveSpeedLimit = speedLimit ?? _defaultSpeedLimitBytes;
    final effectiveChunkCount = max(1, chunkCount ?? _defaultChunkCount);

    // HEAD 只为探大小 / Range 支持，失败不该让整个下载失败：有些站点不允许 HEAD，会返回 405；
    // 此时退化为单流，大小改由 GET 响应头补齐（见 _downloadSingleStream）
    var totalSize = 0;
    var rangeSupported = false;
    String? etag;
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
      //续传/重试带 If-Range 用：源一变服务器就回整包，避免新旧数据拼在一起
      etag = headResp.headers.value('etag');
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
        retryLimit: retryLimit,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        onStatus: onStatus,
        headers: headers,
      );
      return;
    }

    await _downloadChunkedWithFallback(
      url: url,
      savePath: savePath,
      totalSize: totalSize,
      chunkCount: effectiveChunkCount,
      speedLimit: effectiveSpeedLimit,
      tempPath: tempPath,
      etag: etag,
      retryLimit: retryLimit,
      cancelToken: cancelToken,
      deleteOnError: deleteOnError,
      onStatus: onStatus,
      headers: headers,
    );
  }

  ///走分块并发；服务端忽略 Range 时退化为单流整包
  ///
  ///「HEAD 广播 Accept-Ranges、带 Range 的 GET 却回 200」在代理 / 网关上并不罕见，
  ///那种响应不能往分块区间里写，只能整包重下
  Future<void> _downloadChunkedWithFallback({
    required String url,
    required String savePath,
    required int totalSize,
    required int chunkCount,
    int? speedLimit,
    String? tempPath,
    String? etag,
    int retryLimit = 5,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    HttpStatusCallback? onStatus,
    Map<String, String>? headers,
  }) async {
    try {
      await _downloadChunked(
        url: url,
        savePath: savePath,
        totalSize: totalSize,
        chunkCount: chunkCount,
        speedLimit: speedLimit,
        tempPath: tempPath,
        etag: etag,
        retryLimit: retryLimit,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        onStatus: onStatus,
        headers: headers,
      );
    } on _RangeIgnored {
      addLog(
        .debug,
        '服务端忽略 Range（带 Range 的 GET 回了整包），退化为单流下载：$url',
        tag: 'Download',
      );
      await _downloadSingleStream(
        url: url,
        savePath: savePath,
        totalSize: totalSize,
        speedLimit: speedLimit,
        retryLimit: retryLimit,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        onStatus: onStatus,
        headers: headers,
      );
    }
  }

  ///单流下载：整份顺序写，中途断流就带 `Range` 试着接着下
  ///
  ///无 Range 的站点（只认 GET 的接口、把 Range 裁掉的网关）也要扛得住弱网：
  ///不能一断就整单失败。服务器不认 Range（回 200 而不是 206）时整份重来
  Future<void> _downloadSingleStream({
    required String url,
    required String savePath,
    required int totalSize,
    int? speedLimit,
    int retryLimit = 5,
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

      //重试之间 state 一直留着：不来回切 failed / connecting，界面不闪
      for (var attempt = 0; ; attempt++) {
        IOSink? sink;
        try {
          final resumeFrom = state.downloaded;
          final response = await _dio!.get(
            url,
            options: Options(
              responseType: ResponseType.stream,
              //停滞看门狗：两次数据之间超过它没字节，dio 就断掉这条连接
              receiveTimeout: _downloadIdleTimeout,
              headers: {
                ...?headers,
                //已经下过一段就按续传问一次；服务器不认（回 200）下面会整份重写
                if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
              },
            ),
            cancelToken: cancelToken,
          );

          if (state.total <= 0) {
            state.total =
                int.tryParse(
                  response.headers.value('content-length') ?? '0',
                ) ??
                0;
          }

          //续传请求只有真回了 206 才能接着写；回 200 说明整包重发过来了
          final isPartial = response.statusCode == 206;
          if (resumeFrom > 0 && !isPartial) {
            state.downloaded = 0;
            notifier.value = 0;
          }

          state.status = HttpDownloadStatus.downloading;
          periodicTimer ??= Timer.periodic(const Duration(milliseconds: 100), (
            _,
          ) {
            onStatus?.call(state);
          });

          //续上了就 append（保住已下那段），否则 truncate 整份重写
          sink = file.openWrite(
            mode: resumeFrom > 0 && isPartial
                ? FileMode.append
                : FileMode.write,
          );
          await for (final chunk in (response.data as ResponseBody).stream) {
            if (cancelToken?.isCancelled == true) break;

            if (rateLimiter != null) {
              await rateLimiter.throttle(chunk.length);
            }

            sink.add(chunk);
            state.downloaded += chunk.length;
            if (state.total > 0) {
              state.progress = state.downloaded / state.total;
            }
            notifier.value = state.downloaded;
          }

          await sink.flush();
          await sink.close();
          sink = null;

          if (cancelToken?.isCancelled == true) {
            state.status = HttpDownloadStatus.cancelled;
            if (deleteOnError) await file.delete();
            onStatus?.call(state);
            return;
          }

          //知道总长就必须下满：短了说明对端提前收了连接，放任成功就是静默缺数据
          if (state.total > 0 && state.downloaded < state.total) {
            throw HttpException(
              '单流下载提前结束（${state.downloaded}/${state.total} 字节）',
            );
          }

          state.progress = 1.0;
          state.speed = 0;
          state.status = HttpDownloadStatus.completed;
          onStatus?.call(state);
          addLog(
            .debug,
            '单流下载完成：$savePath（${state.downloaded} 字节）',
            tag: 'Download',
          );
          return;
        } catch (e) {
          await sink?.close();
          sink = null;

          if (cancelToken?.isCancelled == true ||
              (e is DioException && CancelToken.isCancel(e))) {
            state.status = HttpDownloadStatus.cancelled;
            if (deleteOnError && await file.exists()) await file.delete();
            onStatus?.call(state);
            return;
          }

          //读到一半被掐断时 dio 把原始错误直接抛给流，不是 DioException
          final isTransport = e is! DioException || isTransportFailure(e);
          // 断网时不再空转多轮：连接类失败只再试一次；其它错误（服务端抖动等）按上限重试
          final limit = isTransport ? 1 : retryLimit;
          if (attempt < limit) {
            final reason = e is DioException
                ? e.type.name
                : e.runtimeType.toString();
            final delay = _retryDelay(attempt);
            addLog(
              .debug,
              '单流下载中断（$reason），${delay.inMilliseconds}ms 后接着下'
              '（已收 ${state.downloaded} 字节）',
              tag: 'Download',
            );
            await Future.delayed(delay);
            continue;
          }

          state.status = HttpDownloadStatus.failed;
          if (deleteOnError && await file.exists()) await file.delete();
          onStatus?.call(state);
          addLog(
            .error,
            '单流下载失败：${e is DioException ? e.type.name : e}'
            '${e is DioException && isNetworkFailure(e) ? '（网络不通或代理不可用）' : ''}'
            '（$url）',
            tag: 'Download',
          );
          rethrow;
        }
      }
    } finally {
      periodicTimer?.cancel();
      speedCalc.cancel();
    }
  }

  ///分块并发下载：各块**直接写进同一个 `.part` 文件的自己那段区间**
  ///
  ///不再「每块一个临时文件 + 收尾合并」：省掉收尾那整轮读一遍写一遍与 2× 磁盘
  ///占用，慢块拆分也只是改区间。续传现场在 `.part.json`（区间 + 已收字节 + ETag），
  ///下完把 `.part` 改名成 [savePath]
  Future<void> _downloadChunked({
    required String url,
    required String savePath,
    required int totalSize,
    int chunkCount = 8,
    int? speedLimit,
    String? tempPath,
    String? etag,
    int retryLimit = 5,
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

    final partialPath = tempPath ?? '$savePath.part';
    final metaPath = '$partialPath.json';
    final partialFile = File(partialPath);

    final chunks = await _planChunks(
      partialFile: partialFile,
      metaPath: metaPath,
      url: url,
      totalSize: totalSize,
      chunkCount: chunkCount,
      etag: etag,
    );

    // 续传信息对排查很有用：现场还在就有多少接着下
    final resumedChunks = chunks.where((c) => c.received > 0).length;
    final resumedBytes = chunks.fold<int>(0, (sum, c) => sum + c.received);
    addLog(
      .debug,
      '分块准备：${chunks.length} 个（总 $totalSize 字节），'
      '续传 $resumedChunks 个 / $resumedBytes 字节',
      tag: 'Download',
    );

    // HttpDownloadState 即缓存 —— 各部分各写各的，不冲突
    final state = HttpDownloadState(
      total: totalSize,
      chunkCount: chunks.length,
      status: HttpDownloadStatus.connecting,
    );

    // 分工：
    //   各分块 stream loop → state.downloaded (汇总), state.received, state.progress
    //   chunk 状态变更 → state.completedChunks, state.connectingChunks, state.chunks
    //   SpeedCalculator → state.speed
    //   Timer → 只读 state 回调
    final notifier = ValueNotifier<int>(0);
    final speedCalc = SpeedCalculator(
      dataNotifier: notifier,
      updateCallback: (s) => state.speed = s,
    );

    //内部中止令牌：判定「服务端忽略 Range」时用它把其余分块立刻收掉
    //（只靠标志位的话，停滞中的分块要等到看门狗超时才收手）；用户取消原样传导
    final abortToken = CancelToken();
    if (cancelToken != null) {
      unawaited(cancelToken.whenCancel.then((_) => abortToken.cancel()));
    }

    // 服务端是否忽略 Range（回整包 200）：一旦判定，其余分块立即收手，
    // 由 _downloadChunkedWithFallback 退化为单流整包重下
    var rangeIgnored = false;

    var lastMetaAt = DateTime.now();
    var lastMetaBytes = -1;
    var metaWriting = false;

    ///把续传现场写进元数据：块完成时、以及下载中每 2 秒一次
    Future<void> saveMeta() async {
      if (metaWriting) return;
      metaWriting = true;
      try {
        await File(metaPath).writeAsString(
          jsonEncode({
            'url': url,
            'total': totalSize,
            'etag': etag,
            'chunks': [
              for (final c in chunks)
                {'start': c.start, 'end': c.end, 'received': c.received},
            ],
          }),
          flush: true,
        );
        lastMetaAt = DateTime.now();
        lastMetaBytes = state.downloaded;
      } catch (_) {
        //写不进元数据不影响这次下载，只是下次续传要从零开始
      } finally {
        metaWriting = false;
      }
    }

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
      //续传要扛得住进程被杀（安卓上很常见）：下载途中也定期落一次进度
      if (DateTime.now().difference(lastMetaAt) >= const Duration(seconds: 2) &&
          state.downloaded != lastMetaBytes) {
        unawaited(saveMeta());
      }
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

    //自适应调度：worker 池取「剩余最大」的块（快 worker 自然多干）；
    //≥32MB 的文件先只开 1 个连接探带宽，按增益扩容；明显慢的块拆一半让出去
    final maxWorkers = chunks.length;
    final dynamicScale = maxWorkers > 1 && totalSize >= _dynamicScaleMinSize;
    var activeWorkers = 0;
    var scaleSaturated = !dynamicScale;
    var lastScaleRate = 0.0;
    var scaleCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
    final recentRates = <double>[];
    var lastSampleBytes = 0;
    var lastSampleAt = DateTime.now();
    final finished = Completer<void>();
    final workerFutures = <Future<void>>[];

    Future<void> downloadPiece(_Chunk chunk, {int tryTime = 0}) async {
      if (rangeIgnored) return;

      //请求区间从 nextOffset 起：续传与重试都接着已落盘的位置，已收的部分不重下
      final rangeHeader = {
        'Range': 'bytes=${chunk.nextOffset}-${chunk.end}',
        //源变了就让服务器回整包（200），走「忽略 Range」那条路整份重下
        if (etag != null && etag.isNotEmpty) 'If-Range': etag,
      };
      //只在首次尝试标「连接中」：重试途中保持原状态，免得界面在「分块明细」与
      //「分块连接中」之间来回跳
      if (tryTime == 0) {
        chunk.status = HttpChunkStatus.connecting;
        refreshChunkStats();
      }

      RandomAccessFile? raf;
      try {
        final resp = await _dio!.get(
          url,
          options: Options(
            responseType: ResponseType.stream,
            //停滞看门狗：两次数据之间超过它没字节，dio 就断掉这条连接
            receiveTimeout: _downloadIdleTimeout,
            headers: {...?headers, ...rangeHeader},
          ),
          cancelToken: abortToken,
        );

        //带 Range 只认 206：回 200 说明服务端没看 Range（或源已变），
        //整包写进这一段区间只会拼出错文件
        if (resp.statusCode != 206) {
          rangeIgnored = true;
          abortToken.cancel();
          throw _RangeIgnored();
        }

        chunk.status = HttpChunkStatus.downloading;
        refreshChunkStats();

        //每块独占一个句柄，块内偏移连续递增：只在首个数据包定位一次
        //
        //必须是 writeOnlyAppend：[FileMode.writeOnly] 打开就把文件截断，
        //会把预分配的 `.part` 清成 0；append 模式只是把位置摆到末尾，
        //setPosition 照常生效（本机实测：两个句柄各写各的区间互不干扰）
        raf = await partialFile.open(mode: FileMode.writeOnlyAppend);
        await raf.setPosition(chunk.nextOffset);
        var writeOffset = chunk.nextOffset;
        var pendingReport = 0;

        await for (final data in (resp.data as ResponseBody).stream) {
          if (data.isEmpty) continue;
          if (cancelToken?.isCancelled == true || rangeIgnored) return;

          //块级边界裁剪：区间被拆小之后，在途连接多发的数据必须丢掉
          final allowed = chunk.end + 1 - writeOffset;
          if (allowed <= 0) break;
          final piece = data.length > allowed ? data.sublist(0, allowed) : data;

          if (rateLimiter != null) {
            await rateLimiter.throttle(piece.length);
          }

          await raf.writeFrom(piece);
          writeOffset += piece.length;
          //累计收到的字节数（含续传部分）；进度逐包更新才跟手，
          //分块汇总与速率通知按批做（见 _progressReportBytes）
          chunk.received += piece.length;
          chunk.nextOffset = writeOffset;
          state.downloaded += piece.length;
          if (state.total > 0) state.progress = state.downloaded / state.total;
          pendingReport += piece.length;
          if (pendingReport >= _progressReportBytes) {
            pendingReport = 0;
            refreshChunkStats();
            notifier.value = state.downloaded;
          }

          //下满即成功：服务器可能发完还拖着连接（黑洞 / keep-alive），
          //等流自然结束会白等一个看门狗周期
          if (chunk.nextOffset > chunk.end) break;
        }

        //没下满就收尾：预分配的 `.part` 里那一段还是 0，放任成功就是静默损坏
        if (chunk.nextOffset <= chunk.end) {
          throw HttpException('分块 ${chunk.index + 1} 提前结束');
        }

        chunk.status = HttpChunkStatus.complete;
        refreshChunkStats();
        notifier.value = state.downloaded;
        await saveMeta();
      } on _RangeIgnored {
        rethrow;
      } catch (e) {
        //用户取消照旧往外抛
        if (cancelToken?.isCancelled == true ||
            (e is DioException && CancelToken.isCancel(e))) {
          rethrow;
        }
        //读到一半被对端掐断时，dio 把原始错误（HttpException）直接抛给响应体流，
        //不是 DioException —— 那同样是弱网断连，要按一样的退避重试接着下
        final isTransport = e is! DioException || isTransportFailure(e);
        // 断网时不再空转多轮：连接类失败只再试一次；其它错误（服务端抖动等）按上限重试
        final limit = isTransport ? 1 : retryLimit;
        if (tryTime < limit) {
          await Future.delayed(_retryDelay(tryTime));
          await downloadPiece(chunk, tryTime: tryTime + 1);
        } else {
          final reason = e is DioException
              ? e.type.name
              : e.runtimeType.toString();
          chunk.status = HttpChunkStatus.failed;
          refreshChunkStats();
          addLog(
            .error,
            '分块 ${chunk.index + 1} 下载失败：$reason'
            '（已收 ${chunk.received}/${chunk.size} 字节）',
            tag: 'Download',
          );
          throw Exception('分块 [${chunk.index}] 下载失败');
        }
      } finally {
        await raf?.close();
      }
    }

    var healthyRate = 0.0;
    ///没有活干的 worker 在这里等新块（拆分出来的尾部）或整单收尾
    var waitingWorkers = <Completer<void>>[];

    void notifyWork() {
      final waiters = waitingWorkers;
      waitingWorkers = [];
      for (final waiter in waiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }

    _Chunk? claimNext() {
      if (finished.isCompleted || rangeIgnored) return null;
      if (cancelToken?.isCancelled == true) return null;
      _Chunk? best;
      for (final chunk in chunks) {
        if (chunk.claimed || chunk.remaining <= 0) continue;
        if (best == null || chunk.remaining > best.remaining) best = chunk;
      }
      best?.claimed = true;
      return best;
    }

    ///一个 worker：领块 → 下完 → 再领；暂时没活就挂着等，别退出
    ///
    ///不能「没活就退」：慢块拖到后期时其它 worker 早退了，拆分出来的尾部会没人接
    Future<void> workerLoop() async {
      try {
        while (!finished.isCompleted) {
          final chunk = claimNext();
          if (chunk == null) {
            if (rangeIgnored || cancelToken?.isCancelled == true) return;
            final waiter = Completer<void>();
            waitingWorkers.add(waiter);
            await Future.any([waiter.future, finished.future]);
            continue;
          }

          final startedAt = DateTime.now();
          final bytesBefore = chunk.received;
          await downloadPiece(chunk);

          //块下完时的整体速率也是「链路能有多快」的样本（窗口采样可能整段错过）
          final seconds =
              DateTime.now().difference(startedAt).inMilliseconds / 1000;
          final downloaded = chunk.received - bytesBefore;
          if (chunk.status == HttpChunkStatus.complete &&
              seconds > 0 &&
              downloaded >= 256 * KB) {
            final rate = downloaded / seconds;
            if (rate > healthyRate) healthyRate = rate;
          }

          //只有每块都真的下满才算完成：判定「忽略 Range」时兄弟块是提前收手的
          if (!rangeIgnored &&
              chunks.every((c) => c.status == HttpChunkStatus.complete) &&
              !finished.isCompleted) {
            finished.complete();
          }
        }
      } catch (error, stack) {
        if (!finished.isCompleted) finished.completeError(error, stack);
      }
    }

    void spawnWorker() {
      activeWorkers++;
      workerFutures.add(workerLoop());
    }

    ///慢块让出尾部：本块收缩到 [start, mid]，新块接管 [mid+1, end]
    void splitChunk(_Chunk chunk) {
      final remaining = chunk.remaining;
      if (remaining < _minSplitBytes * 2) return;

      final mid = chunk.nextOffset + remaining ~/ 2;
      final tail = _Chunk(chunks.length, mid, chunk.end, chunk.end - mid + 1, 0);
      chunk.end = mid - 1;
      chunk.size = chunk.end - chunk.start + 1;
      chunk.slowStreak = 0;
      chunks.add(tail);
      refreshChunkStats();
      state.chunkCount = chunks.length;
      notifyWork();
      addLog(
        .debug,
        '分块 ${chunk.index + 1} 明显慢于其它块，把尾部 ${tail.index + 1} 让出去',
        tag: 'Download',
      );
    }

    ///每个采样窗口看一遍：在跑的块里谁明显慢
    ///
    ///基准取「链路跑得到多快」的经验值（窗口最高速率 + 已完成块的整体速率），
    ///不取「其它块的中位数」——后者在尾部阶段只有慢块自己，反而永远拆不了，
    ///而尾部正是最该拆的时候
    void splitSlowChunks(double elapsedSeconds) {
      final inFlight = chunks
          .where((c) => c.status == HttpChunkStatus.downloading)
          .toList();
      if (inFlight.isEmpty) return;

      final rates = <_Chunk, double>{};
      for (final chunk in inFlight) {
        rates[chunk] = (chunk.received - chunk.sampledBytes) / elapsedSeconds;
        chunk.sampledBytes = chunk.received;
      }
      for (final rate in rates.values) {
        if (rate > healthyRate) healthyRate = rate;
      }
      if (healthyRate <= 0) return;

      for (final entry in rates.entries) {
        final chunk = entry.key;
        if (entry.value < healthyRate * _slowChunkRatio) {
          chunk.slowStreak++;
        } else {
          chunk.slowStreak = 0;
        }
        if (chunk.slowStreak >= _slowChunkStreak) {
          chunk.slowStreak = 0;
          splitChunk(chunk);
        }
      }
    }

    ///扩容决策：单连接够快就停；上一轮扩容没换来 ≥10% 增益也停
    void scaleIfNeeded(double smoothedRate) {
      if (scaleSaturated || activeWorkers >= maxWorkers) return;
      //刚扩过就先等平滑窗口换过一批：否则「上一轮的增益」里还混着扩容前的
      //低速率（启动期尤其明显），会被假增益一路推着把连接开满
      if (DateTime.now().isBefore(scaleCooldownUntil)) return;

      //「带宽充足」只看**探带宽那一条连接**的速率，不能拿聚合速率比：
      //每条连接都慢的弱网里，聚合会先越过阈值 ⇒ 档位提前停住，正好少开连接；
      //爬坡阶段交给下面的增益判据（多一条连接没换来 10% 才算饱和）
      if (activeWorkers <= 1 && smoothedRate >= _sufficientBytesPerSecond) {
        scaleSaturated = true;
        addLog(
          .debug,
          '单连接已 ${(smoothedRate / MB).toStringAsFixed(1)}MB/s，带宽充足不再扩容',
          tag: 'Download',
        );
        return;
      }
      if (lastScaleRate == 0 || smoothedRate >= lastScaleRate * (1 + _scaleMinGain)) {
        lastScaleRate = smoothedRate;
        scaleCooldownUntil = DateTime.now().add(_scaleSampleWindow * 2);
        spawnWorker();
        addLog(
          .debug,
          '扩到 $activeWorkers 个连接（平滑速率 '
          '${(smoothedRate / MB).toStringAsFixed(1)}MB/s）',
          tag: 'Download',
        );
      } else {
        scaleSaturated = true;
        addLog(
          .debug,
          '扩容增益不足（${(smoothedRate / MB).toStringAsFixed(1)}MB/s），'
          '判定带宽池饱和，停在 $activeWorkers 个连接',
          tag: 'Download',
        );
      }
    }

    final sampleTimer = Timer.periodic(_scaleSampleWindow, (_) {
      final now = DateTime.now();
      final elapsed = now.difference(lastSampleAt).inMilliseconds / 1000;
      if (elapsed <= 0) return;

      final rate = (state.downloaded - lastSampleBytes) / elapsed;
      lastSampleBytes = state.downloaded;
      lastSampleAt = now;

      recentRates.add(rate);
      if (recentRates.length > 2) recentRates.removeAt(0);
      final smoothed =
          recentRates.reduce((a, b) => a + b) / recentRates.length;

      if (state.downloaded < totalSize) splitSlowChunks(elapsed);
      scaleIfNeeded(smoothed);
    });

    ///失败收尾：按 [deleteOnError] 决定清掉续传现场还是保住进度
    Future<void> finishFailed() async {
      if (deleteOnError) {
        await _cleanupPartial(partialFile, metaPath);
      } else {
        await saveMeta();
      }
      state.status = HttpDownloadStatus.failed;
      onStatus?.call(state);
    }

    try {
      state.status = HttpDownloadStatus.downloading;
      //固定并发就一次开满；大文件先开 1 个探带宽，后面按增益加
      final initialWorkers = dynamicScale ? 1 : maxWorkers;
      for (var i = 0; i < initialWorkers; i++) {
        spawnWorker();
      }

      await finished.future;
      //等所有 worker 收手再收尾：可能还有 worker 正占着 `.part` 的句柄
      await Future.wait(workerFutures);

      periodicTimer.cancel();
      speedCalc.cancel();
      sampleTimer.cancel();

      state.status = HttpDownloadStatus.merging;
      state.speed = 0;
      onStatus?.call(state);

      //收尾：`.part` 改名成目标文件，续传现场作废（改名是元数据操作，不搬字节）
      final target = File(savePath);
      if (await target.exists()) await _deleteWithRetry(target);
      await partialFile.rename(savePath);
      await _deleteQuietly(File(metaPath));

      state.status = HttpDownloadStatus.completed;
      state.progress = 1.0;
      state.completedChunks = chunks.length;
      onStatus?.call(state);
      addLog(
        .debug,
        '分块下载完成：${chunks.length} 个分块 → $savePath'
        '（${state.downloaded} 字节）',
        tag: 'Download',
      );
    } on _RangeIgnored {
      //换个下载形态重来，不算失败：`.part` 与元数据一律清掉，单流会整份重写
      periodicTimer.cancel();
      speedCalc.cancel();
      sampleTimer.cancel();
      await Future.wait(workerFutures);
      await _cleanupPartial(partialFile, metaPath);
      rethrow;
    } on DioException {
      periodicTimer.cancel();
      speedCalc.cancel();
      sampleTimer.cancel();
      await Future.wait(workerFutures);
      await finishFailed();
      rethrow;
    } catch (_) {
      periodicTimer.cancel();
      speedCalc.cancel();
      sampleTimer.cancel();
      await Future.wait(workerFutures);
      await finishFailed();
      rethrow;
    }
  }

  ///规划分块：能从 `.part.json` 恢复就恢复已下部分，否则清掉现场从零开始
  ///
  ///新现场会把 `.part` 预分配到全量长度，所以「文件长度 == 总大小」是续传的
  ///前提之一；元数据对不上（源变了 / 区间拼不满 / 文件被删过）就当没有，重下
  Future<List<_Chunk>> _planChunks({
    required File partialFile,
    required String metaPath,
    required String url,
    required int totalSize,
    required int chunkCount,
    required String? etag,
  }) async {
    final resumed = await _readResumeMeta(
      partialFile: partialFile,
      metaPath: metaPath,
      url: url,
      totalSize: totalSize,
      etag: etag,
    );
    if (resumed != null) return resumed;

    await _cleanupPartial(partialFile, metaPath);

    final raf = await partialFile.open(mode: FileMode.write);
    await raf.truncate(totalSize);
    await raf.close();

    final chunkSize = totalSize ~/ chunkCount;
    final chunks = <_Chunk>[];
    for (var i = 0; i < chunkCount; i++) {
      final start = i * chunkSize;
      final end = i == chunkCount - 1 ? totalSize - 1 : (i + 1) * chunkSize - 1;
      chunks.add(_Chunk(i, start, end, end - start + 1, 0));
    }
    return chunks;
  }

  ///读续传元数据；不可用（没有 / 坏了 / 跟当前源对不上）返回 null
  Future<List<_Chunk>?> _readResumeMeta({
    required File partialFile,
    required String metaPath,
    required String url,
    required int totalSize,
    required String? etag,
  }) async {
    final metaFile = File(metaPath);
    if (!await metaFile.exists() || !await partialFile.exists()) return null;
    if (await partialFile.length() != totalSize) return null;

    try {
      final meta = jsonDecode(await metaFile.readAsString());
      if (meta is! Map<String, dynamic>) return null;
      if (meta['url'] != url || meta['total'] != totalSize) return null;

      //ETag 只做「两边都有就必须相同」：镜像节点不一定回 ETag，缺了就按旧的接着下
      final savedEtag = meta['etag'];
      final currentEtag = etag;
      if (savedEtag is String &&
          savedEtag.isNotEmpty &&
          currentEtag != null &&
          currentEtag.isNotEmpty &&
          savedEtag != currentEtag) {
        return null;
      }

      final rawChunks = meta['chunks'];
      if (rawChunks is! List || rawChunks.isEmpty) return null;

      final chunks = <_Chunk>[];
      var cursor = 0;
      for (var i = 0; i < rawChunks.length; i++) {
        final item = rawChunks[i];
        if (item is! Map<String, dynamic>) return null;
        final start = item['start'];
        final end = item['end'];
        final received = item['received'];
        if (start is! int || end is! int || received is! int) return null;
        //区间必须严丝合缝地拼满整个文件：对不上说明元数据是上一轮留下的
        if (start != cursor || end < start || end >= totalSize) return null;
        if (received < 0 || received > end - start + 1) return null;
        chunks.add(_Chunk(i, start, end, end - start + 1, received));
        cursor = end + 1;
      }
      if (cursor != totalSize) return null;
      return chunks;
    } catch (_) {
      //元数据坏了（写到一半被杀）当没有：从零开始总比拼出个错文件强
      return null;
    }
  }

  ///清掉续传现场：`.part` 与它的元数据
  Future<void> _cleanupPartial(File partialFile, String metaPath) async {
    await _deleteWithRetry(partialFile);
    await _deleteQuietly(File(metaPath));
  }

  ///删临时文件，删不掉也不抛
  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      //留给系统清理
    }
  }

  ///删除临时文件并在被占用时短暂重试（Windows 下句柄释放是异步的）
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

  ///本块在源文件里的起始偏移（区间本身，不随下载进度变）
  final int start;

  ///本块区间的末尾；慢块被拆分时会把尾部让给新块，所以要可变
  int end;
  int size;

  ///已收字节数（含续传带过来的部分）
  int received;

  ///下一个要写的绝对偏移：续传与重试都从这里接，已收的字节不重下
  int nextOffset;

  ///上一次速率采样时的 [received]（算窗口速率用）
  int sampledBytes = 0;

  ///连续多少个采样窗口明显慢于其它块
  int slowStreak = 0;

  ///已被某个 worker 领走（避免重复下载同一区间）
  bool claimed = false;

  HttpChunkStatus status;

  _Chunk(this.index, this.start, this.end, this.size, this.received)
    : nextOffset = start + received,
      sampledBytes = received,
      status = HttpChunkStatus.pending;

  ///还没下完的字节数
  int get remaining => end - nextOffset + 1;
}

///服务端（或中间网关）嘴上支持 Range、实际回整包 200
///
///**故意不是 [DioException]**：调用方（[_downloadChunkedWithFallback]）据此
///换成单流整包重下
class _RangeIgnored implements Exception {}

/// 是否连接类失败（网络不通 / 代理不可用，属于「可重试」的网络问题）
///
/// 与 404 这类「资源不存在」、403 这类「接口拒绝」区分开
bool isNetworkFailure(DioException error) => switch (error.type) {
  DioExceptionType.connectionError ||
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout => true,
  _ => false,
};

/// 传输层失败：连接类失败 + dio 归到 [DioExceptionType.unknown] 的中断
///
/// 「Software caused connection abort」「Connection reset by peer」这类被对端掐断的
/// 连接在 dio 里是 `unknown`（不是 connectionError），但它是**链路问题**：
/// 直连时该回退镜像、镜像时该换下一个节点；用户主动取消不算
bool isTransportFailure(DioException error) =>
    !CancelToken.isCancel(error) &&
    (isNetworkFailure(error) || error.type == DioExceptionType.unknown);

/// 镜像节点这次失败该不该换节点：连接类失败，或节点回 403 / 429 / 5xx
///
/// 403 常是节点自己拒绝（限流 / 不服务境外 IP）而不是上游答复，换一个节点往往就好；
/// 404 这类是上游真实答复，换谁都一样，所以不算节点失败（镜像 404 不当故障）
bool isMirrorNodeFailure(DioException error) {
  if (isTransportFailure(error)) return true;
  final status = error.response?.statusCode;
  if (status == null) return false;
  return status == 403 || status == 429 || status >= 500;
}

/// 节点失败原因（写日志用）：有状态码就报状态码，否则报 dio 的失败类型
String mirrorFailureReason(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    return status == null ? error.type.name : 'HTTP $status';
  }
  return error.runtimeType.toString();
}

/// 该族的镜像节点全部失败
///
/// **故意不是 [DioException]**：调用方（[CopperIO._githubFallback]）据此回退直连
class MirrorUnavailable implements Exception {
  MirrorUnavailable(this.lastError);

  /// 最后一个节点的失败原因
  final Object? lastError;

  @override
  String toString() => '镜像节点全部失败（最后一个错误：$lastError）';
}

/// 把响应体解成对象：已经是对象（dio 帮着解过）就原样返回
///
/// dio **只在 content-type 是 JSON 时才帮解析**：真 API 上已经解好，再 `jsonDecode`
/// 会抛 `type 'List<dynamic>' is not a subtype of type 'String'`
@visibleForTesting
Object? decodeJsonBody(Object? data) =>
    data is String ? jsonDecode(data) : data;

/// 取 JSON 并解析成对象：**固定按纯文本取**，再自己解析
///
/// 不能拿 [cio] 返回的 data 直接当对象用：镜像节点回包常常不是 JSON content-type
/// （甚至是 HTML 错误页），此时 data 是 String，当对象用会抛
/// `type 'String' is not a subtype of type 'List<dynamic>?'`
Future<Object?> fetchJsonBody(
  String url, {
  Map<String, String>? headers,
}) async {
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

/// 异常信息里的响应预览
String previewResponseBody(String raw) {
  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 120 ? text : '${text.substring(0, 120)}…';
}
