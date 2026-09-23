// 挑选好用的 GitHub 镜像预设节点，写回 remote/github_mirrors.hjson
//
// 阶段一：三家并发探（各带超时）—— raw 延迟、api 是否真 JSON、github 1KB Range 探针
// 阶段二：按 github.com 探针延迟升序取前 max-download-tests 个，测 Range 与速度
//   - range 只在回 206 时算支持（回 200 是忽略 Range 吐整个文件，只能单流）
//   - 连接超时管出首字节之前，接收超时从收到第一块数据开始算；超预算用已收字节估速
//
// 候选 = akams 爬到的社区节点 + 现有预设 + 命令行追加
// 择优：按族各留 keep 个（github 看「Range 优先 + 速度」，raw / api 看延迟）再取并集
//
// 用法（在项目根目录运行）：
//   dart tool/pick_mirrors.dart                      候选：akams + 预设
//   dart tool/pick_mirrors.dart ghfast.top           追加候选节点
//   dart tool/pick_mirrors.dart --dry-run            只打印排行，不写文件
//   dart tool/pick_mirrors.dart --keep 8             每族保留几个（默认 5）
//   dart tool/pick_mirrors.dart --concurrency 3      并发数（默认 6，两个阶段都用它，上限 64）
//   dart tool/pick_mirrors.dart --max-download-tests 20
//                                                    下载测速名额（默认 30，0 = 不限）
//   dart tool/pick_mirrors.dart --proxy 127.0.0.1:7890
//     代理只用于抓 akams 候选；镜像测速始终直连（镜像本身要能直连才有意义）
//
// 跑的时候别并发干别的网络活：2MB 取样互相抢带宽会让速度数字失真
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:copper_launcher/util/io/mirror_node.dart';

const presetPath = 'remote/github_mirrors.hjson';
const akamsBase = 'https://github.akams.cn';

/// raw 探针：延迟 + 内容校验
const rawProbeUrl =
    'https://raw.githubusercontent.com/Anuken/Mindustry/master/README.md';

/// api 探针：必须返回 JSON
const apiProbeUrl = 'https://api.github.com/repos/Anuken/Mindustry';

/// github 探针：Range 取一段 release 资源，验证支持并测速
const githubProbeUrl =
    'https://github.com/Anuken/Mindustry/releases/download/v159.7/Mindustry.jar';

/// github 测速取样大小：2MB 才拉得开差距（小样本会被镜像的突发缓存抬高）
const speedSampleBytes = 2 * 1024 * 1024;

/// github 1KB 探针取样大小
const githubProbeBytes = 1024;

/// 阶段一单节点超时（三家并发探，各带自己的）
const nodeProbeBudget = Duration(seconds: 8);

/// 1KB 探针收到第一块之后的接收预算
const githubProbeReceiveBudget = Duration(seconds: 4);

/// 阶段二：连接（出首字节前）预算
const nodeConnectBudget = Duration(seconds: 10);

/// 阶段二：从收到第一块数据开始算的接收预算
const nodeReceiveBudget = Duration(seconds: 15);

/// 两个阶段的默认并发（共用一个旋钮）
const defaultConcurrency = 6;

/// 并发上限：太大反而互相抢带宽，测出来的速度也不准
const maxConcurrency = 64;

const requestTimeout = Duration(seconds: 20);
const defaultKeep = 5;

/// 默认下载测速名额：候选可能几十个，全测太费流量
const defaultMaxDownloadTests = 30;

/// 命令行参数
class PickerArgs {
  const PickerArgs({
    required this.keep,
    required this.concurrency,
    required this.maxDownloadTests,
    required this.dryRun,
    required this.proxy,
    required this.nodes,
  });

  /// 每族保留几个
  final int keep;

  /// 两个阶段的并发
  final int concurrency;

  /// 最多给几个节点做下载测速（按 github.com 探针延迟取前几个；0 = 不限）
  final int maxDownloadTests;

  final bool dryRun;

  /// 只用于抓 akams 候选的代理
  final String? proxy;

  /// 命令行追加的候选节点
  final List<String> nodes;
}

