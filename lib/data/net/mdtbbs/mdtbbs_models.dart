/// MDTBBS 云存档的模型
///
/// **请求体字段来自官方 OpenAPI 的 `components.schemas`（已核对）**；
/// 但槽位 / 快照 / 配额这些**响应**结构在契约里没有导出（`paths` 是空的），
/// 所以这里一律「能读就读、读不出给 null」，并把原始 JSON 留在 [raw] 里 ——
/// 审核通过后跑 `test/harness/mdtbbs_probe.dart` 打一次真实响应即可核对
library;

/// 上传这份存档的原因（`reason` 字段，取值来自契约 enum）
enum CloudSaveUploadReason {
  manual('manual'),
  beforeLaunch('before_launch'),
  afterExit('after_exit'),
  periodic('periodic'),
  restore('restore'),
  conflict('conflict'),
  import('import');

  const CloudSaveUploadReason(this.wire);

  final String wire;
}

/// 云端已经有更新快照时的处理策略（`conflict_resolution` 字段）
enum CloudSaveConflictPolicy {
  /// 冲突就报错，让客户端自己决定
  normal('normal'),

  /// 另存一份冲突副本
  createConflictCopy('create_conflict_copy'),

  /// 强制覆盖当前 head，必须同时给 `confirm_current_snapshot_id`
  forceReplaceHead('force_replace_head');

  const CloudSaveConflictPolicy(this.wire);

  final String wire;
}

/// 账号信息（`/api/v1/me` 或 MindAuth UserInfo）
class MdtbbsAccount {
  const MdtbbsAccount({
    required this.subject,
    this.username,
    this.avatar,
    this.phoneVerified,
    this.raw = const {},
  });

  /// MindAuth 的稳定账号标识（`sub`）：本地只认它，不认用户名
  final String subject;

  final String? username;
  final String? avatar;

  /// 手机号验证状态：论坛的写操作会卡这一条
  final bool? phoneVerified;

  /// 原始 JSON 留着，字段变动时好核对
  final Map<String, dynamic> raw;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'username': ?username,
    'avatar': ?avatar,
    'phoneVerified': ?phoneVerified,
  };

  factory MdtbbsAccount.fromJson(Map<String, dynamic> json) {
    final verification = (json['verification'] as Map?)
        ?.cast<String, dynamic>();
    return MdtbbsAccount(
      subject: '${json['sub'] ?? json['id'] ?? ''}',
      username: json['username'] as String?,
      // 论坛 /me 给的是 `avatar_url`，不是 `avatar`
      avatar: (json['avatar_url'] ?? json['avatar']) as String?,
      phoneVerified: verification?['phone'] as bool?,
      raw: json,
    );
  }
}

/// 一次 token 交换 / 刷新的结果
class MdtbbsTokens {
  const MdtbbsTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.scope,
  });

  final String accessToken;

  /// 刷新时会轮换，必须原子保存新的那份
  final String? refreshToken;

  /// access token 剩余寿命（秒）
  final int? expiresIn;

  final String? scope;

  factory MdtbbsTokens.fromJson(Map<String, dynamic> json) => MdtbbsTokens(
    accessToken: '${json['access_token'] ?? ''}',
    refreshToken: json['refresh_token'] as String?,
    expiresIn: json['expires_in'] is num
        ? (json['expires_in'] as num).toInt()
        : null,
    scope: json['scope'] as String?,
  );
}

/// 配额与保留策略（`GET /game-saves/quota`）
///
/// 字段名**已对真实响应核过**（2026-10-03）：
/// ```json
/// {
///   "used_bytes": 0,
///   "limit_bytes": 209715200,
///   "max_file_size_bytes": 52428800,
///   "slots": { "used": 0, "limit": 100 },
///   "retention": { "max_unpinned_versions_per_slot": 20, "max_unpinned_age_days": 90 }
/// }
/// ```
class CloudSaveQuota {
  const CloudSaveQuota({
    this.usedBytes,
    this.limitBytes,
    this.maxFileSizeBytes,
    this.slotsUsed,
    this.slotsLimit,
    this.maxUnpinnedVersionsPerSlot,
    this.maxUnpinnedAgeDays,
    this.raw = const {},
  });

  final int? usedBytes;

  /// 账号总配额（实测 200 MiB）
  final int? limitBytes;

  /// **单文件上限（实测 50 MiB）** —— 带模组字节的云包很容易超，打包前拿它挡一下
  final int? maxFileSizeBytes;

  final int? slotsUsed;

  /// 槽位数量上限（实测 100）
  final int? slotsLimit;

  /// 每个槽位保留多少个未固定的历史版本
  final int? maxUnpinnedVersionsPerSlot;

