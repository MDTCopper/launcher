/// 数据索引（`MDTCopper/mindustry-data-index`）的数据模型与解析
///
/// 索引是自动生成的公共数据：模组索引、每个模组的全部版本、游戏版本列表；
/// 字段形状见仓库里的 `schema/`，这里只解析启动器用得到的部分。
library;

import 'dart:convert';

import '../../../util/version_strings.dart' as version_strings;

/// 游戏版本的**闭区间**（数据索引 `gameVersionRanges` 的一项，两端都能用）
class GameVersionRange {
  const GameVersionRange({required this.from, required this.to});

  /// 区间下界（真实游戏版本号，如 `154`）
  final String from;

  /// 区间上界（如 `160.7`）
  final String to;

  /// [gameVersion] 是否落在这个区间里
  ///
  /// 空串（不知道游戏版本）一律返回 false —— 调用方自己决定「不知道」时怎么处理，
  /// 不要在这里猜成兼容
  bool contains(String gameVersion) {
    final version = gameVersion.trim();
    if (version.isEmpty) return false;
    return version_strings.compareVersion(version, from) >= 0 &&
        version_strings.compareVersion(version, to) <= 0;
  }

  static GameVersionRange? fromJson(Object? json) {
    if (json is! Map) return null;
    final from = _text(json['from']);
    final to = _text(json['to']);
    if (from.isEmpty || to.isEmpty) return null;
    return GameVersionRange(from: from, to: to);
  }
}

/// 索引列表顶层的排序项（`{key, label}`）：排序列与界面上能点的排序一一对应
class DataIndexSortOption {
  const DataIndexSortOption({required this.key, required this.label});

  final String key;
  final String label;

  static DataIndexSortOption? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = _text(json['key']);
    if (key.isEmpty) return null;
    return DataIndexSortOption(key: key, label: _text(json['label']));
  }
}

/// 模组索引里的一条（`index.json` / `community/index.json` 的一项）
class DataIndexModEntry {
  const DataIndexModEntry({
    required this.repo,
    required this.internalName,
    required this.name,
    required this.author,
    required this.description,
    required this.modType,
    required this.version,
    required this.minGameVersion,
    required this.gameVersionRanges,
    required this.iconUrl,
    required this.releasesPath,
    required this.pages,
    required this.releaseCount,
    required this.tagCount,
    required this.stars,
    required this.totalDownloads,
    required this.releaseUpdatedAt,
    required this.commitUpdatedAt,
    required this.ranks,
  });

  /// 模组仓库 `owner/name`
  final String repo;

  /// 模组内部名：与游戏 `settings.bin` 的 `mod-<内部名>-enabled` 一致
  final String internalName;

  /// 展示名（已去掉颜色标记）
  final String name;

  final String author;

  final String description;

  /// `java` / `js` / `json`
  final String modType;

  /// 模组元数据里的最新版本
  final String version;

  /// 最新版本要求的最低游戏版本
  final String minGameVersion;

  /// 最新版本适配的游戏版本闭区间
  final List<GameVersionRange> gameVersionRanges;

  final String? iconUrl;

  /// per-mod 版本文件的路径（相对数据索引根）；没有版本数据时为 null
  final String? releasesPath;

  /// 版本文件的分页信息（版本超过 200 条才有），按页序
  final List<DataIndexModPage> pages;

  final int releaseCount;

  final int tagCount;

  final int stars;

  final int totalDownloads;

  final DateTime? releaseUpdatedAt;

  final DateTime? commitUpdatedAt;

  /// 列表预计算好的排名（`heat` / `updated` / `downloads` / `stars` / `newest`），
  /// 按排序项点的时候直接取，不再自己算
  final Map<String, int> ranks;

  /// 是不是 Java 模组（决定新版本要不要取编译好的 jar）
  bool get isJava => modType == 'java';

  static DataIndexModEntry? fromJson(Object? json) {
    if (json is! Map) return null;

    final repo = _text(json['repo']);
    final name = _text(json['namePlain']).isNotEmpty
        ? _text(json['namePlain'])
        : _text(json['name']);
    if (repo.isEmpty || name.isEmpty) return null;

    final rawReleasesPath = _text(json['releasesPath']);
    return DataIndexModEntry(
      repo: repo,
      internalName: _internalNameOf(json, name),
      name: name,
      author: _preferPlain(json, 'author'),
      description: _preferPlain(json, 'description'),
      modType: _text(json['modType']),
      version: _text(json['version']),
      minGameVersion: _text(json['minGameVersion']),
      gameVersionRanges: _parseRanges(json['gameVersionRanges']),
      iconUrl: _nullableText(json['iconUrl']),
      releasesPath: rawReleasesPath.isEmpty ? null : rawReleasesPath,
      pages: _parsePages(json['pages']),
      releaseCount: _intOf(json['releaseCount']),
      tagCount: _intOf(json['tagCount']),
      stars: _intOf(json['stars']),
      totalDownloads: _intOf(json['totalDownloads']),
      releaseUpdatedAt: _dateOf(json['releaseUpdatedAt']),
      commitUpdatedAt: _dateOf(json['commitUpdatedAt']),
      ranks: _parseRanks(json['ranks']),
    );
  }
}

