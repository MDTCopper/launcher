import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/remote_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hjson_dart/hjson_dart.dart' as hjson;
import 'package:path/path.dart' as p;

///github 镜像节点管理。
///
///仅加速 `github.com` / `api.github.com` / `raw.githubusercontent.com` 三个域名，
///用法是「镜像前缀 + 原 URL」（如 `https://ghfast.top/https://github.com/...`）。
///
///节点分三类：
///- 预设：官方仓库 `remote/github_mirrors.hjson`（RemoteData 拉取，assets 兜底）
///- 爬取：从 github.akams.cn 页面 JS 里扒出来的社区节点（缓存到 remoteData）
///- 自定义：用户手动添加，存 config，与预设分开管理
///
///策略：官方直连失败后才走镜像（对齐 Mindustry 的错误驱动回退）；选镜像时
///对候选节点 HEAD 测速，取最快缓存。
class GithubMirror {
  static final GithubMirror _instance = GithubMirror._();

  factory GithubMirror() => _instance;

  static GithubMirror get instance => _instance;

  GithubMirror._();

  static const _githubHosts = {
    'github.com',
    'api.github.com',
    'raw.githubusercontent.com',
  };

  ///镜像测速 / 爬取预检用的探测 URL（小文件，HEAD 往返即可）
  static const probeUrl =
      'https://raw.githubusercontent.com/Anuken/Mindustry/master/README.md';

  ///测速用独立 Dio（避免与 copper_io 相互依赖 / 循环）
  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  bool _enabled = true;

  ///预设节点（来自 remote github_mirrors.hjson）
  List<String> _presetNodes = [];

  ///从 github.akams.cn 爬取并预检通过的社区节点
  List<String> _crawledNodes = [];

  ///爬取预检得到的各节点延迟（前缀 -> ms），供设置页直接展示
  Map<String, int> crawledLatencies = {};

  ///当前选出的最优镜像前缀；null 表示尚未测速
  String? _bestMirror;

  ///最优镜像的选定时刻，用于 TTL 缓存（避免每次回退都全量测速）
  DateTime? _bestMirrorAt;

  ///最优镜像缓存有效期
  static const _bestMirrorTtl = Duration(minutes: 10);

  bool get enabled => _enabled;

  String? get bestMirror => _bestMirror;

  ///缓存仍有效的最优镜像；过期或未选定时返回 null。
  String? get freshBestMirror {
    final best = _bestMirror;
    final at = _bestMirrorAt;
    if (best == null || at == null) return null;
    if (DateTime.now().difference(at) > _bestMirrorTtl) return null;
    return best;
  }

  ///预设节点（只读）
  List<String> get presetNodes => List.unmodifiable(_presetNodes);

  ///爬取节点（只读）
  List<String> get crawledNodes => List.unmodifiable(_crawledNodes);

  ///自定义节点（config，与预设分开）
  List<String> get customNodes =>
      List.unmodifiable(config.setting.mirrorOptions.customNodes);

  ///全部节点（预设 + 爬取 + 自定义），去重
  List<String> get allNodes {
    final set = <String>{
      ..._presetNodes,
      ..._crawledNodes,
      ...customNodes,
    };
    return set.toList();
  }

  ///同步 config 的开关（启动 / 设置页变更时调用）。
  void applySettings() {
    _enabled = config.setting.mirrorOptions.enabled;
  }

  ///仅供测试：清空单例状态，隔离用例（GithubMirror 是单例，无外部重置入口）。
  @visibleForTesting
  void debugReset() {
    _presetNodes = [];
    _crawledNodes = [];
    crawledLatencies = {};
    _bestMirror = null;
    _bestMirrorAt = null;
    _enabled = true;
  }

  ///加载预设节点与爬取缓存。缓存缺失或过期（>7 天）时后台自动重爬一次。
  Future<void> load() async {
    final presetContent = await RemoteData.load('github_mirrors.hjson');
    _presetNodes = _parsePreset(presetContent);
    _crawledNodes = await _loadCrawledCache();

    if (_shouldRefreshCrawledCache()) {
      unawaited(refreshCrawledNodes());
    }
  }

  bool _shouldRefreshCrawledCache() {
    final file = File(_crawledCachePath);
    if (!file.existsSync()) return true;
    try {
      final time = file.statSync().modified;
      return DateTime.now().difference(time) > const Duration(days: 7);
    } catch (_) {
      return true;
    }
  }

  String get _crawledCachePath => p.join(AppPaths.remoteData, 'github_mirrors_crawled.json');

  ///从 github.akams.cn 拉取社区节点并预检：能测通的留下并记延迟，
  ///不通的丢弃（避免之后反复对死节点发起请求），结果缓存到本地。
  Future<List<String>> refreshCrawledNodes() async {
    final domains = await crawlFromAkams();
    final candidates = domains.map((d) => 'https://$d/').toList();
    final working = await filterWorkingNodes(candidates);
    _crawledNodes = working;
    await _saveCrawledCache(working);
    return working;
  }

  ///对候选节点统一测速一遍：能测通的留下并记录延迟，失败的一律剔除。
  @visibleForTesting
  Future<List<String>> filterWorkingNodes(List<String> candidates) async {
    final results = await Future.wait(
      candidates.map((node) async {
        final ms = await measure(node, probeUrl);
        return (node: node, ms: ms);
      }),
    );

    crawledLatencies = {
      for (final result in results)
        if (result.ms != null) result.node: result.ms!,
    };
    return results
        .where((result) => result.ms != null)
        .map((result) => result.node)
        .toList();
  }

