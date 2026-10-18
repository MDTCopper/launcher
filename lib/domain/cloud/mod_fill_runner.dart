import 'dart:convert';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/mod_version_gate.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/mod_fill.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/mod_download_task.dart';
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
  final failed = of(ModFillStatus.failed);
  final stale = of(ModFillStatus.carriedInPackage);

  final parts = <String>[
    if (queued.isNotEmpty) '已排入下载 ${queued.length} 个（${_namesOf(queued)}）',
    if (manual.isNotEmpty) '要你自己装 ${manual.length} 个（${_namesOf(manual)}）',
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
}) async {
  final outcomes = <ModFillOutcome>[];
  final releasesByRepo = <String, List<ModRelease>>{};
  final failureByRepo = <String, String>{};

  for (final mod in missingMods) {
    if (mod.includeBytes) {
      outcomes.add(
        ModFillOutcome(mod: mod, status: ModFillStatus.carriedInPackage),
      );
      continue;
    }
    final source = (mod.source ?? '').trim();
    if (source.isEmpty) {
      outcomes.add(ModFillOutcome(mod: mod, status: ModFillStatus.noSource));
      continue;
    }

    final cacheKey = source.toLowerCase();
    var releases = releasesByRepo[cacheKey];
    if (releases == null) {
      final cachedFailure = failureByRepo[cacheKey];
      if (cachedFailure != null) {
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
      } on Object catch (error) {
        failureByRepo[cacheKey] = '$error';
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
    );
    if (!decision.isPlan) {
      outcomes.add(
        ModFillOutcome(
          mod: mod,
          status: decision.skip == ModFillSkip.noSource
              ? ModFillStatus.noSource
              : ModFillStatus.notInOfficialList,
        ),
      );
      continue;
    }

    final plan = decision.plan!;
    if (_compatible(plan.entry, version) == false) {
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
    outcomes.add(
      ModFillOutcome(mod: mod, status: ModFillStatus.queued, plan: plan),
    );
  }
  return outcomes;
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
}) async {
  onStatus?.call('读取官方模组列表');
  final List<ModOfficialListEntry> officialList;
  try {
    final response = await cio.get(githubModMetaUrl, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    officialList = [
      for (final item in jsonDecode('${response.data}') as List)
        ModOfficialListEntry.fromJson((item as Map).cast<String, dynamic>()),
    ];
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
  );

  for (final outcome in outcomes) {
    if (outcome.isQueued) {
      _queue(outcome.plan!, version);
    }
  }
  return outcomes;
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
  addLogAndPrint(
    .info,
    '补全模组：${CloudRestoreGap.displayNameOf(plan.mod)} ← ${entry.repo}'
    '（${plan.release?.tag ?? '源码'}${plan.versionMatched ? '，与清单版本一致' : ''}）',
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
