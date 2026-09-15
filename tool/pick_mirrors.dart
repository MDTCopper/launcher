// 挑选好用的 GitHub 镜像预设节点，写回 remote/github_mirrors.hjson
//
// 每个节点测三项（对应实际用途）：
// - raw.githubusercontent.com：延迟（GET README，校验内容非健康页）
// - api.github.com：是否支持（必须返回 JSON，挡掉只回 `ok` 的假节点）
// - github.com：Range 取一段 release 资源，验证支持并算下载速度
//
// 候选 = github.akams.cn 爬到的社区节点 + 现有预设 + 命令行追加
// 三项全过才保留，按「速度降序 + 延迟升序」取前 defaultKeep 个（多留几个，
// 不同网络（校园网 / 广电 / 挂代理）表现不一样，池子大点运行期选择更稳）
//
// 用法（在项目根目录运行）：
//   dart tool/pick_mirrors.dart                      候选：akams + 预设
//   dart tool/pick_mirrors.dart ghfast.top           追加候选节点
//   dart tool/pick_mirrors.dart --dry-run            只打印排行，不写文件
//   dart tool/pick_mirrors.dart --keep 12            保留前 12 个（默认 8）
//   dart tool/pick_mirrors.dart --proxy 127.0.0.1:7890
//     代理只用于抓 akams 候选；镜像测速始终直连（镜像本身要能直连才有意义）
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const presetPath = 'remote/github_mirrors.hjson';
const akamsBase = 'https://github.akams.cn';

/// raw 探针：延迟 + 内容校验
const rawProbeUrl =
    'https://raw.githubusercontent.com/Anuken/Mindustry/master/README.md';

/// api 探针：必须返回 JSON
const apiProbeUrl = 'https://api.github.com/repos/Anuken/Mindustry';

/// github 探针：Range 取一小段 release 资源，验证支持并测速
const githubProbeUrl =
    'https://github.com/Anuken/Mindustry/releases/download/v159.7/Mindustry.jar';

/// github 测速取样大小：够估速度即可；节点多时整文件下载太慢
const speedSampleBytes = 512 * 1024;

/// 阶段一（raw 延迟 + api 校验，都是小请求）并发
const probeConcurrency = 16;

/// 阶段二（github Range 测速，重）并发
const speedConcurrency = 6;

const requestTimeout = Duration(seconds: 12);
const defaultKeep = 8;

class NodeResult {
  NodeResult(this.node);

  final String node;
  int? rawMs;
  bool apiOk = false;
  bool githubOk = false;
  double? speedBps;
  String? failReason;

  bool get ok => rawMs != null && apiOk && githubOk;
}

Future<void> main(List<String> args) async {
  var keep = defaultKeep;
  var dryRun = false;
  String? proxy;
  final cliNodes = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dry-run':
        dryRun = true;
      case '--keep':
        if (i + 1 < args.length) keep = int.tryParse(args[++i]) ?? keep;
      case '--proxy':
        if (i + 1 < args.length) proxy = args[++i];
      default:
        cliNodes.add(args[i]);
    }
  }

  stdout.writeln('收集候选…');
  final candidates = <String>{
    ..._readPreset(),
    ...await _crawlAkams(proxy),
    for (final raw in cliNodes) ?_normalize(raw),
  };

  final list = candidates.toList();
  final client = _newClient(null);

  // 阶段一：两项便宜的检查（raw 小文件 + api JSON），先淘汰大半
  stdout.writeln('阶段一：raw 延迟 + api 支持（${list.length} 个，并发 $probeConcurrency）');
  final results = <NodeResult>[];
  for (var i = 0; i < list.length; i += probeConcurrency) {
    final batch = list.sublist(i, math.min(i + probeConcurrency, list.length));
    results.addAll(
      await Future.wait(batch.map((node) => _testCheap(client, node))),
    );
  }

  // 阶段二：只给过了阶段一的节点做 github Range 测速（重）
  final passed = results.where((r) => r.rawMs != null && r.apiOk).toList();
  stdout.writeln(
    '阶段二：github 支持 + 测速（${passed.length} 个过阶段一，并发 $speedConcurrency）',
  );
  for (var i = 0; i < passed.length; i += speedConcurrency) {
    final batch = passed.sublist(
      i,
      math.min(i + speedConcurrency, passed.length),
    );
    await Future.wait(batch.map((result) => _testGithub(client, result)));
  }
  client.close(force: true);

  _printReport(results);

  final good = results.where((r) => r.ok).toList()
    ..sort((a, b) {
      final bySpeed = (b.speedBps ?? 0).compareTo(a.speedBps ?? 0);
      if (bySpeed != 0) return bySpeed;
      return (a.rawMs ?? 1 << 30).compareTo(b.rawMs ?? 1 << 30);
    });

  if (good.isEmpty) {
    stdout.writeln('\n没有三项全过的节点，未改动 $presetPath');
    return;
  }

  final chosen = good.take(keep).map((r) => r.node).toList();
  stdout.writeln('\n三项全过 ${good.length} 个，择优 ${chosen.length} 个：');
  for (final node in chosen) {
    stdout.writeln('  $node');
  }

  if (dryRun) {
    stdout.writeln('\n--dry-run：未写入 $presetPath');
    return;
  }
  await _writePreset(chosen);
  stdout.writeln('\n已写入 $presetPath');
}

