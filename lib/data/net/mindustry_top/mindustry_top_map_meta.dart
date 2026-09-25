/// mindustry.top 资源站的地图数据模型。
///
/// 接口基址见 `mindustryTopApiBase`（app_constant.dart），请求封装见
/// `lib/util/io/mindustry_top_map_api.dart`。
///
/// 实测接口形态（2026-09）：
/// - 列表 `GET /maps/list?begin=<offset>&search=<关键词>` 每页 15 条，
///   begin 越过末尾时服务端直接返回 400（用返回条数 < 15 判断翻到头）
/// - 详情 `GET /maps/<id>.json`
/// - 下载 `GET /maps/<id>.msav`（zlib 压缩的地图本体，浏览器下载同名文件）
library;

import 'dart:convert';

/// 地图列表项（列表接口的数组元素）
class MindustryTopMapMeta {
  /// 地图 id，详情与下载接口都以它寻址
  final int id;

  final String name;

  /// 站点上的简介，可能含 Mindustry 颜色标签（如 `[gray]`），
  /// 展示前需经 `sanitizeText` / `removeColorTags` 清洗
  final String description;

  /// 最新一帖的 id，与详情接口的 `thread` 对应
  final int latestThreadId;

  /// 预览图直链（ipfs 网关上的 PNG）
  final String previewUrl;

  /// 站点展示用的标签序列（模式、内容包、游戏版本、尺寸等）
  final List<MindustryTopMapTag> tags;

  final int width;
  final int height;

  final MindustryTopMapMode mode;

  MindustryTopMapMeta({
    required this.id,
    required this.name,
    required this.description,
    required this.latestThreadId,
    required this.previewUrl,
    required this.tags,
    required this.width,
    required this.height,
    required this.mode,
  });

  factory MindustryTopMapMeta.fromJson(Map<String, dynamic> json) {
    final latestRaw = json['latest'];
    final tagList = json['tags'];
    return MindustryTopMapMeta(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: json['desc'] as String? ?? '',
      latestThreadId: latestRaw is num ? latestRaw.toInt() : int.tryParse('$latestRaw') ?? 0,
      previewUrl: json['preview'] as String? ?? '',
      tags: tagList is List
          ? [for (final it in tagList) MindustryTopMapTag.fromRaw('$it')]
          : const [],
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      mode: MindustryTopMapMode.parse(json['mode']),
    );
  }

  /// 尺寸展示文本，如 `510×510`
  String get sizeText => '$width×$height';

  /// 标签里的游戏版本（形如 `v160` 的那一条），找不到返回 null
  MindustryTopMapTag? get gameVersionTag {
    for (final tag in tags) {
      final versionMatch = RegExp(r'^v\d+(\.\d+)*$').firstMatch(tag.label);
      if (versionMatch != null) return tag;
    }
    return null;
  }
}

/// 站点标签：原始形如 `Pvp§warning`，`§` 后是站点配色名（如 warning），
/// 没有配色后缀的标签（id、`v160`、`510x510`）colorHint 为 null
class MindustryTopMapTag {
  final String label;

  /// 站点配色名，供 UI 侧映射颜色；不认识的名字按默认色处理
  final String? colorHint;

  const MindustryTopMapTag({required this.label, this.colorHint});

  factory MindustryTopMapTag.fromRaw(String raw) {
    final separatorIndex = raw.indexOf('§');
    if (separatorIndex < 0) {
      return MindustryTopMapTag(label: raw);
    }
    return MindustryTopMapTag(
      label: raw.substring(0, separatorIndex),
      colorHint: raw.substring(separatorIndex + 1),
    );
  }

  @override
  String toString() => colorHint == null ? label : '$label§$colorHint';
}

/// 地图玩法模式（列表与详情接口的 `mode` 字段）
enum MindustryTopMapMode {
  survive,
  pvp,
  sandbox,
  attack,

  /// 站点对无法判定的地图标 Unknown（如沙盒测试图）
  unknown;

  static MindustryTopMapMode parse(String? raw) {
    for (final mode in values) {
      if (mode.name.toLowerCase() == raw?.toLowerCase()) return mode;
    }
    return unknown;
  }
}

