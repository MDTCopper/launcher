import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 本机云存档绑定与 profile 归属
///
/// v3 结构（**不做旧数据迁移**）：
/// ```
/// {
///   "version": 3,
///   "owners": { "<localProfileId>": "<账号 subject>" },
///   "accounts": {
///     "<subject>": {
///       "profiles": { "<localProfileId>": <CloudSyncState> }
///     }
///   }
/// }
/// ```
///
/// `owners` 是机器级归属：同一个本机数据目录同一时间只有一个账号 active，
/// 防止换账号后把 A 的本机数据传进 B 的云存档。
class CloudBindingStore {
  CloudBindingStore({
    Map<String, String>? owners,
    Map<String, Map<String, CloudSyncState>>? accounts,
  }) : owners = owners ?? {},
       accounts = accounts ?? {};

  final Map<String, String> owners;

  /// 账号 subject -> localProfileId -> 绑定
  final Map<String, Map<String, CloudSyncState>> accounts;

  static CloudBindingStore load(String path) {
    final file = File(path);
    if (!file.existsSync()) return CloudBindingStore();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map || decoded['version'] != 3) {
        return CloudBindingStore();
      }
      return _fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      // 坏文件按“没有绑定”处理；不要拿空 store 覆盖原文件
      return CloudBindingStore();
    }
  }

  static CloudBindingStore _fromJson(Map<String, dynamic> json) {
    final owners = <String, String>{};
    final rawOwners = json['owners'];
    if (rawOwners is Map) {
      for (final entry in rawOwners.entries) {
        if (entry.value is String) owners['${entry.key}'] = '${entry.value}';
      }
    }

    final accounts = <String, Map<String, CloudSyncState>>{};
    final rawAccounts = json['accounts'];
    if (rawAccounts is Map) {
      for (final account in rawAccounts.entries) {
        final rawAccount = account.value;
        if (rawAccount is! Map) continue;
        final rawProfiles = rawAccount['profiles'];
        final profilesRaw = rawProfiles is Map ? rawProfiles : rawAccount;
        final profiles = <String, CloudSyncState>{};
        for (final profile in profilesRaw.entries) {
          final state = CloudSyncState.fromJson(profile.value);
          if (state != null) profiles['${profile.key}'] = state;
        }
        accounts['${account.key}'] = profiles;
      }
    }

    return CloudBindingStore(owners: owners, accounts: accounts);
  }

  Map<String, CloudSyncState> profilesOf(String account) =>
      accounts[account] ?? const {};

  CloudSyncState? stateOf(String account, String localProfileId) =>
      accounts[account]?[localProfileId];

  void putState(String account, String localProfileId, CloudSyncState state) {
    accounts.putIfAbsent(account, () => {})[localProfileId] = state;
  }

  void removeState(String account, String localProfileId) {
    final profiles = accounts[account];
    if (profiles == null) return;
    profiles.remove(localProfileId);
    if (profiles.isEmpty) accounts.remove(account);
  }

  String? ownerOf(String localProfileId) => owners[localProfileId];

  void setOwner(String localProfileId, String account) {
    owners[localProfileId] = account;
  }

  void clearOwner(String localProfileId) {
    owners.remove(localProfileId);
  }

  void save(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final temporary = File('$path.importing');
    temporary.writeAsStringSync(
      jsonEncode({
        'version': 3,
        'owners': owners,
        'accounts': {
          for (final account in accounts.entries)
            account.key: {
              'profiles': {
                for (final profile in account.value.entries)
                  profile.key: profile.value.toJson(),
              },
            },
        },
      }),
      flush: true,
    );
    if (file.existsSync()) file.deleteSync();
    temporary.renameSync(path);
  }
}

/// 本机一份数据目录的云存档绑定
class CloudSyncState {
  const CloudSyncState({
    required this.slotId,
    this.cloudSignature,
    this.snapshotId,
    this.files = const {},
    this.boundTag,
    this.cloudTag,
    this.slotName,
    this.pendingSlotRename = false,
    this.baseline = true,
    this.profileKind = 'instance',
    this.release,
    this.build,
    this.isBe,
    this.dataPath,
    this.stale = false,
  });

  final String slotId;

  /// 云签名；旧记录没有时按 `slot:<slotId>` 派生
  final String? cloudSignature;
  final String? snapshotId;

  /// 上次同步时的逐文件 sha256；键是数据目录内相对路径
  final Map<String, String> files;

  /// 非默认存档的绑定 tag；默认存档为 null
  final String? boundTag;

  /// 最近一次从云端读到的 tag（非默认）
  final String? cloudTag;

  final String? slotName;
  final bool pendingSlotRename;
  final bool baseline;

  /// `default` / `instance` / `external`
  final String profileKind;

  final String? release;
  final int? build;
  final bool? isBe;
  final String? dataPath;
  final bool stale;

  bool get hasBaseline => baseline && files.isNotEmpty;

  bool get isDefault => profileKind == 'default';

  String get signature => cloudSignature ?? cloudSignatureForSlot(slotId);