  /// 未固定的历史版本保留多少天
  final int? maxUnpinnedAgeDays;

  /// 原始 JSON 留着，字段变动时好核对
  final Map<String, dynamic> raw;

  int? get remainingBytes => (limitBytes == null || usedBytes == null)
      ? null
      : limitBytes! - usedBytes!;

  /// 这个体积传得上去吗：既看单文件上限，也看剩余额度
  bool allowsFileSize(int bytes) {
    final maxFile = maxFileSizeBytes;
    if (maxFile != null && bytes > maxFile) return false;
    final remaining = remainingBytes;
    if (remaining != null && bytes > remaining) return false;
    return true;
  }

  factory CloudSaveQuota.fromJson(Map<String, dynamic> json) {
    final slots = (json['slots'] as Map?)?.cast<String, dynamic>();
    final retention = (json['retention'] as Map?)?.cast<String, dynamic>();
    return CloudSaveQuota(
      usedBytes: _intOf(json['used_bytes']),
      limitBytes: _intOf(json['limit_bytes']),
      maxFileSizeBytes: _intOf(json['max_file_size_bytes']),
      slotsUsed: _intOf(slots?['used']),
      slotsLimit: _intOf(slots?['limit']),
      maxUnpinnedVersionsPerSlot: _intOf(
        retention?['max_unpinned_versions_per_slot'],
      ),
      maxUnpinnedAgeDays: _intOf(retention?['max_unpinned_age_days']),
      raw: json,
    );
  }
}

/// 一页槽位：翻页游标在信封的 `meta.next_cursor` 里，不在 `data` 里
class CloudSaveSlotPage {
  const CloudSaveSlotPage({required this.slots, this.nextCursor});

  final List<CloudSaveSlot> slots;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

/// 一页快照历史
class CloudSaveSnapshotPage {
  const CloudSaveSnapshotPage({required this.snapshots, this.nextCursor});

  final List<CloudSaveSnapshot> snapshots;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

/// 一个云端槽位（对应本机一份数据目录）
class CloudSaveSlot {
  const CloudSaveSlot({
    required this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
    this.currentSnapshot,
    this.raw = const {},
  });

  final String id;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 云端当前 head；上传时作为 `base_snapshot_id` 的依据
  final CloudSaveSnapshot? currentSnapshot;

  final Map<String, dynamic> raw;

  String? get currentSnapshotId => currentSnapshot?.id;

  factory CloudSaveSlot.fromJson(Map<String, dynamic> json) {
    final snapshot = json['current_snapshot'] ?? json['currentSnapshot'];
    return CloudSaveSlot(
      id: '${json['id'] ?? json['slot_id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      createdAt: _timeOf(json['created_at'] ?? json['createdAt']),
      updatedAt: _timeOf(json['updated_at'] ?? json['updatedAt']),
      currentSnapshot: snapshot is Map
          ? CloudSaveSnapshot.fromJson(snapshot.cast<String, dynamic>())
          : null,
      raw: json,
    );
  }
}

/// 一个不可变快照
class CloudSaveSnapshot {
  const CloudSaveSnapshot({
    required this.id,
    this.size,
    this.sha256,
    this.createdAt,
    this.reason,
    this.pinned = false,
    this.deviceId,
    this.game,
    this.save,
    this.mods = const [],
    this.raw = const {},
  });

  final String id;
  final int? size;
  final String? sha256;
  final DateTime? createdAt;
  final String? reason;

  /// 固定后不会被保留策略自动清理
  final bool pinned;

  final String? deviceId;
  final CloudSaveGameInfo? game;
  final CloudSaveDisplayInfo? save;
  final List<CloudSaveModInfo> mods;

  final Map<String, dynamic> raw;

  factory CloudSaveSnapshot.fromJson(Map<String, dynamic> json) {
    final game = json['game'];
    final save = json['save'];
    final mods = json['mods'];
    return CloudSaveSnapshot(
      id: '${json['id'] ?? json['snapshot_id'] ?? ''}',
      size: _intOf(json['size'] ?? json['bytes']),
      sha256: json['sha256'] as String?,
      createdAt: _timeOf(json['created_at'] ?? json['createdAt']),
      reason: json['reason'] as String?,
      pinned: json['pinned'] == true,
      deviceId: json['device_id'] as String?,
      game: game is Map
          ? CloudSaveGameInfo.fromJson(game.cast<String, dynamic>())
          : null,
      save: save is Map
          ? CloudSaveDisplayInfo.fromJson(save.cast<String, dynamic>())
          : null,
      mods: [
        for (final item in (mods as List? ?? const []))
          if (item is Map)
            CloudSaveModInfo.fromJson(item.cast<String, dynamic>()),
      ],
      raw: json,
    );
  }

