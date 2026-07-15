import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../math/speed_calculate.dart';

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
    if (speed < kb) return '${speed.toStringAsFixed(1)} B/s';
    if (speed < mb) return '${(speed / kb).toStringAsFixed(1)} KB/s';
    return '${(speed / mb).toStringAsFixed(1)} MB/s';
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

// --- HttpHelper ---

class HttpHelper {
  static final HttpHelper _instance = HttpHelper._();

  factory HttpHelper() => _instance;

  HttpHelper._();

  Dio? _dio;
  bool _initialized = false;

  String? _proxyHost;
  int? _proxyPort;
  String? _proxyUsername;
  String? _proxyPassword;

  Duration _connectTimeout = const Duration(seconds: 20);
  Duration _receiveTimeout = const Duration(seconds: 60);

  int _maxRetries = 5;

  Dio get dio {
    _ensureInit();
    return _dio!;
  }

  void _ensureInit() {
    if (!_initialized) {
      _recreateClient();
      _initialized = true;
    }
  }

  void _recreateClient() {
    final baseOptions = BaseOptions(
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
    );

    if (_proxyHost != null && _proxyPort != null) {
      final adapter = IOHttpClientAdapter(
        // ignore: deprecated_member_use
        onHttpClientCreate: (client) {
          client.findProxy = (url) => 'PROXY $_proxyHost:$_proxyPort';
          if (_proxyUsername != null) {
            client.addProxyCredentials(
              _proxyHost!,
              _proxyPort!,
              'realm',
              HttpClientBasicCredentials(_proxyUsername!, _proxyPassword ?? ''),
            );
          }
          return client;
        },
      );
      _dio = Dio(baseOptions);
      _dio!.httpClientAdapter = adapter;
    } else {
      final adapter = IOHttpClientAdapter(
        // ignore: deprecated_member_use
        onHttpClientCreate: (client) {
          client.findProxy = (url) {
            final proxy = _detectSystemProxy(url);
            if (proxy != null) return 'PROXY $proxy';
            return 'DIRECT';
          };
          return client;
        },
      );
      _dio = Dio(baseOptions);
      _dio!.httpClientAdapter = adapter;
    }
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
      return _getWindowsSystemProxy();
    }

    return null;
  }

  String? _windowsSystemProxyCache;
  DateTime? _windowsSystemProxyCacheTime;

  String? _getWindowsSystemProxy() {
    if (_windowsSystemProxyCache != null &&
        _windowsSystemProxyCacheTime != null &&
        DateTime.now().difference(_windowsSystemProxyCacheTime!) <
            const Duration(seconds: 30)) {
      return _windowsSystemProxyCache;
    }

    try {
      final result = Process.runSync('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
      ], runInShell: true);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(output);
        if (match != null) {
          final proxy = match.group(1)!.trim();
          if (proxy.isNotEmpty) {
            _windowsSystemProxyCache = proxy;
            _windowsSystemProxyCacheTime = DateTime.now();
            return proxy;
          }
        }
      }
    } catch (_) {}

    _windowsSystemProxyCache = null;
    _windowsSystemProxyCacheTime = DateTime.now();
    return null;
  }

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
    _recreateClient();
  }

  void clearProxy() {
    _proxyHost = null;
    _proxyPort = null;
    _proxyUsername = null;
    _proxyPassword = null;
    _recreateClient();
  }

  bool get hasCustomProxy => _proxyHost != null && _proxyPort != null;

  String get proxyInfo {
    if (!hasCustomProxy) return 'system';
    final auth = _proxyUsername != null ? '$_proxyUsername@' : '';
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
    return _dio!.get<T>(
      url,
      options: Options(headers: headers, responseType: responseType),
      queryParameters: queryParameters ?? queryParameters,
      cancelToken: cancelToken,
    );
  }

  Future<Response> head(
    String url, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    _ensureInit();
    return _dio!.head(
      url,
      options: Options(headers: headers),
      cancelToken: cancelToken,
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
    return _dio!.post<T>(
      url,
      data: data,
      options: Options(headers: headers, responseType: responseType),
      queryParameters: queryParameters,
      cancelToken: cancelToken,
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

  Future<void> download({
    required String url,
    required String savePath,
    int? speedLimit,
    int chunkCount = 8,
    String? tempPath,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    HttpStatusCallback? onStatus,
    Map<String, String>? headers,
    int maxRetries = 5,
  }) async {
    _ensureInit();
    _maxRetries = maxRetries;

    final headResp = await _dio!.head(
      url,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    );

    final int totalSize = int.parse(
      headResp.headers.value('content-length') ?? '0',
    );

    final bool rangeSupported =
        headResp.headers.value('accept-ranges')?.toLowerCase() == 'bytes';

    if (totalSize <= 0 || !rangeSupported || totalSize < 2 * mb) {
      await _downloadSingleStream(
        url: url,
        savePath: savePath,
        totalSize: totalSize,
        speedLimit: speedLimit,
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
      chunkCount: chunkCount,
      speedLimit: speedLimit,
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
    if (totalSize < 2 * mb) {
      chunkCount = totalSize ~/ (500 * kb);
    } else {
      chunkCount = min(chunkCount, totalSize ~/ (2 * mb));
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
      final recentReceived = chunk.received;
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
          chunk.received = recentReceived + (await file.length());
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
          throw Exception('分块[${chunk.index}]下载失败');
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
        await tempFile.delete();
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
          final f = File(c.path);
          if (await f.exists()) await f.delete();
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
          final f = File(c.path);
          if (await f.exists()) await f.delete();
        }
      }
      state.status = HttpDownloadStatus.failed;
      onStatus?.call(state);
      rethrow;
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
