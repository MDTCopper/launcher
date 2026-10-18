import 'package:copper_launcher/data/net/mod/mod_release.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';

/// 补一个缺的模组时落到哪种下载任务
enum ModFillKind {
  /// 官方列表里 `hasJava` 的模组：产物只认 `.jar`
  java,

  /// 脚本 / 资源类模组：产物只认 `.zip`
  zip,

  /// 这个版本没有可用的编译产物 —— 回落到下源码
  source,
}

/// 补不了的原因
enum ModFillSkip {
  /// 云包里没记来源（模组自己没写 `repo`）
  noSource,

  /// 官方模组列表里没有这个仓库：已下架 / 手装的 / 非官方来源
  notInOfficialList,

  /// 仓库里没有编译好的产物（Java 模组只放源码时，装了也载入不了）
  noCompiledAsset,
}

/// 一个模组的补全计划：拿它就能起对应的下载任务
class ModFillPlan {
  const ModFillPlan({
    required this.mod,
    required this.entry,
    required this.kind,
    this.release,
    this.mainAssetIndex = 0,
    this.versionMatched = false,
  });

  /// 云清单里缺的那一条（文件名与哈希以它为准）
  final CloudModEntry mod;

  /// 官方列表里按 `repo` **精确**匹配到的那一条
  final ModOfficialListEntry entry;

  final ModFillKind kind;

  /// 有编译产物时的 release；[ModFillKind.source] 时为 null
  final ModRelease? release;

  /// 主资产在 `release.assets` 里的下标（任务要用它）
  final int mainAssetIndex;

  /// release 的 tag / 名字里带上了云清单记的版本号（能对上就优先用它）
  final bool versionMatched;

  /// 下到哪儿：沿用云清单里的文件名，恢复后与包里的记录一致
  String get fileName => mod.fileName;
}

/// 决策结果：要么给一个计划，要么给一个「补不了」的原因
class ModFillDecision {
  const ModFillDecision.plan(ModFillPlan this.plan) : skip = null;
  const ModFillDecision.skip(ModFillSkip this.skip) : plan = null;

  final ModFillPlan? plan;
  final ModFillSkip? skip;

  bool get isPlan => plan != null;
}

/// 解析云清单里这个模组的仓库
///
/// 优先用模组自己写的 `repo`；没有就按内部名去官方列表里查（列表现在带 `internalName`）。
/// 两边都有时以**官方列表里真有的那个为准** —— 模组里记的仓库可能是改名前的旧名字
/// （Aquarion 记的 `Twcash/Tantros-test` 会被 GitHub 重定向到 `Twcash/Aquarion`），
/// 按官方列表的写法走最稳。内部名仍对不上就返回空串 —— 官方列表里有好几对同名不同仓库的
/// 模组，不按显示名猜
String resolveModRepo(
  CloudModEntry mod,
  Map<String, String> internalNameToRepo, {
  Set<String> officialRepos = const {},
}) {
  final recorded = (mod.source ?? '').trim();
  final internal = (mod.internalName ?? '').trim().toLowerCase();
  final byInternal = (internal.isEmpty
          ? ''
          : (internalNameToRepo[internal] ?? ''))
      .trim();

  bool known(String repo) =>
      officialRepos.isEmpty || officialRepos.contains(repo.toLowerCase());

  if (recorded.isNotEmpty && known(recorded)) return recorded;
  if (byInternal.isNotEmpty && known(byInternal)) return byInternal;
  return recorded.isNotEmpty ? recorded : byInternal;
}