// ── 单节点测试 ──────────────────────────────────────────────

Future<NodeResult> _testCheap(HttpClient client, String node) async {
  final result = NodeResult(node);

  // api：必须真是 JSON
  try {
    final body = await _getText(client, '$node$apiProbeUrl');
    final head = body.trimLeft();
    result.apiOk = head.startsWith('{') || head.startsWith('[');
  } catch (_) {}
  if (!result.apiOk) result.failReason = 'api 不支持';

  // raw：延迟 + 内容校验
  try {
    final stopwatch = Stopwatch()..start();
    final body = await _getText(client, '$node$rawProbeUrl');
    stopwatch.stop();
    if (body.contains('Mindustry')) result.rawMs = stopwatch.elapsedMilliseconds;
  } catch (_) {}
  if (result.rawMs == null) result.failReason ??= 'raw 不支持';

  return result;
}

/// 阶段二：Range 取一段 release 资源，验证 github.com 支持并估算速度
Future<void> _testGithub(HttpClient client, NodeResult result) async {
  try {
    final sample = await _rangeSample(client, '${result.node}$githubProbeUrl');
    if (sample.bytes > 0 && !sample.isHtml) {
      result.githubOk = true;
      final seconds = sample.elapsedMs / 1000;
      if (seconds > 0) result.speedBps = sample.bytes / seconds;
    }
  } catch (_) {}
  if (!result.githubOk) result.failReason ??= 'github 不支持';
}

Future<String> _getText(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url)).timeout(requestTimeout);
  request.headers.set('User-Agent', 'CopperLauncher-mirror-picker');
  final response = await request.close().timeout(requestTimeout);
  final body = await response
      .transform(utf8.decoder)
      .join()
      .timeout(requestTimeout);
  if (response.statusCode < 200 || response.statusCode >= 400) {
    throw HttpException('HTTP ${response.statusCode}：$url');
  }
  return body;
}

/// Range 取前 [speedSampleBytes] 字节，返回实取字节数 / 耗时 / 是否 HTML 错误页
Future<({int bytes, int elapsedMs, bool isHtml})> _rangeSample(
  HttpClient client,
  String url,
) async {
  final request = await client.getUrl(Uri.parse(url)).timeout(requestTimeout);
  request.headers.set('User-Agent', 'CopperLauncher-mirror-picker');
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${speedSampleBytes - 1}');

  final stopwatch = Stopwatch()..start();
  final response = await request.close().timeout(requestTimeout);
  if (response.statusCode < 200 || response.statusCode >= 400) {
    throw HttpException('HTTP ${response.statusCode}：$url');
  }

  var bytes = 0;
  final head = <int>[];
  await for (final chunk in response.timeout(requestTimeout)) {
    bytes += chunk.length;
    if (head.length < 16) {
      head.addAll(chunk.take(16 - head.length));
    }
    if (bytes >= speedSampleBytes) break;
  }
  stopwatch.stop();

  final headText = utf8.decode(head, allowMalformed: true).trimLeft().toLowerCase();
  final isHtml = headText.startsWith('<!doctype') || headText.startsWith('<html');
  return (bytes: bytes, elapsedMs: stopwatch.elapsedMilliseconds, isHtml: isHtml);
}