/// 模组版本文件的一页（`releases/<owner>/<repo>/page-N.json`）
class DataIndexModPage {
  const DataIndexModPage({
    required this.page,
    required this.count,
    required this.gameVersionRanges,
    required this.path,
  });

  final int page;

  final int count;

  /// 这一页版本的适配区间并集（先按它选页，再拉具体文件）
  final List<GameVersionRange> gameVersionRanges;

  /// 相对数据索引根的路径
  final String path;

  static DataIndexModPage? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = _text(json['path']);
    if (path.isEmpty) return null;
    return DataIndexModPage(
      page: _intOf(json['page']),
      count: _intOf(json['count']),
      gameVersionRanges: _parseRanges(json['gameVersionRanges']),
      path: path,
    );
  }
}

/// per-mod 版本文件里的一条版本
class DataIndexModVersion {
  const DataIndexModVersion({
    required this.tag,
    required this.kind,
    required this.modVersion,
    required this.minGameVersion,
    required this.gameVersionRanges,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.downloadCount,
    required this.prerelease,
    required this.removed,
    required this.releasedAt,
    required this.committedAt,
  });

  /// git tag
  final String tag;

  /// `release`（有 Release 与资产）/ `tag`（只有 tag，下载的是源码归档）
  final String kind;

  /// 这个 tag 里模组元数据的版本号
  final String modVersion;

  final String minGameVersion;

  final List<GameVersionRange> gameVersionRanges;

  /// 下载地址：Java 取编译好的 jar，其余取源码归档；删除留档的版本可能为空
  final String? downloadUrl;

  final int? sizeBytes;

  final int? downloadCount;

  final bool prerelease;

  /// 这个 tag 已从仓库删除，只留档不参与下载
  final bool removed;

  final String? releasedAt;

  final String? committedAt;

  /// 能不能拿来装：有下载地址且没被删除
  bool get downloadable => !removed && (downloadUrl ?? '').isNotEmpty;

  /// 这一版能不能用在 [gameVersion] 上
  ///
  /// 优先看索引算好的适配区间；区间缺失时退到最低版本要求；
  /// 两样都没有时不当成「不兼容」（索引缺字段不该让整个模组失去更新）
  bool supportsGameVersion(String? gameVersion) {
    final version = gameVersion?.trim() ?? '';
    if (version.isEmpty) return true;
    if (gameVersionRanges.isNotEmpty) {
      return gameVersionRanges.any((range) => range.contains(version));
    }
    if (minGameVersion.isNotEmpty) {
      return version_strings.compareVersion(version, minGameVersion) >= 0;
    }
    return true;
  }

  static DataIndexModVersion? fromJson(Object? json) {
    if (json is! Map) return null;
    final tag = _text(json['tag']);
    if (tag.isEmpty) return null;
    return DataIndexModVersion(
      tag: tag,
      kind: _text(json['kind']),
      modVersion: _text(json['modVersion']),
      minGameVersion: _text(json['minGameVersion']),
      gameVersionRanges: _parseRanges(json['gameVersionRanges']),
      downloadUrl: _nullableText(json['downloadUrl']),
      sizeBytes: _nullableIntOf(json['sizeBytes']),
      downloadCount: _nullableIntOf(json['downloadCount']),
      prerelease: json['prerelease'] == true,
      removed: json['removed'] == true,
      releasedAt: _nullableText(json['releasedAt']),
      committedAt: _nullableText(json['committedAt']),
    );
  }
}

/// per-mod 版本文件（`releases/<owner>/<repo>.json` 或其中一页）
class DataIndexModReleases {
  const DataIndexModReleases({
    required this.repo,
    required this.modType,
    required this.versions,
    required this.gameVersionRanges,
    required this.page,
    required this.pages,
  });

  final String repo;

  final String? modType;

  /// 新版本在前
  final List<DataIndexModVersion> versions;

  /// 这一页（或这个文件）版本的适配区间并集
  final List<GameVersionRange> gameVersionRanges;

  final int? page;

  final int? pages;