PickerArgs parsePickerArgs(List<String> args) {
  var keep = defaultKeep;
  var concurrency = defaultConcurrency;
  var maxDownloadTests = defaultMaxDownloadTests;
  var dryRun = false;
  String? proxy;
  final nodes = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dry-run':
        dryRun = true;
      case '--keep':
        if (i + 1 < args.length) keep = int.tryParse(args[++i]) ?? keep;
      case '--concurrency':
        if (i + 1 < args.length) {
          final value = int.tryParse(args[++i]);
          if (value != null) concurrency = value.clamp(1, maxConcurrency);
        }
      case '--max-download-tests':
        if (i + 1 < args.length) {
          final value = int.tryParse(args[++i]);
          if (value != null && value >= 0) maxDownloadTests = value;
        }
      case '--proxy':
        if (i + 1 < args.length) proxy = args[++i];
      default:
        nodes.add(args[i]);
    }
  }

  return PickerArgs(
    keep: keep,
    concurrency: concurrency,
    maxDownloadTests: maxDownloadTests,
    dryRun: dryRun,
    proxy: proxy,
    nodes: nodes,
  );
}

class NodeResult {
  NodeResult(this.node);

  final String node;
  int? rawMs;
  bool apiOk = false;
  bool githubOk = false;

  /// 是否真支持 Range（探针回 206）：支持才能分块并发下载
  bool rangeOk = false;
  double? speedBps;
  String? failReason;

  /// github.com 的 1KB 探针耗时：给下载测速排序，通了才算「能下载」
  int? githubProbeMs;

  /// 1KB 探针没过的原因（超时 / HTML / HTTP 码）：看不出原因时最难查
  String? githubProbeNote;

  /// 下载测速没跑满样本时的说明（慢节点）：速度按已收到字节算
  String? slowNote;

  bool get githubReachable => githubProbeMs != null;

  /// 能不能下 github.com 的资源（下载场景的门槛）
  bool get downloadable => githubOk;

  /// 转成预设记录：能力 + 实测速度（MB/s）
  MirrorNode toMirrorNode() => MirrorNode(
    url: node,
    github: githubOk,
    raw: rawMs != null,
    api: apiOk,
    range: rangeOk,
    speed: (speedBps ?? 0) / 1024 / 1024,
  );
}

/// 挑出要跑下载测速的节点：**按 github.com 的 1KB 探针延迟升序**（快的先测），
/// 取前 [maxTests] 个；0 = 不限
///
/// 探针没通的节点直接排除（连 1KB 都拿不到，2MB 更没戏）
List<NodeResult> pickDownloadTests(List<NodeResult> results, int maxTests) {
  final reachable = results.where((r) => r.githubReachable).toList()
    ..sort((a, b) => a.githubProbeMs!.compareTo(b.githubProbeMs!));
  if (maxTests == 0) return reachable;
  return reachable.take(maxTests).toList();
}

/// 按族各留 [keep] 个，返回并集：github 看「Range 优先 + 速度」，raw / api 看延迟
List<MirrorNode> pickPerFamily(List<NodeResult> results, int keep) {
  final picked = <String, MirrorNode>{};

  void take(
    Iterable<NodeResult> pool,
    int Function(NodeResult a, NodeResult b) compare,
  ) {
    final sorted = pool.toList()..sort(compare);
    for (final result in sorted.take(keep)) {
      picked[result.node] = result.toMirrorNode();
    }
  }

  int byRawMs(NodeResult a, NodeResult b) =>
      (a.rawMs ?? 1 << 30).compareTo(b.rawMs ?? 1 << 30);

  take(results.where((r) => r.githubOk), (a, b) {
    if (a.rangeOk != b.rangeOk) return a.rangeOk ? -1 : 1;
    return (b.speedBps ?? 0).compareTo(a.speedBps ?? 0);
  });
  take(results.where((r) => r.rawMs != null), byRawMs);
  take(results.where((r) => r.apiOk), byRawMs);

  final list = picked.values.toList()
    ..sort((a, b) {
      // 能下 github 的排前面（下载是主要用途），同组内 Range 与速度优先
      if (a.github != b.github) return a.github ? -1 : 1;
      if (a.github && b.github) {
        if (a.range != b.range) return a.range ? -1 : 1;
        return b.speed.compareTo(a.speed);
      }
      return a.url.compareTo(b.url);
    });
  return list;
}

