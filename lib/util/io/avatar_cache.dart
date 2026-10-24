import 'dart:io';

import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 头像磁盘缓存：`<数据根>/cache/avatars/<短哈希>-<文件名>`
///
/// 论坛头像是 `/uploads/avatars/<时间戳>-<随机>.jpg` 这种**不会变的路径**，
/// 所以直接按 URL 缓存到底就行；换头像会换文件名，不用做失效。
/// 走 [cio] 而不是裸 Dio：代理 / 超时 / 证书那些设置跟其它请求保持一致。
class AvatarCache {
  AvatarCache._();

  static String get dir => p.join(AppPaths.copperLauncher, 'cache', 'avatars');

  /// 同一个 URL 同时被多个头像请求时只下载一次
  static final Map<String, Future<File?>> _inflight = {};

  static String _fileNameOf(String url) {
    final uri = Uri.tryParse(url);
    final raw = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : url.hashCode.toRadixString(16);
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final tail = safe.length > 64 ? safe.substring(safe.length - 64) : safe;
    return '${url.hashCode.toRadixString(16)}-$tail';
  }

  /// 已经缓存过就直接给文件（同步，首帧不闪）
  static File? cached(String url) {
    final file = File(p.join(dir, _fileNameOf(url)));
    return file.existsSync() ? file : null;
  }

  /// 缓存优先；没有就下载并落盘。失败返回 null（界面退回兜底图标）
  static Future<File?> load(String url) {
    final hit = cached(url);
    if (hit != null) return Future.value(hit);
    return _inflight[url] ??= _fetch(url).whenComplete(() => _inflight.remove(url));
  }

  static Future<File?> _fetch(String url) async {
    try {
      final response = await cio.dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      final file = File(p.join(dir, _fileNameOf(url)));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on Object catch (error) {
      addLog(.debug, '头像缓存失败：$error', tag: 'Avatar');
      return null;
    }
  }
}