/// 地图上传者
class MindustryTopMapUser {
  final String name;

  /// 站点用户全局 id
  final String gid;

  const MindustryTopMapUser({required this.name, required this.gid});

  factory MindustryTopMapUser.fromJson(Map<String, dynamic> json) {
    return MindustryTopMapUser(
      name: json['name'] as String? ?? '',
      gid: json['gid'] as String? ?? '',
    );
  }
}

/// 地图详情（详情接口）；`tags` 字段是地图本体的元数据块，
/// 与 .msav 内部的 tags 同构（保存时间、作者、波次等随版本有增减），
/// 因此保留原始映射、常用字段做类型化访问
class MindustryTopMapDetail {
  /// 与列表项的 [MindustryTopMapMeta.id] 一致（接口里叫 `hash`）
  final int id;

  final String name;

  /// 所属帖 id（列表接口的 `latest` 指向的就是它）
  final int threadId;

  final MindustryTopMapUser? user;

  final MindustryTopMapMode mode;

  final String previewUrl;

  /// 地图本体元数据原始块（保存时间、作者、波次表等）
  final Map<String, dynamic> mapInfo;

  MindustryTopMapDetail({
    required this.id,
    required this.name,
    required this.threadId,
    required this.user,
    required this.mode,
    required this.previewUrl,
    required this.mapInfo,
  });

  factory MindustryTopMapDetail.fromJson(Map<String, dynamic> json) {
    final hashRaw = json['hash'];
    final threadRaw = json['thread'];
    final userRaw = json['user'];
    final infoRaw = json['tags'];
    return MindustryTopMapDetail(
      id: hashRaw is num ? hashRaw.toInt() : int.tryParse('$hashRaw') ?? 0,
      name: json['name'] as String? ?? '',
      threadId: threadRaw is num ? threadRaw.toInt() : int.tryParse('$threadRaw') ?? 0,
      user: userRaw is Map<String, dynamic> ? MindustryTopMapUser.fromJson(userRaw) : null,
      mode: MindustryTopMapMode.parse(json['mode']),
      previewUrl: json['preview'] as String? ?? '',
      mapInfo: infoRaw is Map<String, dynamic> ? infoRaw : const {},
    );
  }
}

/// [MindustryTopMapDetail.mapInfo] 的类型化读取：字段随游戏版本增减，
/// 按需在取值处容错，缺字段返回 null / 空集合
extension MindustryTopMapInfo on Map<String, dynamic> {
  /// 地图内部名（编辑器保存名，常与站点展示名不同，如 `Editor Playtesting`）
  String? get mapName => _text('mapname');

  String? get author => _text('author');

  String? get description => _text('description');

  int? get width => _int('width');

  int? get height => _int('height');

  /// 保存该图时的游戏 build 号（如 160）
  int? get gameBuild => _int('build');

  int? get wave => _int('wave');

  /// 最后保存时间（毫秒时间戳）
  DateTime? get savedAt {
    final milliseconds = _int('saved');
    return milliseconds == null ? null : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// 地图依赖的 mod 名单（列表元素通常是 mod 内部名）
  List<String> get mods => _stringList('mods');

  String? _text(String key) {
    final raw = this[key];
    return raw is String ? raw : null;
  }

  int? _int(String key) {
    final raw = this[key];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  List<String> _stringList(String key) {
    final raw = this[key];
    return raw is List ? [for (final it in raw) '$it'] : const [];
  }
}

/// 列表响应解码：接受 JSON 数组原文，逐条解析，坏条目跳过不炸整页
List<MindustryTopMapMeta> parseMapMetaList(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return const [];
  final decoded = jsonDecode(trimmed);
  if (decoded is! List) return const [];
  final result = <MindustryTopMapMeta>[];
  for (final entry in decoded) {
    if (entry is! Map<String, dynamic>) continue;
    try {
      result.add(MindustryTopMapMeta.fromJson(entry));
    } on TypeError {
      //字段类型与约定不符的脏数据，跳过该条
    }
  }
  return result;
}
