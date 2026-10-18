import 'dart:async';
import 'dart:convert';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/mod_version_gate.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/mod_fill.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/mod_download_task.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 一个缺的模组最后是什么下场
enum ModFillStatus {
  /// 已排进下载队列
  queued,

  /// 云包里没记来源（模组自己没写 `repo`）
  noSource,

  /// 官方模组列表里没有这个仓库：已下架 / 手装的 / 非官方来源
  notInOfficialList,

  /// 本机这个游戏版本跑不了它（声明的最低版本与门禁对不上）
  incompatible,

  /// 仓库里没有编译好的产物（Java 模组只放源码，装了也载入不了）
  noCompiledAsset,

  /// 本来随包带了字节却没落地 —— 该重下云端快照，不是去下模组
  carriedInPackage,

  /// 拉官方列表 / release 失败
  failed,
}

/// 补一个模组的结果；界面拿它拼提示（哪些排上了、哪些只能自己装）
class ModFillOutcome {
  const ModFillOutcome({
    required this.mod,
    required this.status,
    this.plan,
    this.detail,
  });

  final CloudModEntry mod;
  final ModFillStatus status;

  /// 排上了才有：可直接起任务的计划
  final ModFillPlan? plan;

  /// 给人看的原因（兼容性说明 / 报错原文）
  final String? detail;

  bool get isQueued => status == ModFillStatus.queued;

  String get displayName => CloudRestoreGap.displayNameOf(mod);
}

/// 一句话说清补全的结果：排上几个、哪些只能自己装、哪些版本对不上
///
/// 名字最多列 3 个（通知里放不下更多），其余用「等」收掉
String describeFillOutcomes(List<ModFillOutcome> outcomes) {
  List<ModFillOutcome> of(ModFillStatus status) =>
      [for (final it in outcomes) if (it.status == status) it];

  final queued = of(ModFillStatus.queued);
  final manual = [...of(ModFillStatus.noSource), ...of(ModFillStatus.notInOfficialList)];
  final incompatible = of(ModFillStatus.incompatible);
  final noCompiledAsset = of(ModFillStatus.noCompiledAsset);
  final failed = of(ModFillStatus.failed);
  final stale = of(ModFillStatus.carriedInPackage);

  final parts = <String>[
    if (queued.isNotEmpty) '已排入下载 ${queued.length} 个（${_namesOf(queued)}）',
    if (manual.isNotEmpty) '要你自己装 ${manual.length} 个（${_namesOf(manual)}）',
    if (noCompiledAsset.isNotEmpty)
      '没有编译产物、只能自己装 ${noCompiledAsset.length} 个（${_namesOf(noCompiledAsset)}）',
    if (incompatible.isNotEmpty) '版本对不上 ${incompatible.length} 个（${_namesOf(incompatible)}）',
    if (stale.isNotEmpty) '有 ${stale.length} 个该重新下载云端快照（包里带了字节却没落地）',
    if (failed.isNotEmpty) '补不了 ${failed.length} 个（${_namesOf(failed)}）',
  ];
  return parts.isEmpty ? '没有要补的' : parts.join('；');
}

String _namesOf(List<ModFillOutcome> outcomes) {
  final names = outcomes.take(3).map((it) => it.displayName).join('、');
  return outcomes.length > 3 ? '$names 等' : names;
}

/// GitHub 走 API 认这个 UA（与模组页的 `modDownloadHeaders` 同义；
/// 那几个常量在 UI 层，域层不去引它）
const _defaultHeaders = {'User-Agent': 'MindustryModDownloader'};