// ── 候选收集 ────────────────────────────────────────────────

/// 现有预设里的节点（从 hjson 文本里抠 URL，格式简单不引 hjson 依赖）
List<String> _readPreset() {
  final file = File(presetPath);
  if (!file.existsSync()) return const [];
  return [
    for (final match in RegExp(r'https?://\S+').allMatches(file.readAsStringSync()))
      ?_normalize(match.group(0)!),
  ];
}

/// 从 github.akams.cn 页面 JS 里扒社区节点（逻辑与 lib 的 github_mirror 一致）
Future<List<String>> _crawlAkams(String? proxy) async {
  final client = _newClient(proxy);
  try {
    final page = await _getText(client, akamsBase);
    for (final chunk in _extractChunkUrls(page)) {
      final js = await _getText(client, '$akamsBase$chunk');
      final domains = _extractNodeDomains(js);
      if (domains.isNotEmpty) {
        stdout.writeln('akams 爬到 ${domains.length} 个社区节点');
        return [for (final domain in domains) 'https://$domain/'];
      }
    }
  } catch (error) {
    stdout.writeln('akams 爬取失败（忽略，用预设 + 命令行候选）：$error');
  } finally {
    client.close(force: true);
  }
  return const [];
}

List<String> _extractChunkUrls(String html) => RegExp(
  r'/_next/static/chunks/[a-zA-Z0-9._-]+\.js',
).allMatches(html).map((m) => m.group(0)!).toSet().toList();

List<String> _extractNodeDomains(String js) => RegExp(
  r'\{label:"(?:search|contribute)",value:"([a-zA-Z0-9.-]+)"\}',
).allMatches(js).map((m) => m.group(1)!).toSet().toList();

// ── 输出 ────────────────────────────────────────────────────

Future<void> _writePreset(List<String> nodes) async {
  final date = DateTime.now().toIso8601String().split('T').first;
  final buffer = StringBuffer()
    ..writeln('update_time: $date')
    ..writeln('mirrors:[');
  for (final node in nodes) {
    buffer.writeln('    $node');
  }
  buffer.writeln(']');
  await File(presetPath).writeAsString(buffer.toString(), flush: true);
}

void _printReport(List<NodeResult> results) {
  final sorted = [...results]..sort((a, b) => a.node.compareTo(b.node));
  const header = 'raw(ms)  api  github  速度(MB/s)  说明';
  stdout.writeln('\n${'节点'.padRight(36)}$header');
  for (final result in sorted) {
    final speed = result.speedBps == null
        ? '-'
        : (result.speedBps! / 1024 / 1024).toStringAsFixed(2);
    stdout.writeln(
      '${result.node.padRight(36)}'
      '${(result.rawMs?.toString() ?? '-').padLeft(6)}  '
      '${result.apiOk ? ' ok ' : '--- '} '
      '${result.githubOk ? ' ok ' : '--- '}  '
      '${speed.padLeft(8)}  '
      '${result.ok ? '' : result.failReason ?? ''}',
    );
  }
}

// ── 工具 ────────────────────────────────────────────────────

HttpClient _newClient(String? proxy) {
  final client = HttpClient()..connectionTimeout = requestTimeout;
  if (proxy != null && proxy.isNotEmpty) {
    final uri = Uri.parse(proxy.contains('://') ? proxy : 'http://$proxy');
    client.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
  }
  return client;
}

/// 统一成「前缀」：补 scheme、保证以 `/` 结尾
String? _normalize(String raw) {
  var node = raw.trim();
  if (node.isEmpty) return null;
  if (!node.startsWith('http://') && !node.startsWith('https://')) {
    node = 'https://$node';
  }
  if (!node.endsWith('/')) node = '$node/';
  return node;
}