Future<void> main(List<String> args) async {
  final options = parsePickerArgs(args);

  stdout.writeln('收集候选…');
  final candidates = <String>{
    ..._readPreset(),
    ...await _crawlAkams(options.proxy),
    for (final raw in options.nodes) ?MirrorNode.normalizeUrl(raw),
  };

  final list = candidates.toList();
  final client = _newClient(null);

  // 阶段一：三家并发探（raw 延迟 / api JSON / github 1KB）
  final concurrency = options.concurrency;
  stdout.writeln('阶段一：raw + api + github 探针（${list.length} 个，并发 $concurrency）');
  final phaseOneWatch = Stopwatch()..start();
  final phaseOne = PickerProgress('阶段一', list.length)..start();
  final results = <NodeResult>[];
  for (var i = 0; i < list.length; i += concurrency) {
    final batch = list.sublist(i, math.min(i + concurrency, list.length));
    results.addAll(
      await Future.wait(
        batch.map((node) => _testCheap(client, node, phaseOne)),
      ),
    );
  }
  phaseOne.finish();
  phaseOneWatch.stop();
  final rawPassed = results.where((r) => r.rawMs != null).length;
  final githubReachable = results.where((r) => r.githubReachable).length;
  stdout.writeln(
    '阶段一完成：$rawPassed 个 raw 通 / ${results.where((r) => r.apiOk).length} 个 api 通'
    ' / $githubReachable 个 github 可下'
    '（${phaseOneWatch.elapsed.inSeconds}s）',
  );

  // 阶段二：按 github.com 探针延迟取前 maxDownloadTests 个做下载探测 + 测速
  final passed = pickDownloadTests(results, options.maxDownloadTests);
  final skipped = githubReachable - passed.length;
  stdout.writeln(
    '阶段二：github 下载 + Range + 测速（取 ${passed.length} 个，并发 $concurrency'
    '${skipped > 0 ? '；github 可下 $githubReachable 个，其余 $skipped 个不测下载' : ''}）',
  );
  final phaseTwoWatch = Stopwatch()..start();
  final phaseTwo = PickerProgress('阶段二', passed.length)..start();
  for (var i = 0; i < passed.length; i += concurrency) {
    final batch = passed.sublist(i, math.min(i + concurrency, passed.length));
    await Future.wait(
      batch.map((result) => _testGithub(client, result, phaseTwo)),
    );
  }
  phaseTwo.finish();
  phaseTwoWatch.stop();
  stdout.writeln('阶段二完成（${phaseTwoWatch.elapsed.inSeconds}s）');
  client.close(force: true);

  _printReport(results);

  final chosen = pickPerFamily(results, options.keep);
  final githubCount = chosen.where((r) => r.github).length;
  final rangeCount = chosen.where((r) => r.range).length;
  final rawCount = chosen.where((r) => r.raw).length;
  final apiCount = chosen.where((r) => r.api).length;

  if (chosen.isEmpty) {
    stdout.writeln('\n没有可用节点，未改动 $presetPath');
    return;
  }

  stdout.writeln(
    '\n按族择优 ${chosen.length} 个：'
    'github $githubCount（其中 Range $rangeCount）/ raw $rawCount / api $apiCount',
  );
  for (final node in chosen) {
    final caps = [
      if (node.github) 'github',
      if (node.raw) 'raw',
      if (node.api) 'api',
      if (node.range) 'Range',
    ].join('+');
    stdout.writeln(
      '  ${node.url.padRight(36)}${caps.padRight(28)}'
      '${node.speed.toStringAsFixed(2)} MB/s',
    );
  }

  if (options.dryRun) {
    stdout.writeln('\n--dry-run：未写入 $presetPath');
    return;
  }
  await File(presetPath).writeAsString(formatMirrorPreset(chosen), flush: true);
  stdout.writeln('\n已写入 $presetPath');
}

// ── 单节点测试 ──────────────────────────────────────────────

/// 跑的时候的进度反馈：每个节点出结果打一行；有节点久等就每 5 秒报一次，
/// 免得看着像卡死
class PickerProgress {
  PickerProgress(this.label, this.total);

  final String label;
  final int total;
  int _done = 0;
  final Map<String, DateTime> _inflight = {};
  Timer? _heartbeat;

  void start() {
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _beat());
  }

  void begin(String node) => _inflight[node] = DateTime.now();

  void end(String node, String detail) {
    _inflight.remove(node);
    _done++;
    stdout.writeln('[$label $_done/$total] ${node.padRight(36)} $detail');
  }

  void finish() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _inflight.clear();
  }

  /// 超过 10 秒没回的节点报一下（慢节点是主要耗时来源）
  void _beat() {
    final now = DateTime.now();
    for (final entry in _inflight.entries) {
      final seconds = now.difference(entry.value).inSeconds;
      if (seconds >= 10 && seconds % 5 == 0) {
        stdout.writeln('      …仍在测 ${entry.key}（${seconds}s）');
      }
    }
  }
}