/// 逐个模组定计划：**不联网、不排队**（[officialList] 与 [fetchReleases] 都由调用方给）
///
/// 同一个仓库只拉一次 release（多个缺件同源时省一遍请求，失败也记下来不重试）
Future<List<ModFillOutcome>> planModFills({
  required Iterable<CloudModEntry> missingMods,
  required Iterable<ModOfficialListEntry> officialList,
  required Mindustry version,
  required Future<List<ModRelease>> Function(String repo) fetchReleases,
  Map<String, String> internalNameToRepo = const {},
  Future<String?> Function(String repo)? resolveRepo,
}) async {
  final outcomes = <ModFillOutcome>[];
  final releasesByRepo = <String, List<ModRelease>>{};
  final failureByRepo = <String, String>{};
  final officialRepos = {
    for (final entry in officialList)
      if (entry.repo.trim().isNotEmpty) entry.repo.trim().toLowerCase(),
  };

  addLogAndPrint(.info, '补全模组：待定 ${missingMods.length} 个', tag: 'Cloud');

  for (final mod in missingMods) {
    final label = CloudRestoreGap.displayNameOf(mod);
    if (mod.includeBytes) {
      addLogAndPrint(
        .info,
        '补全模组：$label 随包带了字节却没落地，跳过（该重下云端快照）',
        tag: 'Cloud',
      );
      outcomes.add(
        ModFillOutcome(mod: mod, status: ModFillStatus.carriedInPackage),
      );
      continue;
    }
    final recorded = (mod.source ?? '').trim();
    var source = resolveModRepo(
      mod,
      internalNameToRepo,
      officialRepos: officialRepos,
    );
    if (source.isEmpty) {
      addLogAndPrint(
        .warning,
        '补全模组：$label 既没记仓库也没有内部名，只能自己装',
        tag: 'Cloud',
      );
      outcomes.add(ModFillOutcome(mod: mod, status: ModFillStatus.noSource));
      continue;
    }
    if (recorded.isEmpty) {
      addLogAndPrint(
        .info,
        '补全模组：$label 没记仓库，'
        '按内部名 ${mod.internalName} 对上 $source',
        tag: 'Cloud',
      );
    } else if (recorded.toLowerCase() != source.toLowerCase()) {
      addLogAndPrint(
        .warning,
        '补全模组：$label 记的仓库 $recorded 不在官方列表里，'
        '改用内部名 ${mod.internalName} 对应的 $source',
        tag: 'Cloud',
      );
    }
    if (officialRepos.isNotEmpty &&
        !officialRepos.contains(source.toLowerCase()) &&
        resolveRepo != null) {
      // 仓库可能只是改了名：GitHub 会把旧名重定向到新名，按新名再核一次官方列表
      final canonical = ((await resolveRepo(source)) ?? '').trim();
      if (canonical.isNotEmpty &&
          officialRepos.contains(canonical.toLowerCase())) {
        addLogAndPrint(
          .info,
          '补全模组：$label 记的仓库 $source 已改名 / 重定向到 $canonical，按它补',
          tag: 'Cloud',
        );
        source = canonical;
      }
    }
    if (officialRepos.isNotEmpty &&
        !officialRepos.contains(source.toLowerCase())) {
      addLogAndPrint(
        .warning,
        '补全模组：$label 的仓库 $source 不在官方列表里，跳过（不去白拉 release）',
        tag: 'Cloud',
      );
      outcomes.add(
        ModFillOutcome(mod: mod, status: ModFillStatus.notInOfficialList),
      );
      continue;
    }

    final cacheKey = source.toLowerCase();
    var releases = releasesByRepo[cacheKey];
    if (releases == null) {
      final cachedFailure = failureByRepo[cacheKey];
      if (cachedFailure != null) {
        addLogAndPrint(
          .warning,
          '补全模组：$label 的仓库 $source 上次拉取已失败，不再重试',
          tag: 'Cloud',
        );
        outcomes.add(
          ModFillOutcome(
            mod: mod,
            status: ModFillStatus.failed,
            detail: cachedFailure,
          ),
        );
        continue;
      }
      try {
        releases = await fetchReleases(source);
        releasesByRepo[cacheKey] = releases;
        addLogAndPrint(
          .info,
          '补全模组：$source 拉到 ${releases.length} 条 release',
          tag: 'Cloud',
        );
      } on Object catch (error) {
        failureByRepo[cacheKey] = '$error';
        addLogAndPrint(
          .warning,
          '补全模组：拉 $source 的 release 失败：$error',
          tag: 'Cloud',
        );
        outcomes.add(
          ModFillOutcome(
            mod: mod,
            status: ModFillStatus.failed,
            detail: '$error',
          ),
        );
        continue;
      }
    }

    final decision = decideModFill(
      mod: mod,
      officialList: officialList,
      releases: releases,
      internalNameToRepo: internalNameToRepo,
      officialRepos: officialRepos,
      repoOverride: source,
    );
    if (!decision.isPlan) {
      final (status, reason) = switch (decision.skip!) {
        ModFillSkip.noSource => (ModFillStatus.noSource, '没有来源'),
        ModFillSkip.notInOfficialList => (
          ModFillStatus.notInOfficialList,
          '仓库 $source 不在官方列表里',
        ),
        ModFillSkip.noCompiledAsset => (
          ModFillStatus.noCompiledAsset,
          '仓库里没有编译好的产物（Java 模组只放源码，装了也载入不了）',
        ),
      };
      addLogAndPrint(
        .warning,
        '补全模组：$label 跳过 —— $reason',
        tag: 'Cloud',
      );
      outcomes.add(
        ModFillOutcome(mod: mod, status: status, detail: reason),
      );
      continue;
    }

    final plan = decision.plan!;
    if (_compatible(plan.entry, version) == false) {
      // 官方列表的 minGameVersion 是**最新那版**的要求；清单记的是当时装的那一版。
      // 版本对得上时按当时的版本装（那版本来就在这个游戏版本上跑过），只提示一句；
      // 只有「拿不准是不是同一版」才拦下
      if (!plan.versionMatched) {
        addLogAndPrint(
          .warning,
          '补全模组：$label 要求游戏 ${plan.entry.minGameVersion}+，'
          '本机是 ${version.release}，跳过',
          tag: 'Cloud',
        );
        outcomes.add(
          ModFillOutcome(
            mod: mod,
            status: ModFillStatus.incompatible,
            plan: plan,
            detail: '它要求游戏 ${plan.entry.minGameVersion}+，本机是 ${version.release}',
          ),
        );
        continue;
      }
      addLogAndPrint(
        .warning,
        '补全模组：$label 的最新版要求 ${plan.entry.minGameVersion}+（本机 ${version.release}），'
        '但清单记的就是 ${plan.release?.tag ?? '这一版'}，按当时那版装',
        tag: 'Cloud',
      );
    }
    outcomes.add(
      ModFillOutcome(mod: mod, status: ModFillStatus.queued, plan: plan),
    );
  }

  _logFillSummary(outcomes);
  return outcomes;
}