  /// 取云端记录：新近程度看 [createdAt]（服务端生成，比本机 mtime 可信）
  Map<String, dynamic> toJson() => {
    'id': id,
    if (size != null) 'size': size,
    if (sha256 != null) 'sha256': sha256,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (reason != null) 'reason': reason,
    'pinned': pinned,
    if (deviceId != null) 'device_id': deviceId,
    if (game != null) 'game': game!.toJson(),
    if (save != null) 'save': save!.toJson(),
    if (mods.isNotEmpty) 'mods': [for (final mod in mods) mod.toJson()],
  };
}

/// 上传体里的游戏版本信息
class CloudSaveGameInfo {
  const CloudSaveGameInfo({this.version, this.build});

  /// 例如 `v160.5`（契约 maxLength 32）
  final String? version;
  final int? build;

  Map<String, dynamic> toJson() => {
    if (version != null) 'version': version,
    if (build != null) 'build': build,
  };

  factory CloudSaveGameInfo.fromJson(Map<String, dynamic> json) =>
      CloudSaveGameInfo(
        version: json['version'] as String?,
        build: _intOf(json['build']),
      );
}

/// 上传体里的存档显示信息（列表页不用解开整个 zip 就能展示）
class CloudSaveDisplayInfo {
  const CloudSaveDisplayInfo({this.mapName, this.wave, this.playtimeSeconds});

  final String? mapName;
  final int? wave;
  final int? playtimeSeconds;

  Map<String, dynamic> toJson() => {
    if (mapName != null) 'map_name': mapName,
    if (wave != null) 'wave': wave,
    if (playtimeSeconds != null) 'playtime_seconds': playtimeSeconds,
  };

  factory CloudSaveDisplayInfo.fromJson(Map<String, dynamic> json) =>
      CloudSaveDisplayInfo(
        mapName: json['map_name'] as String?,
        wave: _intOf(json['wave']),
        playtimeSeconds: _intOf(json['playtime_seconds']),
      );
}

/// 上传体里的模组条目（契约：id / name / version / sha256）
class CloudSaveModInfo {
  const CloudSaveModInfo({
    required this.id,
    this.name,
    this.version,
    this.sha256,
  });

  /// 模组内部名（对齐 Mindustry 的 `internalName`）
  final String id;
  final String? name;
  final String? version;
  final String? sha256;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (version != null) 'version': version,
    if (sha256 != null) 'sha256': sha256,
  };

  factory CloudSaveModInfo.fromJson(Map<String, dynamic> json) =>
      CloudSaveModInfo(
        id: '${json['id'] ?? ''}',
        name: json['name'] as String?,
        version: json['version'] as String?,
        sha256: json['sha256'] as String?,
      );
}

/// 上传会话：服务端占好配额、给出去哪 PUT
class CloudSaveUploadSession {
  const CloudSaveUploadSession({
    required this.uploadId,
    required this.url,
    this.method = 'PUT',
    this.headers = const {},
    this.expiresAt,
  });

  final String uploadId;

  /// 相对 `/api/v1` 的路径（服务端给的就是相对路径）
  final String url;
  final String method;
  final Map<String, String> headers;
  final DateTime? expiresAt;

  factory CloudSaveUploadSession.fromJson(Map<String, dynamic> json) {
    final upload =
        (json['upload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final headers = (upload['headers'] as Map?) ?? const {};
    return CloudSaveUploadSession(
      uploadId: '${json['upload_id'] ?? ''}',
      url: '${upload['url'] ?? ''}',
      method: '${upload['method'] ?? 'PUT'}',
      headers: headers.map((key, value) => MapEntry('$key', '$value')),
      expiresAt: _timeOf(upload['expires_at']),
    );
  }
}

/// 下载凭据：先拿它、再按它对文件发 GET
class CloudSaveDownloadTicket {
  const CloudSaveDownloadTicket({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.size,
    this.sha256,
    this.fileName,
  });

  final String url;
  final String method;
  final Map<String, String> headers;

  /// 落地后要按它逐字节校验，对不上不能替换本机存档
  final int? size;
  final String? sha256;
  final String? fileName;

  factory CloudSaveDownloadTicket.fromJson(Map<String, dynamic> json) {
    final download =
        (json['download'] as Map?)?.cast<String, dynamic>() ?? const {};
    final headers = (download['headers'] as Map?) ?? const {};
    return CloudSaveDownloadTicket(
      url: '${download['url'] ?? ''}',
      method: '${download['method'] ?? 'GET'}',
      headers: headers.map((key, value) => MapEntry('$key', '$value')),
      size: _intOf(download['size']),
      sha256: download['sha256'] as String?,
      fileName: download['file_name'] as String?,
    );
  }
}

int? _intOf(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _timeOf(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