/// 决定一个缺的模组怎么补回来
///
/// **纯决策**：不联网、不起任务、不看门禁 —— 只按「云清单记的来源」去官方列表里
/// 按 `repo` 精确匹配（**不按显示名猜**：官方列表里有 6 对同名不同仓库的模组），
/// 再用与模组页同一套规则挑产物（`hasJava` → `.jar`，否则 `.zip`，按体积取最大的那个；
/// 都没有就回落源码）。
///
/// [internalNameToRepo] 给「没写 `repo` 的模组」留一条按内部名查仓库的路。
/// [repoOverride] 是调用方已经解析好的仓库（比如查过 GitHub 的重定向之后），给了就不再自己解析。
///
/// [releases] 由调用方给（该仓库的 release，**按新到旧**）。云清单只记了模组的
/// 版本号、没记 release tag，所以这里先找 tag / 名字里带这个版本号的那条，
/// 找不到再用最新的一条 —— 尽量把「当时那个版本」装回来
ModFillDecision decideModFill({
  required CloudModEntry mod,
  required Iterable<ModOfficialListEntry> officialList,
  required Iterable<ModRelease> releases,
  Map<String, String> internalNameToRepo = const {},
  Set<String> officialRepos = const {},
  String? repoOverride,
}) {
  final source = (repoOverride ?? '').trim().isNotEmpty
      ? repoOverride!.trim().toLowerCase()
      : resolveModRepo(
          mod,
          internalNameToRepo,
          officialRepos: officialRepos,
        ).toLowerCase();
  if (source.isEmpty) return const ModFillDecision.skip(ModFillSkip.noSource);

  ModOfficialListEntry? entry;
  for (final candidate in officialList) {
    if (candidate.repo.trim().toLowerCase() == source) {
      entry = candidate;
      break;
    }
  }
  if (entry == null) {
    return const ModFillDecision.skip(ModFillSkip.notInOfficialList);
  }

  final extension = entry.hasJava ? '.jar' : '.zip';
  final ordered = releases.toList();

  final wanted = _meaningfulVersion(mod.version);
  if (wanted.isNotEmpty) {
    // 先找完全对得上的 tag / 名字，再放宽到「数字版本前缀一致」；
    // 两级都找不到才退回最新版（见下面的循环）
    for (final rank in const [2, 1]) {
      for (final release in ordered) {
        if (_versionMatchRank(release, wanted) != rank) continue;
        final matched = _planFor(
          mod: mod,
          entry: entry,
          release: release,
          extension: extension,
          versionMatched: true,
        );
        if (matched != null) return ModFillDecision.plan(matched);
      }
    }
  }

  for (final release in ordered) {
    final planned = _planFor(
      mod: mod,
      entry: entry,
      release: release,
      extension: extension,
      versionMatched: false,
    );
    if (planned != null) return ModFillDecision.plan(planned);
  }

  // 一条 release 都没带可用产物：Java 模组只放了源码，下下来也载入不了，
  // 与下载页的 javaDownloadBan 同一口径；非 Java 的 zip 模组回落源码
  if (entry.hasJava) {
    return const ModFillDecision.skip(ModFillSkip.noCompiledAsset);
  }
  return ModFillDecision.plan(
    ModFillPlan(mod: mod, entry: entry, kind: ModFillKind.source),
  );
}

/// 清单里记的版本号能不能拿来对 release
///
/// 很多模组在 `mod.hjson` 里写 `version: "0"`（作者没填），这种当成没记 ——
/// 不然 `tag.contains("0")` 会误中 `4.0.2` 这种版本
String _meaningfulVersion(String? version) {
  final raw = (version ?? '').trim().toLowerCase();
  if (raw.isEmpty) return '';
  final normalized = raw.replaceAll(RegExp(r'[^0-9a-z.]'), '');
  if (normalized.isEmpty) return '';
  if (RegExp(r'^0+(\.0+)*$').hasMatch(normalized)) return '';
  return raw;
}

ModFillPlan? _planFor({
  required CloudModEntry mod,
  required ModOfficialListEntry entry,
  required ModRelease release,
  required String extension,
  required bool versionMatched,
}) {
  final candidates = release.assetsOfType(extension);
  if (candidates.isEmpty) return null;
  // 体积最大的那个就是模组本体（与模组页同一个取法）
  final chosen = candidates.first;
  return ModFillPlan(
    mod: mod,
    entry: entry,
    kind: entry.hasJava ? ModFillKind.java : ModFillKind.zip,
    release: release,
    mainAssetIndex: release.assets.indexOf(chosen),
    versionMatched: versionMatched,
  );
}

/// release 的 tag 或名字里有没有提到这个版本号（`1.2.3` / `v1.2.3` / `Release 1.2.3` 都算）
/// 这个 release 的 tag / 名字与清单版本对到几成：2 = 完全一致，1 = 数字版本前缀一致，0 = 对不上
///
/// mod.hjson 里的 `version` 和 GitHub 的 tag 经常不是同一个写法（`3.0` vs `v3.0`、
/// `3.0.1`、`Aquarion-3.0-beta`），所以不直接比字符串：
/// 先看「去不区分大小写的完全相同（允许前面多个 `v`）」，再比数字版本核的前缀。
/// 数字核比较能避开 `3.0` 命中 `13.0.2` 这种字面包含误判
int _versionMatchRank(ModRelease release, String wanted) {
  final target = wanted.trim().toLowerCase();
  if (target.isEmpty) return 0;
  final wantedCore = _numericCore(target);

  for (final raw in [release.tag, release.name]) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) continue;
    if (text == target || text == 'v$target') return 2;
    if (wantedCore == null) continue;
    final core = _numericCore(text);
    if (core == null) continue;
    if (_coreIsPrefix(core, wantedCore) || _coreIsPrefix(wantedCore, core)) {
      return 1;
    }
  }
  return 0;
}

/// 版本号里的数字核：`v3.0.1-beta` → `[3, 0, 1]`
List<int>? _numericCore(String text) {
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(text);
  if (match == null) return null;
  return [for (final part in match.group(0)!.split('.')) int.parse(part)];
}

/// 一个数字核是不是另一个的前缀（`[3,0]` 与 `[3,0,1]` 视为同一版的不同写法）
bool _coreIsPrefix(List<int> base, List<int> longer) {
  if (base.length > longer.length) return false;
  for (var i = 0; i < base.length; i++) {
    if (base[i] != longer[i]) return false;
  }
  return true;
}