  CloudSyncState copyWith({
    String? cloudSignature,
    String? snapshotId,
    Map<String, String>? files,
    String? boundTag,
    String? cloudTag,
    String? slotName,
    bool? pendingSlotRename,
    bool? baseline,
    String? profileKind,
    String? release,
    int? build,
    bool? isBe,
    String? dataPath,
    bool? stale,
  }) => CloudSyncState(
    slotId: slotId,
    cloudSignature: cloudSignature ?? this.cloudSignature,
    snapshotId: snapshotId ?? this.snapshotId,
    files: files ?? this.files,
    boundTag: boundTag ?? this.boundTag,
    cloudTag: cloudTag ?? this.cloudTag,
    slotName: slotName ?? this.slotName,
    pendingSlotRename: pendingSlotRename ?? this.pendingSlotRename,
    baseline: baseline ?? this.baseline,
    profileKind: profileKind ?? this.profileKind,
    release: release ?? this.release,
    build: build ?? this.build,
    isBe: isBe ?? this.isBe,
    dataPath: dataPath ?? this.dataPath,
    stale: stale ?? this.stale,
  );

  Map<String, dynamic> toJson() => {
    'slot_id': slotId,
    if (cloudSignature != null) 'cloud_signature': cloudSignature,
    if (snapshotId != null) 'snapshot_id': snapshotId,
    if (files.isNotEmpty) 'files': files,
    if (boundTag != null) 'bound_tag': boundTag,
    if (cloudTag != null) 'cloud_tag': cloudTag,
    if (slotName != null) 'slot_name': slotName,
    if (pendingSlotRename) 'pending_slot_rename': true,
    'baseline': baseline,
    'profile_kind': profileKind,
    if (release != null) 'release': release,
    if (build != null) 'build': build,
    if (isBe != null) 'is_be': isBe,
    if (dataPath != null) 'data_path': dataPath,
    if (stale) 'stale': true,
  };

  /// 兼容旧记录：值是槽位 id 字符串，或 map
  static CloudSyncState? fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return CloudSyncState(
        slotId: value,
        cloudSignature: cloudSignatureForSlot(value),
        baseline: false,
      );
    }
    if (value is! Map) return null;

    final slotId = '${value['slot_id'] ?? value['slotId'] ?? ''}';
    if (slotId.isEmpty) return null;

    final rawFiles = value['files'];
    final files = rawFiles is Map
        ? {
            for (final entry in rawFiles.entries)
              if (entry.value is String) '${entry.key}': '${entry.value}',
          }
        : const <String, String>{};
    final rawBaseline = value['baseline'];
    final baseline = rawBaseline is bool ? rawBaseline : files.isNotEmpty;
    return CloudSyncState(
      slotId: slotId,
      cloudSignature:
          value['cloud_signature'] as String? ??
          cloudSignatureForSlot(slotId),
      snapshotId: value['snapshot_id'] as String?,
      files: files,
      boundTag: value['bound_tag'] as String? ?? value['tag'] as String?,
      cloudTag: value['cloud_tag'] as String?,
      slotName: value['slot_name'] as String?,
      pendingSlotRename: value['pending_slot_rename'] == true,
      baseline: baseline,
      profileKind: '${value['profile_kind'] ?? 'instance'}',
      release: value['release'] as String?,
      build: value['build'] is int ? value['build'] as int : null,
      isBe: value['is_be'] is bool ? value['is_be'] as bool : null,
      dataPath: value['data_path'] as String?,
      stale: value['stale'] == true,
    );
  }
}

/// 云签名：槽位 ID 的派生值，槽位还在就不变
String cloudSignatureForSlot(String slotId) => 'slot:$slotId';

/// 槽位名里的 8 位短码
String cloudSignatureShort(String signature) =>
    sha256.convert(utf8.encode(signature)).toString().substring(0, 8);

/// 本机查找键：隔离实例用 instance.id，默认目录用 default，外置目录用路径哈希
String localProfileIdOf(Mindustry version) {
  if (version.isolation) {
    final id = version.id.trim();
    return id.isEmpty
        ? 'path:${shortPathHash(version.dataPath)}'
        : 'instance:$id';
  }
  if (version.hasExternalDataDir) {
    return 'external:${shortPathHash(version.dataPath)}';
  }
  return 'default';
}

String shortPathHash(String path) {
  final normalized = p.normalize(path);
  final key = Platform.isWindows ? normalized.toLowerCase() : normalized;
  return sha256.convert(utf8.encode(key)).toString().substring(0, 8);
}

class CloudProfileLockedException implements Exception {
  const CloudProfileLockedException(this.ownerSubject, {this.localProfileId});

  final String? ownerSubject;
  final String? localProfileId;

  @override
  String toString() =>
      '这个数据目录当前由账号 ${ownerSubject ?? '未知'} 使用，先覆盖归属到当前账号';
}

class CloudBindingRequiredException implements Exception {
  const CloudBindingRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudAlreadyBoundException implements Exception {
  const CloudAlreadyBoundException(this.tag);

  final String? tag;

  @override
  String toString() => '这份云存档已经绑定在 tag ${tag ?? '未知'} 上，先解绑';
}

class CloudBindCancelledException implements Exception {
  const CloudBindCancelledException();

  @override
  String toString() => '已取消绑定';
}
