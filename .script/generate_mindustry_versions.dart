// 生成 remote/mindustry_versions.json（官方 release 快照）
//
// 数据 = GitHub release 对象的精简版，字段与 net_asset.dart 的
// MindustryGithubMeta.fromJson 对齐，启动器直接复用同一套解析；
// 历史版本不会再变，之后启动器只需用 API 补最新一页
//
// 用法：dart .script/generate_mindustry_versions.dart [代理地址，如 http://127.0.0.1:7890]
import 'dart:convert';
import 'dart:io';

const releaseApiUrl = 'https://api.github.com/repos/Anuken/Mindustry/releases';
const outputPath = 'remote/mindustry_versions.json';
const pageSize = 100;

Future<void> main(List<String> args) async {
  final proxy = args.isEmpty ? null : args.first;
  final client = HttpClient();
  if (proxy != null) {
    final uri = Uri.parse(proxy);
    client.findProxy = (target) => 'PROXY ${uri.host}:${uri.port}';
    stdout.writeln('走代理 $proxy');
  }

  final releases = <Map<String, dynamic>>[];
  for (var page = 1; ; page++) {
    final batch = await _fetchPage(client, page);
    releases.addAll(batch.map(_trimRelease));
    stdout.writeln('第 $page 页：${batch.length} 条');
    if (batch.length < pageSize) break;
  }
  client.close();

  final output = <String, dynamic>{
    'update_time': DateTime.now().toIso8601String().split('T').first,
    'source': releaseApiUrl,
    'releases': releases,
  };

  final file = File(outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );
  stdout.writeln('写入 $outputPath：${releases.length} 条，${await file.length()} 字节');
}

Future<List<dynamic>> _fetchPage(HttpClient client, int page) async {
  final request = await client.getUrl(
    Uri.parse('$releaseApiUrl?per_page=$pageSize&page=$page'),
  );
  request.headers.set('User-Agent', 'CopperLauncher-generator');
  request.headers.set('Accept', 'application/vnd.github+json');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw HttpException('列表获取失败：${response.statusCode} $body');
  }
  return jsonDecode(body) as List<dynamic>;
}

/// 精简 release：只留启动器要用的字段
///
/// body 一律存空串（列表不展示更新日志）；reactions 只留 total_count，
/// 但该键必须存在——MindustryGithubMeta 用「reactions 是否为 null」区分 be 版
Map<String, dynamic> _trimRelease(dynamic release) {
  final map = release as Map<String, dynamic>;
  final reactions = map['reactions'] as Map<String, dynamic>?;
  return {
    'name': map['name'],
    'tag_name': map['tag_name'],
    'published_at': map['published_at'],
    'body': '',
    'reactions': <String, dynamic>{
      'total_count': reactions?['total_count'] ?? 0,
    },
    'assets': [
      for (final asset in map['assets'] as List<dynamic>)
        {
          'name': (asset as Map<String, dynamic>)['name'],
          'size': asset['size'],
          'download_count': asset['download_count'],
          'browser_download_url': asset['browser_download_url'],
        },
    ],
  };
}