Future<NodeResult> _testCheap(
  HttpClient client,
  String node,
  PickerProgress progress,
) async {
  final result = NodeResult(node);
  progress.begin(node);

  // 三家并发探：省时间，每家能力也各自独立
  final (apiOk, rawMs, githubProbe) = await (
    _probeApi(client, node),
    _probeRaw(client, node),
    _probeGithub(client, node),
  ).wait;

  result.apiOk = apiOk;
  result.rawMs = rawMs;
  result.githubProbeMs = githubProbe.ms;
  result.githubProbeNote = githubProbe.note;
  if (!result.apiOk) result.failReason = 'api 不支持';
  if (result.rawMs == null) result.failReason = 'raw 不可用';

  progress.end(
    node,
    'raw ${result.rawMs == null ? '不可用' : '${result.rawMs}ms'}  '
    'api ${result.apiOk ? 'ok' : '--'}  '
    'github ${result.githubReachable ? '${result.githubProbeMs}ms' : result.githubProbeNote ?? '--'}',
  );
  return result;
}

/// api.github.com：必须真是 JSON（挡掉只回 `ok` 的健康页）
Future<bool> _probeApi(HttpClient client, String node) async {
  try {
    final body = await _getText(
      client,
      '$node$apiProbeUrl',
    ).timeout(nodeProbeBudget);
    final head = body.trimLeft();
    return head.startsWith('{') || head.startsWith('[');
  } catch (_) {
    return false;
  }
}

/// raw.githubusercontent.com：延迟（顺带校验内容不是健康页）
Future<int?> _probeRaw(HttpClient client, String node) async {
  try {
    final stopwatch = Stopwatch()..start();
    final body = await _getText(
      client,
      '$node$rawProbeUrl',
    ).timeout(nodeProbeBudget);
    stopwatch.stop();
    return body.contains('Mindustry') ? stopwatch.elapsedMilliseconds : null;
  } catch (_) {
    return null;
  }
}

/// github.com：1KB Range 小探针 —— 延迟用来给下载测速排序，
/// 通了才说明这个节点能下 release 资源（raw 通不通是另一回事）
Future<({int? ms, String? note})> _probeGithub(
  HttpClient client,
  String node,
) async {
  try {
    final sample = await _rangeSample(
      client,
      '$node$githubProbeUrl',
      size: githubProbeBytes,
      connectTimeout: nodeProbeBudget,
      receiveTimeout: githubProbeReceiveBudget,
    );
    if (sample.isHtml) {
      // 有的节点对 release 路径回一个 HTML 说明页，那不是能用的下载节点
      return (ms: null, note: 'HTML ${sample.statusCode}');
    }
    if (sample.bytes > 0) return (ms: sample.elapsedMs, note: null);
    return (ms: null, note: 'HTTP ${sample.statusCode} 无内容');
  } on TimeoutException {
    return (ms: null, note: '超时');
  } catch (error) {
    return (
      ms: null,
      note: error is HttpException
          ? error.message
          : error.runtimeType.toString(),
    );
  }
}