/// 收尾一句：每个结局各几个，日志里能直接看出补全为什么没全成
void _logFillSummary(List<ModFillOutcome> outcomes) {
  int count(ModFillStatus status) =>
      outcomes.where((outcome) => outcome.status == status).length;
  addLogAndPrint(
    .info,
    '补全模组：共 ${outcomes.length} 个 —— '
    '排入下载 ${count(ModFillStatus.queued)}，'
    '无来源 ${count(ModFillStatus.noSource)}，'
    '不在官方列表 ${count(ModFillStatus.notInOfficialList)}，'
    '没有编译产物 ${count(ModFillStatus.noCompiledAsset)}，'
    '版本不兼容 ${count(ModFillStatus.incompatible)}，'
    '随包未落地 ${count(ModFillStatus.carriedInPackage)}，'
    '拉取失败 ${count(ModFillStatus.failed)}',
    tag: 'Cloud',
  );
}

/// 完整流程：拉一次官方列表 → 逐个定计划 → 排进下载队列
///
/// 列表拉不到时**一个都不排**（全部标 [ModFillStatus.failed]）—— 宁可让用户
/// 自己装，也不要拿半份数据猜着下
Future<List<ModFillOutcome>> fillMissingMods({
  required CloudRestoreGap gap,
  required Mindustry version,
  Map<String, String> headers = _defaultHeaders,
  void Function(String status)? onStatus,
  bool queueTasks = true,
}) async {
  onStatus?.call('读取官方模组列表');
  final List<ModOfficialListEntry> officialList;
  final internalNameToRepo = <String, String>{};
  try {
    final response = await cio.get(githubModMetaUrl, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final raw = jsonDecode('${response.data}') as List;
    officialList = [
      for (final item in raw)
        ModOfficialListEntry.fromJson((item as Map).cast<String, dynamic>()),
    ];
    // 官方列表带 `internalName`（2026-10 起），没写 `repo` 的模组靠它对回仓库
    for (final item in raw) {
      final map = (item as Map).cast<String, dynamic>();
      final internal = '${map['internalName'] ?? ''}'.trim().toLowerCase();
      final repo = '${map['repo'] ?? ''}'.trim();
      if (internal.isNotEmpty && repo.isNotEmpty) {
        internalNameToRepo[internal] = repo;
      }
    }
    addLogAndPrint(
      .info,
      '补全模组：官方列表 ${officialList.length} 条'
      '（${internalNameToRepo.length} 条带内部名）',
      tag: 'Cloud',
    );
  } on Object catch (error) {
    addLogAndPrint(.warning, '读官方模组列表失败：$error', tag: 'Cloud');
    return [
      for (final mod in gap.missingMods)
        ModFillOutcome(
          mod: mod,
          status: ModFillStatus.failed,
          detail: '读官方模组列表失败：$error',
        ),
    ];
  }

  final outcomes = await planModFills(
    missingMods: gap.missingMods,
    officialList: officialList,
    version: version,
    fetchReleases: (repo) => _fetchReleases(repo, headers, onStatus),
    internalNameToRepo: internalNameToRepo,
    resolveRepo: (repo) => _resolveRepoFullName(repo, headers),
  );

  if (queueTasks) {
    for (final outcome in outcomes) {
      if (outcome.isQueued) {
        _queue(outcome.plan!, version);
      }
    }
  }
  return outcomes;
}

/// 在调用方的任务里**就地**下载一个补全计划：不往任务抽屉里另起卡片
///
/// 云存档的「一张卡包住恢复 + 补全」靠它 —— 进度由调用方转发到自己的卡片上
Future<void> runFillPlanInline(
  ModFillPlan plan,
  Mindustry version, {
  required void Function(String phase) onPhase,
  void Function(double? progress)? onProgress,
  bool Function()? isCancelled,
  CancelToken? cancelToken,
}) async {
  final savePath = version.modsPath;
  final Task subtask;
  switch (plan.kind) {
    case ModFillKind.java:
      subtask = JavaModDownloadTask(
        modListMeta: plan.entry,
        modMeta: plan.release!,
        savePath: savePath,
        mainAssetIndex: plan.mainAssetIndex,
      );
    case ModFillKind.zip:
      subtask = ZipModDownloadTask(
        plan.entry,
        plan.release!,
        savePath,
        mainAssetIndex: plan.mainAssetIndex,
      );
    case ModFillKind.source:
      subtask = SourceModDownloadTask(
        modListMeta: plan.entry,
        modMeta: plan.release,
        savePath: savePath,
      );
  }

  void forwardProgress() => onProgress?.call(subtask.progress);
  subtask.addListener(forwardProgress);
  final done = _waitForTerminal(subtask);
  // 外层任务卡上的 ✕ 也要能把正在下的这一份停掉
  cancelToken?.whenCancel.then((_) => subtask.cancel());
  subtask.start();
  if (isCancelled?.call() ?? false) subtask.cancel();
  await done;
  subtask.removeListener(forwardProgress);
  if (isCancelled?.call() ?? false) {
    throw const ModFillCancelled();
  }
}

/// 补全被取消（与用户按了任务卡上的 ✕ 同一语义）
class ModFillCancelled implements Exception {
  const ModFillCancelled();

  @override
  String toString() => '补全已取消';
}

Future<void> _waitForTerminal(Task task) {
  final completer = Completer<void>();
  void changed() {
    if (task.status == TaskStatus.completed ||
        task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancel) {
      task.removeListener(changed);
      if (!completer.isCompleted) completer.complete();
    }
  }

  task.addListener(changed);
  changed();
  return completer.future;
}

/// 查仓库现在的全名：GitHub 会把改名前的旧仓库名重定向到新名字。
///
/// 云清单里记的可能是旧名（模组自己的 `mod.hjson` 写的），而官方列表用新名；
/// 这条查询把两者对上。查不到就返回 null，调用方按「不在官方列表」处理
Future<String?> _resolveRepoFullName(
  String repo,
  Map<String, String> headers,
) async {
  try {
    final response = await cio.get(
      'https://api.github.com/repos/$repo',
      headers: headers,
    );
    if (response.statusCode != 200) return null;
    final data = response.data;
    final map = data is Map ? data : jsonDecode('$data') as Map;
    final fullName = '${map['full_name'] ?? ''}'.trim();
    return fullName.isEmpty ? null : fullName;
  } on Object catch (error) {
    addLogAndPrint(
      .warning,
      '补全模组：查 $repo 现在的仓库名失败：$error',
      tag: 'Cloud',
    );
    return null;
  }
}

/// 按计划起对应的下载任务；落点用版本自己的 `mods/`
void _queue(ModFillPlan plan, Mindustry version) {
  final entry = plan.entry;
  final savePath = version.modsPath;
  switch (plan.kind) {
    case ModFillKind.java:
      addTask(
        JavaModDownloadTask(
          modListMeta: entry,
          modMeta: plan.release!,
          savePath: savePath,
          mainAssetIndex: plan.mainAssetIndex,
        ),
      );
    case ModFillKind.zip:
      addTask(
        ZipModDownloadTask(
          entry,
          plan.release!,
          savePath,
          mainAssetIndex: plan.mainAssetIndex,
        ),
      );
    case ModFillKind.source:
      addTask(
        SourceModDownloadTask(
          modListMeta: entry,
          modMeta: plan.release,
          savePath: savePath,
        ),
      );
  }
  final release = plan.release;
  final asset = release == null || plan.mainAssetIndex >= release.assets.length
      ? null
      : release.assets[plan.mainAssetIndex];
  final manifestVersion = (plan.mod.version ?? '').trim();
  final sourceNote = plan.kind == ModFillKind.source
      ? '源码按默认分支取最新${manifestVersion.isEmpty ? '' : '（清单版本 $manifestVersion）'}'
      : plan.versionMatched
      ? '与清单版本一致'
      : '用最新版本${manifestVersion.isEmpty ? '' : '（清单版本 $manifestVersion 对不上）'}';
  addLogAndPrint(
    .info,
    '补全模组：${CloudRestoreGap.displayNameOf(plan.mod)} ← ${entry.repo}'
    '（${plan.kind.name}，${release?.tag ?? '源码'}'
    '${asset == null ? '' : ' / ${asset.name}（${formatBytes(asset.size)}）'}'
    '，$sourceNote）→ ${plan.fileName}',
    tag: 'Cloud',
  );
}

Future<List<ModRelease>> _fetchReleases(
  String repo,
  Map<String, String> headers,
  void Function(String status)? onStatus,
) async {
  onStatus?.call('读取 $repo 的版本');
  final response = await cio.get<List>(
    'https://api.github.com/repos/$repo/releases?page=1&per_page=100',
    headers: headers,
  );
  return [
    for (final item in response.data ?? const [])
      ModRelease.fromJson((item as Map).cast<String, dynamic>()),
  ];
}

/// 该模组在本机这个游戏版本上能不能跑；与模组页 `compatForSelectedVersion` 同一套判定
///
/// 声明的最低版本读不出来（官方列表里出现过 `"157.1，"`）时返回 null = 判不了，
/// 那种**放行**（宁可让用户装了再发现，也不要因为一个坏字段把补全整条堵死）
bool? _compatible(ModOfficialListEntry entry, Mindustry version) {
  final modMin = double.tryParse(entry.minGameVersion);
  if (modMin == null) return null;
  final threshold = entry.hasJava
      ? ModVersionGate.instance.java.resultOf(version.releaseDouble)
      : ModVersionGate.instance.mod.resultOf(version.releaseDouble);
  return modMin >= threshold && modMin <= version.releaseDouble;
}
