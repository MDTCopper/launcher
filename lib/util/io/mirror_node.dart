import 'package:hjson_dart/hjson_dart.dart' as hjson;

/// 镜像节点能直连的 github 域名族（三家能力互不相同，按族分开记）
enum MirrorFamily {
  /// `github.com`：release 资源 / 归档下载
  github,

  /// `raw.githubusercontent.com`：raw 文件（版本快照、适配表等）
  raw,

  /// `api.github.com`：接口（绕匿名额度）
  api,
}

/// URL 属于哪个域名族；不是需要加速的 github 域名返回 null
MirrorFamily? mirrorFamilyOf(String url) {
  final host = Uri.tryParse(url)?.host;
  return switch (host) {
    'github.com' => MirrorFamily.github,
    'raw.githubusercontent.com' => MirrorFamily.raw,
    'api.github.com' => MirrorFamily.api,
    _ => null,
  };
}

/// 一个镜像节点：前缀地址 + 实测能力（`tool/pick_mirrors.dart` 写回预设）
///
/// 旧格式只写地址时按「三家都可能」乐观处理，运行期探针会再筛
class MirrorNode {
  const MirrorNode({
    required this.url,
    this.github = true,
    this.raw = true,
    this.api = true,
    this.range = false,
    this.speed = 0,
  });

  /// 镜像前缀：`https://example.com/`（拼原 URL 用，必须以 `/` 结尾）
  final String url;

  /// 能直连 `github.com`
  final bool github;

  /// 能直连 `raw.githubusercontent.com`
  final bool raw;

  /// 能直连 `api.github.com`
  final bool api;

  /// 支持 Range 请求（回 206）：支持才能分块并发 + 断点续传
  final bool range;

  /// 实测下载速度（MB/s），主要看 `github.com` 的资源
  final double speed;

  /// 这个节点能不能服务某一族请求
  bool serves(MirrorFamily family) => switch (family) {
    MirrorFamily.github => github,
    MirrorFamily.raw => raw,
    MirrorFamily.api => api,
  };

  /// 统一成「前缀」形态：补 scheme、保证以 `/` 结尾
  static String? normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (!url.endsWith('/')) url = '$url/';
    return url;
  }

  /// 从预设里的一项构造：字符串 = 旧格式（只写地址），对象 = 带能力
  static MirrorNode? fromPresetItem(Object? item) {
    if (item is String) {
      final url = normalizeUrl(item);
      return url == null ? null : MirrorNode(url: url);
    }
    if (item is Map) {
      final url = normalizeUrl(item['url']?.toString() ?? '');
      if (url == null) return null;
      return MirrorNode(
        url: url,
        github: _boolOf(item['github'], fallback: true),
        raw: _boolOf(item['raw'], fallback: true),
        api: _boolOf(item['api'], fallback: true),
        range: _boolOf(item['range'], fallback: false),
        speed: _doubleOf(item['speed']),
      );
    }
    return null;
  }

  static bool _boolOf(Object? value, {required bool fallback}) =>
      value is bool ? value : fallback;

  static double _doubleOf(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  String toString() => url;
}

/// 解析预设文件（hjson）：`mirrors` 里每项可以是字符串（旧格式）或带能力的对象
List<MirrorNode> parseMirrorPreset(String? content) {
  if (content == null || content.trim().isEmpty) return const [];
  try {
    final decoded = hjson.hjsonDecode(content) as Map<String, dynamic>;
    final mirrors = decoded['mirrors'] as List<dynamic>? ?? const [];
    return mirrors
        .map(MirrorNode.fromPresetItem)
        .whereType<MirrorNode>()
        .toList();
  } catch (_) {
    return const [];
  }
}

/// 生成预设文本：写回 `remote/github_mirrors.hjson` 用（脚本与手工维护共用一份）
String formatMirrorPreset(List<MirrorNode> nodes, {DateTime? date}) {
  final day = (date ?? DateTime.now()).toIso8601String().split('T').first;
  final buffer = StringBuffer()
    ..writeln('# 节点能力由 tool/pick_mirrors.dart 实测写入，别手改字段名')
    ..writeln('update_time: $day')
    ..writeln('mirrors:[');
  for (final node in nodes) {
    buffer.writeln(
      '    {url: "${node.url}", github: ${node.github}, raw: ${node.raw}, '
      'api: ${node.api}, range: ${node.range}, '
      'speed: ${node.speed.toStringAsFixed(2)}}',
    );
  }
  buffer.writeln(']');
  return buffer.toString();
}