/// 阶段二：Range 取一段 release 资源，验证 github.com 支持并估算速度
Future<void> _testGithub(
  HttpClient client,
  NodeResult result,
  PickerProgress progress,
) async {
  progress.begin(result.node);
  try {
    final sample = await _rangeSample(
      client,
      '${result.node}$githubProbeUrl',
      connectTimeout: nodeConnectBudget,
      receiveTimeout: nodeReceiveBudget,
    );
    if (sample.bytes > 0 && !sample.isHtml) {
      result.githubOk = true;
      // 只有 206 才算真支持 Range（回 200 = 忽略 Range 吐整个文件，只能单流）
      result.rangeOk = sample.statusCode == HttpStatus.partialContent;
      final seconds = sample.elapsedMs / 1000;
      // 超预算的节点按实际收到的字节估速
      if (seconds > 0) result.speedBps = sample.bytes / seconds;
      if (sample.bytes < speedSampleBytes) {
        result.slowNote =
            '慢（${(sample.bytes / 1024).round()}KB/${seconds.toStringAsFixed(1)}s）';
      }
    }
  } catch (_) {}
  if (!result.githubOk) {
    result.failReason ??= 'github 不可用';
  } else if (!result.apiOk) {
    result.failReason ??= 'api 不可用（能下载）';
  }

  final speed = result.speedBps == null
      ? '--'
      : '${(result.speedBps! / 1024 / 1024).toStringAsFixed(2)}MB/s';
  progress.end(
    result.node,
    'github ${result.githubOk ? 'ok' : '--'}  '
    'range ${result.githubOk ? (result.rangeOk ? 'ok' : '--') : 'n/a'}  '
    '$speed',
  );
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

/// Range 取前 [size] 字节（默认 [speedSampleBytes]），返回实取字节数 / 耗时 /
/// 是否 HTML 错误页 / 状态码
///
/// [connectTimeout] 管出首字节之前，[receiveTimeout] 从收到第一块数据开始算
/// （慢启动的节点不该被连接耗时判死；超预算就用已收字节算速度）
///
/// [statusCode] 用来分辨「真支持 Range」（206）与「忽略 Range 吐整个文件」（200）
Future<({int bytes, int elapsedMs, bool isHtml, int statusCode})> _rangeSample(
  HttpClient client,
  String url, {
  int? size,
  Duration? connectTimeout,
  Duration? receiveTimeout,
}) async {
  final want = size ?? speedSampleBytes;
  final connectLimit = connectTimeout ?? requestTimeout;
  final receiveLimit = receiveTimeout ?? requestTimeout;

  final request = await client.getUrl(Uri.parse(url)).timeout(connectLimit);
  request.headers.set('User-Agent', 'CopperLauncher-mirror-picker');
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${want - 1}');

  // 接收计时从第一块数据开始：连接与响应头耗时不算进去
  final receiveWatch = Stopwatch();
  final response = await request.close().timeout(connectLimit);
  if (response.statusCode < 200 || response.statusCode >= 400) {
    throw HttpException('HTTP ${response.statusCode}：$url');
  }

  var bytes = 0;
  final head = <int>[];
  await for (final chunk in response.timeout(receiveLimit)) {
    if (!receiveWatch.isRunning) receiveWatch.start();
    bytes += chunk.length;
    if (head.length < 16) {
      head.addAll(chunk.take(16 - head.length));
    }
    if (bytes >= want || receiveWatch.elapsed > receiveLimit) break;
  }
  receiveWatch.stop();

  final headText = utf8
      .decode(head, allowMalformed: true)
      .trimLeft()
      .toLowerCase();
  final isHtml =
      headText.startsWith('<!doctype') || headText.startsWith('<html');
  return (
    bytes: bytes,
    // 耗时只算接收窗口（连接与响应头不算）：速度才有可比性
    elapsedMs: receiveWatch.elapsedMilliseconds,
    isHtml: isHtml,
    statusCode: response.statusCode,
  );
}

// ── 候选收集 ────────────────────────────────────────────────

/// 现有预设里的节点（走共享解析，新旧格式都认）
List<String> _readPreset() {
  final file = File(presetPath);
  if (!file.existsSync()) return const [];
  return [
    for (final node in parseMirrorPreset(file.readAsStringSync())) node.url,
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

void _printReport(List<NodeResult> results) {
  final sorted = [...results]..sort((a, b) => a.node.compareTo(b.node));
  const header = 'raw(ms)  api  github  range  速度(MB/s)  说明';
  stdout.writeln('\n${'节点'.padRight(36)}$header');
  for (final result in sorted) {
    final speed = result.speedBps == null
        ? '-'
        : (result.speedBps! / 1024 / 1024).toStringAsFixed(2);
    // github 列：阶段二测过就写 ok/---；只过 1KB 探针（没排上测速名额）写 1KB
    final String githubCell = result.githubOk
        ? ' ok '
        : (result.githubReachable ? '1KB ' : '--- ');
    final rangeCell = result.githubOk
        ? (result.rangeOk ? ' ok ' : '--- ')
        : 'n/a ';
    stdout.writeln(
      '${result.node.padRight(36)}'
      '${(result.rawMs?.toString() ?? '-').padLeft(6)}  '
      '${result.apiOk ? ' ok ' : '--- '} '
      '$githubCell  '
      '$rangeCell  '
      '${speed.padLeft(8)}  '
      '${[if (result.failReason != null) result.failReason!, if (!result.githubReachable && result.githubProbeNote != null) 'github ${result.githubProbeNote}', if (result.slowNote != null) result.slowNote!].join(' / ')}',
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