  /// 与 [gameVersion] 兼容、可下载的最新一版；没有返回 null
  DataIndexModVersion? newestCompatible(String? gameVersion) {
    for (final version in versions) {
      if (!version.downloadable) continue;
      if (version.supportsGameVersion(gameVersion)) return version;
    }
    return null;
  }

  static DataIndexModReleases? parse(String content) {
    final decoded = _decodeJson(content);
    if (decoded is! Map) return null;

    final rawVersions = decoded['versions'];
    final versions = <DataIndexModVersion>[
      if (rawVersions is List)
        for (final item in rawVersions) ?DataIndexModVersion.fromJson(item),
    ];

    final rawPage = decoded['page'];
    return DataIndexModReleases(
      repo: _text(decoded['repo']),
      modType: _nullableText(decoded['modType']),
      versions: versions,
      gameVersionRanges: _parseRanges(decoded['gameVersionRanges']),
      page: rawPage is num ? rawPage.toInt() : null,
      pages: decoded['pages'] is num ? (decoded['pages'] as num).toInt() : null,
    );
  }
}

/// 模组索引（`index.json` / `community/index.json`）
class DataIndexModIndex {
  DataIndexModIndex({
    required this.formatVersion,
    required this.mods,
    required this.sortOptions,
    required this.defaultSort,
  });

  final String formatVersion;

  final List<DataIndexModEntry> mods;

  final List<DataIndexSortOption> sortOptions;

  /// 默认排序列（排序项的 key）
  final String defaultSort;

  Map<String, List<DataIndexModEntry>>? _byInternalName;

  /// 按内部名找全部条目：同一个模组可能被多个仓库重新发布（同名不同仓库）
  List<DataIndexModEntry> findAllByInternalName(String internalName) {
    _byInternalName ??= _groupByInternalName();
    return _byInternalName![internalName] ?? const [];
  }

  /// 按内部名找条目：同名不同仓库时取索引里靠前的那个（官方列表在前）
  DataIndexModEntry? findByInternalName(String internalName) {
    final matches = findAllByInternalName(internalName);
    return matches.isEmpty ? null : matches.first;
  }

  Map<String, List<DataIndexModEntry>> _groupByInternalName() {
    final grouped = <String, List<DataIndexModEntry>>{};
    for (final mod in mods) {
      (grouped[mod.internalName] ??= []).add(mod);
    }
    return grouped;
  }

  static DataIndexModIndex? parse(String content) {
    final decoded = _decodeJson(content);
    if (decoded is! Map) return null;

    final rawMods = decoded['mods'];
    final mods = <DataIndexModEntry>[
      if (rawMods is List)
        for (final item in rawMods) ?DataIndexModEntry.fromJson(item),
    ];
    final rawSortOptions = decoded['sortOptions'];

    return DataIndexModIndex(
      formatVersion: _text(decoded['formatVersion']),
      mods: mods,
      sortOptions: [
        if (rawSortOptions is List)
          for (final item in rawSortOptions)
            ?DataIndexSortOption.fromJson(item),
      ],
      defaultSort: _text(decoded['defaultSort']),
    );
  }
}

Object? _decodeJson(String content) {
  try {
    return jsonDecode(content);
  } catch (_) {
    return null;
  }
}

List<GameVersionRange> _parseRanges(Object? raw) {
  if (raw is! List) return const [];
  return [for (final item in raw) ?GameVersionRange.fromJson(item)];
}

List<DataIndexModPage> _parsePages(Object? raw) {
  if (raw is! List) return const [];
  return [for (final item in raw) ?DataIndexModPage.fromJson(item)];
}

Map<String, int> _parseRanks(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
  };
}

/// 展示名 / 作者 / 描述优先取 `*Plain`（已去颜色标记），没有就退回原字段
String _preferPlain(Map json, String field) {
  final plain = _text(json['${field}Plain']);
  if (plain.isNotEmpty) return plain;
  return _text(json[field]);
}

String _internalNameOf(Map json, String name) {
  final raw = _text(json['internalName']);
  if (raw.isNotEmpty) return raw;
  return _internalNameFromName(name);
}

/// 与游戏 / 启动器一致的内部名规则：小写、空格换 `-`
String _internalNameFromName(String name) =>
    name.trim().toLowerCase().replaceAll(' ', '-');

String _text(Object? value) => value?.toString().trim() ?? '';

String? _nullableText(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

int _intOf(Object? value) => value is num ? value.toInt() : 0;

int? _nullableIntOf(Object? value) => value is num ? value.toInt() : null;

DateTime? _dateOf(Object? value) {
  final text = _text(value);
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

/// 模组条目在索引里的内部名规则（供测试与上层复用）
String dataIndexInternalNameOf(String name) => _internalNameFromName(name);