  Future<List<String>> _loadCrawledCache() async {
    try {
      final file = File(_crawledCachePath);
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final domains = (data['domains'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      return domains.map((d) => 'https://$d/').toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCrawledCache(List<String> nodes) async {
    try {
      final domains = nodes
          .map((n) => n.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), ''))
          .toList();
      final file = File(_crawledCachePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'domains': domains}), flush: true);
    } catch (_) {}
  }

  List<String> _parsePreset(String? content) {
    if (content == null) return [];
    try {
      final decoded = hjson.hjsonDecode(content) as Map<String, dynamic>;
      final mirrors = decoded['mirrors'] as List<dynamic>? ?? const [];
      return mirrors
          .map((e) => normalizeNode(e.toString()))
          .whereType<String>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  ///统一节点格式为「镜像前缀」，非法返回 null。
  ///
  ///- 无 scheme 时补 `https://`
  ///- 保证以 `/` 结尾（前缀 + 原 URL 拼接需要分隔）
  static String? normalizeNode(String raw) {
    var node = raw.trim();
    if (node.isEmpty) return null;
    if (!node.startsWith('http://') && !node.startsWith('https://')) {
      node = 'https://$node';
    }
    if (!node.endsWith('/')) node = '$node/';
    return node;
  }

  ///URL 是否为需要加速的 github 域名。
  static bool isGithubUrl(String url) {
    final host = Uri.tryParse(url)?.host;
    return host != null && _githubHosts.contains(host);
  }

  ///返回应使用的镜像前缀；不需要加速 / 未开启 / 无节点时返回 null。
  String? prefixFor(String url) {
    if (!_enabled) return null;
    if (!isGithubUrl(url)) return null;
    final nodes = allNodes;
    final best = _bestMirror ?? (nodes.isEmpty ? null : nodes.first);
    return best;
  }

  ///把 URL 套上镜像前缀；不需加速时原样返回。
  String resolve(String url) {
    final prefix = prefixFor(url);
    if (prefix == null) return url;
    return '$prefix$url';
  }

  ///对单个节点测速（HEAD 到 前缀+探测URL），返回耗时毫秒；失败返回 null。
  Future<int?> measure(String nodePrefix, String probeUrl) async {
    final url = '$nodePrefix$probeUrl';
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _probeDio.head(url);
      final code = response.statusCode;
      if (code != null && code >= 200 && code < 400) {
        return stopwatch.elapsedMilliseconds;
      }
    } catch (_) {}
    return null;
  }

  ///对全部节点分级测速，选最快者作为后续使用的镜像（带 TTL 缓存标记）。
///
///优先测「上次已选 + 自定义 + 预设」小集合；全部失败才碰爬取的全量池
///（避免每次回退都对 77 个社区节点发起 HEAD）。返回选中的镜像前缀，
///全部不可用返回 null。
  Future<String?> selectBestMirror(String probeUrl) async {
    final previousBest = _bestMirror;
    _bestMirror = null;
    _bestMirrorAt = null;

    final priorityNodes = <String>{
      ?previousBest,
      ...customNodes,
      ..._presetNodes,
    }.toList();

    final priorityBest = await _measureFastest(priorityNodes, probeUrl);
    if (priorityBest != null) {
      _bestMirror = priorityBest;
      _bestMirrorAt = DateTime.now();
      return priorityBest;
    }

    final crawledBest = await _measureFastest(_crawledNodes, probeUrl);
    if (crawledBest != null) {
      _bestMirror = crawledBest;
      _bestMirrorAt = DateTime.now();
      return crawledBest;
    }

    return null;
  }

  ///并行对候选节点测速，返回耗时最短的节点前缀；没有可用节点返回 null。
  Future<String?> _measureFastest(List<String> nodes, String probeUrl) async {
    if (nodes.isEmpty) return null;
    final results = await Future.wait(
      nodes.map((node) async {
        final ms = await measure(node, probeUrl);
        return (node: node, ms: ms);
      }),
    );
    int? bestMs;
    String? bestNode;
    for (final result in results) {
      final ms = result.ms;
      if (ms == null) continue;
      if (bestMs == null || ms < bestMs) {
        bestMs = ms;
        bestNode = result.node;
      }
    }
    return bestNode;
  }

  // ---- 从 github.akams.cn 爬取社区节点 ----

  ///页面根地址
  static const akamsBase = 'https://github.akams.cn';

  Future<String> _fetchText(String url) async {
    final response = await _probeDio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  ///爬取 akams 页面，返回社区节点域名列表（不含 scheme）。
  Future<List<String>> crawlFromAkams() async {
    try {
      final page = await _fetchText(akamsBase);
      final chunkUrls = extractChunkUrls(page);
      for (final chunkUrl in chunkUrls) {
        final js = await _fetchText('$akamsBase$chunkUrl');
        final domains = extractNodeDomains(js);
        if (domains.isNotEmpty) return domains;
      }
    } catch (_) {}
    return [];
  }

  ///从页面 HTML 提取 Next.js chunk 脚本路径。
  @visibleForTesting
  static List<String> extractChunkUrls(String html) {
    final regex = RegExp(r'/_next/static/chunks/[a-zA-Z0-9._-]+\.js');
    return regex.allMatches(html).map((m) => m.group(0)!).toSet().toList();
  }

  ///从 JS 源码提取节点域名（`{label:"search|contribute",value:"<域名>"}`）。
  @visibleForTesting
  static List<String> extractNodeDomains(String js) {
    final regex = RegExp(
      r'\{label:"(?:search|contribute)",value:"([a-zA-Z0-9.-]+)"\}',
    );
    return regex
        .allMatches(js)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
  }
}
