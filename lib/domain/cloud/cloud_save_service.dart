import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_cloud_save_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_binding_store.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_mod_state.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

export 'package:copper_launcher/domain/cloud/cloud_binding_store.dart';

/// 一次上传的结果
class CloudSaveUploadResult {
  const CloudSaveUploadResult({
    required this.slot,
    required this.snapshot,
    required this.archiveBytes,
    required this.dropped,
    this.alreadyUpToDate = false,
    this.quotaGuard = const CloudQuotaGuard(),
  });

  final CloudSaveSlot slot;

  /// 服务端建好的快照；响应结构契约没导出，解不出时为 null（不代表失败）
  final CloudSaveSnapshot? snapshot;

  /// 上传的 zip 体积
  final int archiveBytes;

  /// 扫完到打包之间又变过、没能进包的文件
  final List<String> dropped;

  /// 本来报冲突，但比下来**云端 head 与本机这份内容相同** ⇒ 什么也不用做
  final bool alreadyUpToDate;

  /// 这次上传前为了腾空间做了什么（清理了几个旧快照 / 还剩多少额度）
  final CloudQuotaGuard quotaGuard;
}

/// 上传前的配额守卫结果
///
/// 存档一大就很容易把 200 MiB 额度顶满，而服务端的保留策略是**按版本数**清的
/// （每槽位 20 个未固定 / 90 天），不按容量 ⇒ 空间不够时得自己先删最旧的未固定快照
class CloudQuotaGuard {
  const CloudQuotaGuard({
    this.deletedSnapshots = 0,
    this.freedBytes = 0,
    this.remainingBytes,
  });

  /// 这次为腾空间删掉的旧快照数
  final int deletedSnapshots;

  /// 删掉它们腾出来的字节数（按服务端给的快照体积估）
  final int freedBytes;

  /// 这次上传之后还剩多少额度；服务端没给额度时为 null
  final int? remainingBytes;

  bool get cleaned => deletedSnapshots > 0;
}

/// 这个数据目录现在处于什么状态（页面上的状态点、自动同步判断都用它）
enum CloudSyncStatus {
  /// 云端还没有这个数据目录的槽位
  noSlot,

  /// 本机与云端一致
  upToDate,

  /// 本机改过了，等上传
  pendingUpload,

  /// 云端有新的、本机没动过 —— 可以直接下载
  pendingDownload,

  /// 两边都改过：我们没有合并语义，只能让用户选（覆盖 / 留副本）
  conflicted,

  /// 已绑定但还没有同步基线：先让用户选拉取 / 上传
  boundUnsynced,
}

/// 一侧（本机 / 云端）的「这份存档是什么」
///
/// 冲突弹窗要能写出「本机：我的图 · 波次 42 · 12 分钟前」对「云上：云图 · 波次 30 ·
/// 来自 PHONE」，靠的就是这里；两侧字段并非都齐 —— 快照那套只有云端有，
/// 游戏写在存档里的保存时刻只有本机有
class CloudSyncSide {
  const CloudSyncSide({
    this.deviceName,
    this.snapshotId,
    this.revision,
    this.mapName,
    this.wave,
    this.playtimeSeconds,
    this.savedAt,
    this.createdAt,
    this.fileCount = 0,
    this.totalBytes = 0,
    this.modCount = 0,
  });

  /// 本机侧是这台设备；云端侧是上传那台设备
  final String? deviceName;

  /// 云端快照 id 与版本号；本机侧没有
  final String? snapshotId;
  final int? revision;

  /// 最新那份存档的地图名 / 波次 / 游玩时长（秒）；读不出来给 null
  final String? mapName;
  final int? wave;
  final int? playtimeSeconds;

  /// 游戏写在存档 meta 里的保存时刻；本机侧有
  final DateTime? savedAt;

  /// 快照创建时间；云端侧有
  final DateTime? createdAt;

  /// 本机侧是清单收进来的文件数；云端侧服务端不给，恒为 0
  final int fileCount;

  /// 本机侧是清单合计（**未压缩**，zip 之后更小）；云端侧是服务端记的快照体积 ——
  /// 两侧口径不同，别直接拿来比大小
  final int totalBytes;

  /// 模组数量（云端侧是快照里的模组摘要条数）
  final int modCount;
}

/// 一次同步判断的完整结果：**状态 + 两侧各是什么 + 本机改了哪些文件**
///
/// 页面拿它画状态点、拼冲突弹窗的两侧对照，不用自己再扫一遍或猜
class CloudSyncOutcome {
  const CloudSyncOutcome({
    required this.status,
    required this.local,
    this.slot,
    this.remote,
    this.changedFiles = const [],
    this.hasBaseline = false,
  });

  final CloudSyncStatus status;

  /// 本机这一侧（清单刚扫过，永远有）
  final CloudSyncSide local;

  /// 云端槽位；null 表示这个数据目录还没传过
  final CloudSaveSlot? slot;

  /// 云端 head 那一侧；槽位还没有快照时给 null
  final CloudSyncSide? remote;

  /// 与上次同步相比变了哪些文件（数据目录内的相对路径，已排序）；
  /// **没有可用基线时给空**（没记过，或记过但没逐文件哈希）—— 没有基线就说不出「变了哪些」
  final List<String> changedFiles;

  /// 有没有**可用的逐文件基线**（上次同步时记下的那批哈希）
  ///
  /// `false` 时 [changedFiles] 一定是空，界面该说的是「没有上次同步的逐文件记录」，
  /// 而不是「一个文件都没改」
  final bool hasBaseline;

  String? get slotId => slot?.id;

  /// 云端 head 的快照 id；上传要拿它当 `base_snapshot_id`
  String? get currentSnapshotId => slot?.currentSnapshotId;
}

/// 云端 head 与本机这份**内容不同**的冲突：带上两侧信息，界面直接拿去问用户
///
/// 继承 [MdtbbsException] 是有意的 —— 既有 `on MdtbbsException` 的调用点不用改，
/// `isConflict` 与 `conflictCurrentSnapshotId` 照旧能用
class CloudSaveConflictException extends MdtbbsException {
  CloudSaveConflictException({
    required this.outcome,
    required MdtbbsException cause,
  }) : super(
         statusCode: cause.statusCode,
         code: cause.code,
         message: cause.message,
         requestId: cause.requestId,
         retryable: cause.retryable,
         details: cause.details,
       );

  /// 比过内容、确定两边不一样的当下判断；两侧信息都在里面
  final CloudSyncOutcome outcome;
}

/// 一次「恢复」的结果
class CloudSaveRestoreResult {
  const CloudSaveRestoreResult({
    required this.report,
    required this.backupPath,
    required this.backupBytes,
  });

  final CloudImportReport report;

  /// 覆盖前那份本机存档的备份（zip）；要告诉用户放在哪，出问题好退回去
  final String backupPath;

  final int backupBytes;
}

/// 上传前的体积预估：**清单合计（未压缩）**
///
/// 页面拿它显示「这次约 X MB」，好与云端剩余配额对照。**别拿它当上传字节数**：
/// `.msav` / `.msch` 在包里原样存（本来就 zlib 过），只有模组 jar 会压 ⇒ 真实包更小
class CloudUploadEstimate {
  const CloudUploadEstimate({
    required this.bytes,
    required this.fileCount,
    required this.modCount,
  });

  final int bytes;
  final int fileCount;

  /// 清单里记着的模组数（**字节默认不进包**，这里只用来提示）
  final int modCount;

  bool get isEmpty => bytes == 0;
}

/// 一份「覆盖前自备份」（`<数据根>/cloud-backups/cloud-backup-<时间戳>.zip`）
///
/// 每次覆盖性恢复都会留一份，只保留最近 [CloudSaveService.backupKeep] 份 ——
/// 但在这之前**没有任何入口能看见 / 还原它们**，等于存了却拿不出来
class CloudBackupFile {
  const CloudBackupFile({
    required this.path,
    required this.name,
    required this.bytes,
    this.createdAt,
  });

  final String path;
  final String name;
  final int bytes;

  /// 从文件名里的时间戳解出来的时刻（解不出给 null，不影响展示与还原）
  final DateTime? createdAt;
}

/// 云存档的编排层：本地云包（`CloudArchive`）↔ MDTBBS 云存档接口
///
/// 同步单元是**数据目录**：一个数据目录一个槽位，槽位名默认「设备名 · 游戏版本」。
/// 槽位 id 会在本地按数据目录记一份，用户改了槽位名也不会走丢、不会重复建
class CloudSaveService {
  CloudSaveService._();

  static const bindingFileName = 'mdtbbs_cloud_slots.json';

  /// 用例可指定目录，默认数据根
  @visibleForTesting
  static String? directoryOverride;

  static String get _root => directoryOverride ?? AppPaths.copperLauncher;

  static String get _bindingPath => p.join(_root, bindingFileName);

  /// 云包与临时文件都放这里
  ///
  /// **不能放进游戏数据目录**：Steam 云对 `saves/`、`maps/`、`mods` 等的规则是 `*`，
  /// 临时文件也会被传上去占配额
  static String get tempDir => p.join(_root, 'tmp');

  /// 「恢复」前的本机备份放这里，同样**不在游戏数据目录里**
  static String get backupDir => p.join(_root, 'cloud-backups');

  /// 清单哈希缓存（按大小与修改时间复用 sha256，见 `CloudHashCache`）
  static String get hashCachePath => p.join(_root, 'cloud-manifest-cache.json');

  /// 备份文件名前缀（清理旧备份时按它认人）
  static const backupFilePrefix = 'cloud-backup-';

  /// 备份只留最近这么多份：每次恢复留一份会一直涨
  static const backupKeep = 5;

  /// 用例可指定账号，避免依赖真实登录
  @visibleForTesting
  static String? accountOverride;

  /// 当前账号 subject；没有登录 / 还没读到资料时为 null
  static String? get currentAccountId {
    final override = accountOverride;
    if (override != null && override.trim().isNotEmpty) return override.trim();
    final subject = AccountManager.instance.subject?.trim();
    return (subject == null || subject.isEmpty) ? null : subject;
  }

  /// 云操作前确保能拿到账号；取不到就返回 null，调用方拒绝操作
  static Future<String?> _resolveAccountId() async {
    final override = accountOverride;
    if (override != null && override.trim().isNotEmpty) return override.trim();
    final accounts = AccountManager.instance;
    await accounts.ensureRestored();
    if (!accounts.isLoggedIn) return null;
    var subject = accounts.subject?.trim();
    if (subject == null || subject.isEmpty) {
      try {
        await accounts.loadAccount();
      } catch (_) {}
      subject = accounts.subject?.trim();
    }
    return (subject == null || subject.isEmpty) ? null : subject;
  }

  static CloudBindingStore _loadStore() => CloudBindingStore.load(_bindingPath);

  static void _saveStore(CloudBindingStore store) => store.save(_bindingPath);

  /// 本机同步单元：默认 / 隔离实例 / 外置目录
  static String profileIdOf(Mindustry version) => localProfileIdOf(version);

  /// 这个数据目录当前属于哪个账号；null = 未占用
  static String? ownerOf(Mindustry version) =>
      _loadStore().ownerOf(profileIdOf(version));

  static bool isLocked(Mindustry version) {
    final account = currentAccountId;
    final owner = ownerOf(version);
    return account != null && owner != null && owner != account;
  }

  /// 槽位名：非默认 `设备 · release · boundTag #短码`；默认 `设备 · 默认存档 #短码`
  static String slotNameFor({
    required String deviceName,
    required CloudGameInfo game,
    String? boundTag,
    bool isDefault = false,
    String? signatureShort,
  }) {
    final release = game.release.isNotEmpty ? game.release : game.tag;
    final tag = (boundTag == null || boundTag.trim().isEmpty)
        ? ''
        : ' · ${boundTag.trim()}';
    final base = isDefault
        ? '$deviceName · 默认存档'
        : '$deviceName · $release$tag';
    final suffix = (signatureShort == null || signatureShort.isEmpty)
        ? ''
        : ' #$signatureShort';
    final name = '$base$suffix';
    if (name.length <= 100) return name;
    final keep = 100 - suffix.length;
    if (keep <= 0) return name.substring(0, 100);
    return '${base.substring(0, keep)}$suffix';
  }

  /// 从云端槽位名里解出 `boundTag`；默认存档 / 旧命名返回 null
  static String? boundTagOfSlotName(String name) {
    final withoutShort = name.replaceFirst(RegExp(r' #[0-9a-fA-F]{8}$'), '');
    final parts = withoutShort.split(' · ');
    if (parts.length < 3) return null;
    final tag = parts.sublist(2).join(' · ').trim();
    return tag.isEmpty ? null : tag;
  }

  /// 采用云端标签：把本机隔离实例的 tag / 文件夹改成云端 `boundTag`
  ///
  /// 云槽位名、云签名、slotId 都不动；失败抛 [StateError]，调用方不要继续拉取。
  static Future<void> adoptCloudTag(Mindustry version, String cloudTag) async {
    final tag = cloudTag.trim();
    if (tag.isEmpty || tag == version.tag) return;
    final error = WindowsFileNameValidator.tagValidate(tag);
    if (error != null) throw StateError('云端标签不能用作版本名：$error');

    final fold = config.versionOptions.versionFolds.firstWhere(
      (fold) => fold.versions.contains(version),
      orElse: () => VersionFold(tag: '', path: '', versions: []),
    );
    if (fold.versions.any((other) => other != version && other.tag == tag)) {
      throw StateError('本机已有同名版本「$tag」，不能直接采用云端标签');
    }

    final oldFolder = version.foldPath;
    final newFolder = p.join(version.resolvedPath, tag);
    if (oldFolder != newFolder && Directory(oldFolder).existsSync()) {
      if (Directory(newFolder).existsSync()) {
        throw StateError('目标版本文件夹已存在：$newFolder');
      }
      await Directory(oldFolder).rename(newFolder);
      final bodyPath = version.resolvedJarPath;
      if (p.isWithin(oldFolder, bodyPath)) {
        version.jarPath = AppPaths.toStoredPath(
          p.join(newFolder, p.relative(bodyPath, from: oldFolder)),
        );
      }
    }

    version.tag = tag;
    await config.save();
    addLog(.info, '采用云端标签，本机版本改名为 [$tag]', tag: 'Cloud');
  }

  /// 采用本地标签：把云端槽位名改成当前实例 tag；云签名与 slotId 不变
  static Future<void> renameCloudSlotToLocalTag({
    required String accessToken,
    required String slotId,
    required Mindustry version,
    CancelToken? cancelToken,
  }) async {
    final signature = cloudSignatureForSlot(slotId);
    final name = slotNameFor(
      deviceName: deviceName,
      game: CloudGameInfo.fromVersion(version),
      boundTag: version.tag,
      signatureShort: cloudSignatureShort(signature),
    );
    await MdtbbsCloudSaveApi.renameSlot(
      accessToken: accessToken,
      slotId: slotId,
      name: name,
      cancelToken: cancelToken,
    );
    addLog(.info, '采用本地标签，云端槽位改名为 [$name]', tag: 'Cloud');
  }

  /// 设备名：槽位命名与「另一台设备传的」提示用
  static String get deviceName {
    final host = Platform.localHostname.trim();
    // Android 上常是 localhost，那种情况退回系统名
    if (host.isEmpty || host.toLowerCase() == 'localhost') {
      return Platform.operatingSystem;
    }
    return host;
  }

  /// 找这个数据目录**已有**的云端槽位；找不到给 null，**不创建、不按名字认领**
  static Future<CloudSaveSlot?> findSlot({
    required String accessToken,
    required Mindustry version,
    String? deviceName,
    CancelToken? cancelToken,
  }) async {
    final account = await _resolveAccountId();
    if (account == null) return null;

    final profile = profileIdOf(version);
    final store = _loadStore();
    final owner = store.ownerOf(profile);
    if (owner != null && owner != account) {
      addLog(.info, '云存档 [${version.tag}] 被账号 $owner 占用，当前账号不能操作', tag: 'Cloud');
      return null;
    }
    final state = store.stateOf(account, profile);
    if (state == null || state.slotId.isEmpty) return null;

    try {
      final slot = await MdtbbsCloudSaveApi.slot(
        accessToken: accessToken,
        slotId: state.slotId,
        cancelToken: cancelToken,
      );
      // 顺手刷新缓存里的 dataPath（tag 改名 / 数据目录搬迁后仍能显示对）
      if (state.dataPath != version.dataPath) {
        store.putState(
          account,
          profile,
          state.copyWith(dataPath: version.dataPath),
        );
        _saveStore(store);
      }
      return slot;
    } on MdtbbsException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 403) {
        // 不删、不按名字认领；只标 stale，等用户选
        if (!state.stale) {
          store.putState(account, profile, state.copyWith(stale: true));
          _saveStore(store);
        }
        addLog(.warning, '云存档绑定已失效（${error.statusCode}），等待用户处理', tag: 'Cloud');
        return null;
      }
      rethrow;
    }
  }

  /// 账号下所有槽位（把分页拉全）
  static Future<List<CloudSaveSlot>> allSlots({
    required String accessToken,
    CancelToken? cancelToken,
  }) async {
    final slots = <CloudSaveSlot>[];
    String? cursor;
    do {
      final page = await MdtbbsCloudSaveApi.listSlots(
        accessToken: accessToken,
        cursor: cursor,
        cancelToken: cancelToken,
      );
      slots.addAll(page.slots);
      cursor = page.nextCursor;
    } while (cursor != null && cursor.isNotEmpty);
    return slots;
  }

  /// 把当前账号的数据目录绑到指定槽位（供拉取 / 上传在完成对话框后调用）
  static void bindSlot(Mindustry version, String slotId) {
    final account = currentAccountId;
    if (account == null) return;
    final profile = profileIdOf(version);
    final store = _loadStore();
    final owner = store.ownerOf(profile);
    if (owner != null && owner != account) {
      throw CloudProfileLockedException(owner, localProfileId: profile);
    }
    final isDefault = profile == 'default';
    final signature = cloudSignatureForSlot(slotId);
    store.putState(
      account,
      profile,
      CloudSyncState(
        slotId: slotId,
        cloudSignature: signature,
        boundTag: isDefault ? null : version.tag,
        cloudTag: isDefault ? null : version.tag,
        slotName: slotNameFor(
          deviceName: deviceName,
          game: CloudGameInfo.fromVersion(version),
          boundTag: version.tag,
          isDefault: isDefault,
          signatureShort: cloudSignatureShort(signature),
        ),
        baseline: false,
        profileKind: isDefault ? 'default' : 'instance',
        release: version.release,
        build: version.versionNumber ?? version.releaseInt,
        isBe: version.isBe,
        dataPath: version.dataPath,
      ),
    );
    store.setOwner(profile, account);
    _saveStore(store);
  }

  /// 解绑当前数据目录（只删本机绑定，不动云端 / 本机存档）
  static void unbind(Mindustry version) {
    final account = currentAccountId;
    if (account == null) return;
    final profile = profileIdOf(version);
    final store = _loadStore();
    final owner = store.ownerOf(profile);
    if (owner != null && owner != account) {
      throw CloudProfileLockedException(owner, localProfileId: profile);
    }
    store.removeState(account, profile);
    store.clearOwner(profile);
    _saveStore(store);
  }

  /// 把当前数据目录的 active owner 覆盖为当前账号
  static void takeover(Mindustry version) {
    final account = currentAccountId;
    if (account == null) return;
    final profile = profileIdOf(version);
    final store = _loadStore();
    final owner = store.ownerOf(profile);
    if (owner != null && owner != account) {
      // 原 owner 的绑定保留为 dormant；只改归属
      store.setOwner(profile, account);
      _saveStore(store);
      addLog(.info, '云存档归属改为账号 $account（原 $owner）', tag: 'Cloud');
    }
  }

  /// 这份云存档在本机绑到了哪个 profile；没绑返回 null
  static String? profileIdBoundToSlot(String slotId) {
    final account = currentAccountId;
    if (account == null) return null;
    for (final entry in _loadStore().profilesOf(account).entries) {
      if (entry.value.slotId == slotId) return entry.key;
    }
    return null;
  }

  /// 某个 profile 对应的本机版本；default 取第一个未隔离版本
  static Mindustry? versionOfProfile(String profileId) {
    for (final fold in config.versionOptions.versionFolds) {
      for (final version in fold.versions) {
        if (profileIdOf(version) == profileId) return version;
      }
    }
    return null;
  }

  /// 丢弃一个失效 profile 的绑定（实例已经不在了）
  static void discardProfileBinding(String profileId) {
    final account = currentAccountId;
    if (account == null) return;
    final store = _loadStore();
    store.removeState(account, profileId);
    store.clearOwner(profileId);
    _saveStore(store);
  }

  /// 按发布号或 tag 找本机已有的版本
  static Mindustry? findInstalledVersion(String releaseOrTag) {
    final wanted = releaseOrTag.trim();
    if (wanted.isEmpty) return null;
    for (final fold in config.versionOptions.versionFolds) {
      for (final version in fold.versions) {
        if (version.release.trim() == wanted || version.tag.trim() == wanted) {
          return version;
        }
      }
    }
    return null;
  }

  /// 槽位名里的发布号：`设备名 · v160.5`，设备名自带分隔时取最后一段
  static String releaseFromSlotName(String name) {
    final index = name.lastIndexOf(' · ');
    return (index < 0 ? name : name.substring(index + 3)).trim();
  }

  /// 取当前绑定槽位；没有绑定时只有 [allowCreate] 才建新槽
  ///
  /// 自动同步不允许建槽；手动上传 / 显式新建才允许。
  static Future<CloudSaveSlot> resolveSlot({
    required String accessToken,
    required Mindustry version,
    String? deviceName,
    bool allowCreate = true,
    CancelToken? cancelToken,
  }) async {
    final account = await _resolveAccountId();
    if (account == null) throw const CloudBindingRequiredException('未登录 BBS，无法操作云存档');
    final profile = profileIdOf(version);
    final store = _loadStore();
    final owner = store.ownerOf(profile);
    if (owner != null && owner != account) {
      throw CloudProfileLockedException(owner, localProfileId: profile);
    }

    final state = store.stateOf(account, profile);
    if (state != null) {
      try {
        return await MdtbbsCloudSaveApi.slot(
          accessToken: accessToken,
          slotId: state.slotId,
          cancelToken: cancelToken,
        );
      } on MdtbbsException catch (error) {
        if (error.statusCode == 404 || error.statusCode == 403) {
          store.putState(account, profile, state.copyWith(stale: true));
          _saveStore(store);
          throw const CloudBindingRequiredException('云存档绑定已失效，先重新选择槽位');
        }
        rethrow;
      }
    }

    if (!allowCreate) {
      throw const CloudBindingRequiredException('还没有绑定云存档');
    }

    final name = deviceName ?? CloudSaveService.deviceName;
    final isDefault = profile == 'default';
    final baseName = slotNameFor(
      deviceName: name,
      game: CloudGameInfo.fromVersion(version),
      boundTag: version.tag,
      isDefault: isDefault,
    );
    final created = await MdtbbsCloudSaveApi.createSlot(
      accessToken: accessToken,
      name: baseName,
      cancelToken: cancelToken,
    );
    final signature = cloudSignatureForSlot(created.id);
    final short = cloudSignatureShort(signature);
    var slotName = baseName;
    try {
      final withShort = slotNameFor(
        deviceName: name,
        game: CloudGameInfo.fromVersion(version),
        boundTag: version.tag,
        isDefault: isDefault,
        signatureShort: short,
      );
      await MdtbbsCloudSaveApi.renameSlot(
        accessToken: accessToken,
        slotId: created.id,
        name: withShort,
        cancelToken: cancelToken,
      );
      slotName = withShort;
    } catch (error) {
      addLog(.warning, '槽位名补短码失败：${removeNewlines('$error')}', tag: 'Cloud');
    }

    store.putState(
      account,
      profile,
      CloudSyncState(
        slotId: created.id,
        cloudSignature: signature,
        boundTag: isDefault ? null : version.tag,
        cloudTag: isDefault ? null : version.tag,
        slotName: slotName,
        baseline: false,
        profileKind: isDefault ? 'default' : 'instance',
        release: version.release,
        build: version.versionNumber ?? version.releaseInt,
        isBe: version.isBe,
        dataPath: version.dataPath,
      ),
    );
    store.setOwner(profile, account);
    _saveStore(store);
    return created;
  }

  static Future<CloudSaveQuota> quota({
    required String accessToken,
    CancelToken? cancelToken,
  }) => MdtbbsCloudSaveApi.quota(
    accessToken: accessToken,
    cancelToken: cancelToken,
  );

  static Future<CloudSaveSnapshotPage> snapshots({
    required String accessToken,
    required String slotId,
    CancelToken? cancelToken,
  }) => MdtbbsCloudSaveApi.listSnapshots(
    accessToken: accessToken,
    slotId: slotId,
    cancelToken: cancelToken,
  );

  /// 把这个版本的数据目录打包上传
  ///
  /// 上传的就是 `CloudArchive` 打的 zip（服务端只当不可变 blob 存）。冲突靠
  /// [CloudSaveConflictPolicy] 决定：默认 `normal`（不匹配就报错让上层处理），
  /// 由上层拿着当前 head 再决定重试还是强制覆盖
  static Future<CloudSaveUploadResult> upload({
    required String accessToken,
    required Mindustry version,
    String? deviceName,
    CloudSaveUploadReason reason = CloudSaveUploadReason.manual,
    CloudSaveConflictPolicy conflictPolicy = CloudSaveConflictPolicy.normal,
    String? confirmCurrentSnapshotId,
    bool includePreviews = false,
    bool includeModBytes = false,
    bool Function(CloudModEntry mod)? includeBytesWhen,
    bool allowCreateSlot = true,
    void Function(String status)? onStatus,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final name = deviceName ?? CloudSaveService.deviceName;
    onStatus?.call('查云端槽位');
    final slot = await resolveSlot(
      accessToken: accessToken,
      version: version,
      deviceName: name,
      allowCreate: allowCreateSlot,
      cancelToken: cancelToken,
    );

    final directory = Directory(tempDir);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final archivePath = p.join(
      tempDir,
      'cloud-upload-${DateTime.now().millisecondsSinceEpoch}.zip',
    );

    try {
      onStatus?.call('打包本机存档');
      final export = await _exportWithCache(
        version: version,
        outputPath: archivePath,
        deviceName: name,
        includePreviews: includePreviews,
        includeModBytes: includeModBytes,
        includeBytesWhen: includeBytesWhen,
        onStatus: onStatus,
      );

      final bytes = File(archivePath).readAsBytesSync();
      final sha256 = sha256OfBytes(bytes);

      onStatus?.call('检查云端空间');
      final guard = await _makeRoomForUpload(
        accessToken: accessToken,
        slot: slot,
        newBytes: bytes.length,
        onStatus: onStatus,
        cancelToken: cancelToken,
      );

      onStatus?.call('申请上传额度');
      final CloudSaveUploadSession session;
      try {
        session = await MdtbbsCloudSaveApi.createUpload(
          accessToken: accessToken,
          slotId: slot.id,
          sha256: sha256,
          size: bytes.length,
          baseSnapshotId: slot.currentSnapshotId,
          reason: reason,
          conflictPolicy: conflictPolicy,
          confirmCurrentSnapshotId: confirmCurrentSnapshotId,
          game: CloudSaveGameInfo(
            version: version.release,
            build: version.versionNumber ?? version.releaseInt,
          ),
          // 带上「本机在玩哪张图」：云端列表与冲突对照都靠它，不带就全是 null
          save: _displayInfoOf(_newestSave(export.manifest)?.meta),
          mods: _modsOf(export.manifest),
          deviceId: name,
          cancelToken: cancelToken,
        );
      } on MdtbbsException catch (error) {
        // 冲突先比内容再定：云端 head 与本机这份逐字节相同（同 sha256）就不是冲突 ——
        // 常见于「绑定丢了 / 换设备重传 / 上次传成功但没记下状态」这些其实没变的情况
        if (!error.isConflict) rethrow;
        final head = await MdtbbsCloudSaveApi.slot(
          accessToken: accessToken,
          slotId: slot.id,
          cancelToken: cancelToken,
        );
        if (head.currentSnapshot?.sha256 != sha256) {
          throw CloudSaveConflictException(
            cause: error,
            outcome: outcomeOf(
              slot: head,
              state: localState(version),
              manifest: export.manifest,
            ),
          );
        }

        addLog(.info, '云端 head 与本机这份内容相同，按已同步处理', tag: 'Cloud');
        _rememberSynced(
          version,
          slotId: slot.id,
          snapshotId: head.currentSnapshotId,
          files: export.manifest.fileHashes,
        );
        return CloudSaveUploadResult(
          slot: slot,
          snapshot: head.currentSnapshot,
          archiveBytes: bytes.length,
          dropped: export.dropped,
          alreadyUpToDate: true,
        );
      }

      onStatus?.call('上传云包');
      // 会话一建好，服务端就替我们占着配额 ⇒ 取消 / 失败都必须把它交回去。
      // 不交的话那笔额度要等它自己过期，用户看到的是「刚传失败了，怎么又传不了」
      final CloudSaveSnapshot? snapshot;
      try {
        await MdtbbsCloudSaveApi.putUploadBytes(
          accessToken: accessToken,
          session: session,
          bytes: bytes,
          onSendProgress: onSendProgress,
          cancelToken: cancelToken,
        );

        onStatus?.call('等云端确认');
        snapshot = await MdtbbsCloudSaveApi.commitUpload(
          accessToken: accessToken,
          uploadId: session.uploadId,
          cancelToken: cancelToken,
        );
      } on Object {
        await _releaseUploadQuietly(
          accessToken: accessToken,
          uploadId: session.uploadId,
        );
        rethrow;
      }

      // 记下「同步到哪个快照」：commit 的响应解不出快照时问一次槽位拿 head id，
      // 否则下一次状态判断会把「刚传上去的」误报成「云端有新的」
      final headId =
          snapshot?.id ??
          (await MdtbbsCloudSaveApi.slot(
            accessToken: accessToken,
            slotId: slot.id,
            cancelToken: cancelToken,
          )).currentSnapshotId;
      _rememberSynced(
        version,
        slotId: slot.id,
        snapshotId: headId,
        files: export.manifest.fileHashes,
      );

      return CloudSaveUploadResult(
        slot: slot,
        snapshot: snapshot,
        archiveBytes: bytes.length,
        dropped: export.dropped,
        quotaGuard: guard,
      );
    } finally {
      _deleteQuietly(archivePath);
    }
  }

  /// 把没用完的上传会话交回去（服务端据此释放它占的配额）
  ///
  /// 收尾动作，尽力而为：**不带原来那个 cancelToken** —— 用户取消时它已经取消了，
  /// 拿它发请求会立刻再被取消；失败也只记日志，别盖住真正的错
  static Future<void> _releaseUploadQuietly({
    required String accessToken,
    required String uploadId,
  }) async {
    try {
      await MdtbbsCloudSaveApi.cancelUpload(
        accessToken: accessToken,
        uploadId: uploadId,
      );
      addLog(.info, '已交回未完成的上传会话：$uploadId', tag: 'Cloud');
    } on Object catch (error) {
      addLog(.warning, '交回上传会话失败（$uploadId）：$error', tag: 'Cloud');
    }
  }

  /// 上传前看额度够不够；不够就删**最旧的未固定快照**腾地方
  ///
  /// 服务端的保留策略按版本数清（每槽位 20 个未固定 / 90 天），**不按容量** ⇒
  /// 存档一大就会顶满 200 MiB。这里只做两件事：
  /// - 额度够 / 读不到额度（服务端没给、请求失败）⇒ 直接放行，交给服务端判
  /// - 额度不够 ⇒ 从最旧的未固定快照开始删（**固定的与当前 head 不碰**），
  ///   删完还差就抛 [MdtbbsException]（码 `QUOTA_INSUFFICIENT`），**不上传**
  static Future<CloudQuotaGuard> _makeRoomForUpload({
    required String accessToken,
    required CloudSaveSlot slot,
    required int newBytes,
    void Function(String status)? onStatus,
    CancelToken? cancelToken,
  }) async {
    final CloudSaveQuota quota;
    try {
      quota = await MdtbbsCloudSaveApi.quota(
        accessToken: accessToken,
        cancelToken: cancelToken,
      );
    } catch (error) {
      addLog(
        .warning,
        '读不到云端配额，跳过空间检查：${removeNewlines('$error')}',
        tag: 'Cloud',
      );
      return const CloudQuotaGuard();
    }

    final limit = quota.limitBytes;
    final used = quota.usedBytes;
    // 服务端没给额度就别拿猜出来的数字拦玩家
    if (limit == null || used == null) {
      return CloudQuotaGuard(remainingBytes: quota.remainingBytes);
    }
    if (used + newBytes <= limit) {
      return CloudQuotaGuard(remainingBytes: limit - used - newBytes);
    }

    onStatus?.call('云端空间不够，清理旧快照');
    final page = await MdtbbsCloudSaveApi.listSnapshots(
      accessToken: accessToken,
      slotId: slot.id,
      limit: 100,
      cancelToken: cancelToken,
    );
    final head = slot.currentSnapshotId;
    final candidates =
        page.snapshots.where((item) => !item.pinned && item.id != head).toList()
          ..sort(
            (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
          );

    var freed = 0;
    var deleted = 0;
    for (final snapshot in candidates) {
      if (used + newBytes - freed <= limit) break;
      try {
        await MdtbbsCloudSaveApi.deleteSnapshot(
          accessToken: accessToken,
          slotId: slot.id,
          snapshotId: snapshot.id,
          cancelToken: cancelToken,
        );
      } catch (error) {
        addLog(
          .warning,
          '删旧快照 ${snapshot.id} 失败：${removeNewlines('$error')}',
          tag: 'Cloud',
        );
        continue;
      }
      freed += snapshot.size ?? 0;
      deleted++;
      addLog(
        .info,
        '云端空间不够，删掉第 ${snapshot.revision ?? 0} 版旧快照（${snapshot.size ?? 0} 字节）',
        tag: 'Cloud',
      );
    }

    final stillShort = used + newBytes - freed - limit;
    if (stillShort > 0) {
      throw MdtbbsException(
        code: 'QUOTA_INSUFFICIENT',
        message:
            '云端空间不够：这次要 ${formatBytes(newBytes)}，'
            '清掉 $deleted 个旧快照后还差 ${formatBytes(stillShort)}；'
            '先把要长期留的版本固定住、再删掉一些旧快照后重试',
      );
    }
    return CloudQuotaGuard(
      deletedSnapshots: deleted,
      freedBytes: freed,
      remainingBytes: limit - (used + newBytes - freed),
    );
  }

  /// 把某个快照拉下来并解进本机数据目录
  ///
  /// 严格按官方要求：**先落临时文件 → 校验字节数与 sha256 → 才交给解包**；
  /// 解包按 [mode] 处理同名文件；**默认整份覆盖**，不留 `-cloud-` 副本。
  /// `settings.bin` 也在这条路上当普通文件同步（含键位 / UI / 存档标题）
  static Future<CloudImportReport> download({
    required String accessToken,
    required Mindustry version,
    required String slotId,
    required String snapshotId,
    CloudImportMode mode = CloudImportMode.overwrite,
    HttpStatusCallback? onStatus,
    CancelToken? cancelToken,
  }) async {
    final account = await _resolveAccountId();
    if (account == null) {
      throw const MdtbbsException(message: '未登录 BBS，不能拉取云存档');
    }
    final profile = profileIdOf(version);
    final owner = _loadStore().ownerOf(profile);
    if (owner != null && owner != account) {
      throw CloudProfileLockedException(owner, localProfileId: profile);
    }
    final tempPath = await _fetchSnapshot(
      accessToken: accessToken,
      slotId: slotId,
      snapshotId: snapshotId,
      onStatus: onStatus,
      cancelToken: cancelToken,
    );
    try {
      final reader = await CloudArchiveReader.open(tempPath);
      _validateCloudManifest(
        reader.manifest,
        version: version,
        slotId: slotId,
      );
      final report = await reader.extractTo(
        dataPath: version.dataPath,
        mode: mode,
        backupDir: _campaignBackupDir(),
      );
      await _applyModStatesQuietly(version, reader.manifest);
      if (report.rejected.isEmpty) {
        _rememberSynced(
          version,
          slotId: slotId,
          snapshotId: snapshotId,
          files: reader.manifest.fileHashes,
        );
      }
      return report;
    } finally {
      _deleteQuietly(tempPath);
    }
  }

  /// 下载 / 恢复前校验归属与云签名；不通过就不解包
  static void _validateCloudManifest(
    CloudManifest manifest, {
    required Mindustry version,
    required String slotId,
  }) {
    final account = currentAccountId;
    if (account == null) {
      throw const MdtbbsException(message: '未登录 BBS，不能恢复云存档');
    }
    final manifestAccount = manifest.account?.trim();
    if (manifestAccount != null &&
        manifestAccount.isNotEmpty &&
        manifestAccount != account) {
      throw MdtbbsException(
        message: '这份云存档属于账号 $manifestAccount，不是当前账号',
      );
    }
    final expected = localState(version)?.signature ?? cloudSignatureForSlot(slotId);
    final actual = manifest.cloudSignature?.trim();
    if (actual != null && actual.isNotEmpty && actual != expected) {
      throw const MdtbbsException(message: '这是另一份云存档，不能覆盖当前绑定');
    }
  }

  /// 用云端快照**覆盖本机**这份数据目录（页面上那个「恢复」）
  ///
  /// 覆盖前先把本机这份导出成 zip 存进 [backupDir]；**备份失败就中止** ——
  /// 不能在没有退路的情况下盖掉玩家的存档。
  /// `settings.bin` 与存档一样**逐字节落地**（含键位 / UI / 存档标题），
  /// 我们不再自己解码改写它
  static Future<CloudSaveRestoreResult> restore({
    required String accessToken,
    required Mindustry version,
    required String slotId,
    required String snapshotId,
    void Function(String status)? onStatus,
    HttpStatusCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final account = await _resolveAccountId();
    if (account == null) {
      throw const MdtbbsException(message: '未登录 BBS，不能恢复云存档');
    }
    final profile = profileIdOf(version);
    final owner = _loadStore().ownerOf(profile);
    if (owner != null && owner != account) {
      throw CloudProfileLockedException(owner, localProfileId: profile);
    }

    onStatus?.call('备份本机存档');
    final backup = await _backupForRestore(version);

    onStatus?.call('下载云端快照');
    final tempPath = await _fetchSnapshot(
      accessToken: accessToken,
      slotId: slotId,
      snapshotId: snapshotId,
      onStatus: onProgress,
      cancelToken: cancelToken,
    );

    try {
      onStatus?.call('覆盖本机存档');
      final reader = await CloudArchiveReader.open(tempPath);
      _validateCloudManifest(reader.manifest, version: version, slotId: slotId);
      final report = await reader.extractTo(
        dataPath: version.dataPath,
        mode: CloudImportMode.overwrite,
      );
      await _applyModStatesQuietly(version, reader.manifest);
      _pruneBackups();
      // 落干净了才记「同步到这个快照」；有拒收说明本机与云上并不一致，别谎报
      if (report.rejected.isEmpty) {
        _rememberSynced(
          version,
          slotId: slotId,
          snapshotId: snapshotId,
          files: reader.manifest.fileHashes,
        );
      }
      return CloudSaveRestoreResult(
        report: report,
        backupPath: backup.path,
        backupBytes: backup.bytes,
      );
    } finally {
      _deleteQuietly(tempPath);
    }
  }

  /// 这次上传大概多大（清单合计、未压缩）与有几份文件 / 几个模组
  ///
  /// 给页面显示「这次约 X MB」用。走哈希缓存（真数据热扫约 0.67 s）；
  /// 真上传时还会再扫一次 —— 那次要的就是哈希，这里只为显示
  static Future<CloudUploadEstimate> estimateUpload(
    Mindustry version, {
    bool Function(CloudModEntry mod)? includeBytesWhen,
  }) async {
    final cache = CloudHashCache.load(hashCachePath);
    try {
      final manifest = await CloudManifest.scan(
        version: version,
        deviceName: deviceName,
        cache: cache,
        includeBytesWhen: includeBytesWhen,
      );
      var bytes = 0;
      for (final entry in manifest.includedFiles) {
        bytes += entry.size;
      }
      // 随包带的模组字节也算进去（默认不带，带了就占配额）
      for (final mod in manifest.includedModBytes) {
        bytes += mod.size;
      }
      return CloudUploadEstimate(
        bytes: bytes,
        fileCount: manifest.includedFiles.length,
        modCount: manifest.mods.length,
      );
    } finally {
      cache.save();
    }
  }

  /// 列出本机自备份，**最新在前**
  ///
  /// 文件名里就是时间戳（`cloud-backup-2026-10-15T19-30-00.zip`），所以按名字倒序
  /// 就是时间倒序 —— 与 [_pruneBackups] 的清理顺序同一套口径
  static String get _accountBackupDir {
    final account = currentAccountId;
    return account == null ? backupDir : p.join(backupDir, account);
  }

  static List<CloudBackupFile> backups() {
    final directory = Directory(_accountBackupDir);
    if (!directory.existsSync()) return const [];
    final files =
        [
          for (final entity in directory.listSync())
            if (entity is File &&
                p.basename(entity.path).startsWith(backupFilePrefix))
              entity,
        ]..sort((a, b) => b.path.compareTo(a.path));
    return [
      for (final file in files)
        CloudBackupFile(
          path: file.path,
          name: p.basename(file.path),
          bytes: file.lengthSync(),
          createdAt: _stampOf(p.basename(file.path)),
        ),
    ];
  }

  /// 用某份自备份**覆盖**本机数据目录
  ///
  /// 与云端恢复同一条规矩：**覆盖前先留底**（那份新的自备份就是这次的后路，
  /// 所以「还原」本身也能再退回去）。**不动本地同步记录** —— 本机内容已经与云端 head
  /// 不一致了，之后该判成待上传 / 冲突由状态机去说，别在这里谎报已同步
  static Future<CloudSaveRestoreResult> restoreBackup({
    required Mindustry version,
    required String backupPath,
  }) async {
    if (!File(backupPath).existsSync()) {
      throw const MdtbbsException(message: '这份自备份已经不在了');
    }
    final safety = await _backupForRestore(version);
    final extracted = await _extract(
      backupPath,
      version: version,
      mode: CloudImportMode.overwrite,
    );
    _pruneBackups();
    addLogAndPrint(
      .info,
      '用本机自备份还原：${p.basename(backupPath)}',
      tag: 'Cloud',
    );
    return CloudSaveRestoreResult(
      report: extracted.report,
      backupPath: safety.path,
      backupBytes: safety.bytes,
    );
  }

  /// 从备份文件名里解出时刻；解不出给 null（不影响展示与还原）
  static DateTime? _stampOf(String name) {
    final raw = name.substring(
      backupFilePrefix.length,
      name.length - (name.endsWith('.zip') ? 4 : 0),
    );
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})',
    ).firstMatch(raw);
    if (match == null) return null;
    return DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }

  /// 固定 / 取消固定：固定的快照不会被服务端的保留策略清掉
  static Future<void> setSnapshotPinned({
    required String accessToken,
    required String slotId,
    required String snapshotId,
    required bool pinned,
    CancelToken? cancelToken,
  }) => MdtbbsCloudSaveApi.setSnapshotPinned(
    accessToken: accessToken,
    slotId: slotId,
    snapshotId: snapshotId,
    pinned: pinned,
    cancelToken: cancelToken,
  );

  /// 取下载凭据 → 下到临时文件 → 校验字节数与 sha256，返回那个临时文件
  static Future<String> _fetchSnapshot({
    required String accessToken,
    required String slotId,
    required String snapshotId,
    HttpStatusCallback? onStatus,
    CancelToken? cancelToken,
  }) async {
    final ticket = await MdtbbsCloudSaveApi.createDownload(
      accessToken: accessToken,
      slotId: slotId,
      snapshotId: snapshotId,
      cancelToken: cancelToken,
    );

    final directory = Directory(tempDir);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final tempPath = p.join(tempDir, 'cloud-download-$snapshotId.zip');

    // 校验不过（或下载中断）就把半截文件删掉，别留下一个「看着像下好了」的包
    var verified = false;
    try {
      await MdtbbsCloudSaveApi.downloadSnapshotFile(
        accessToken: accessToken,
        ticket: ticket,
        savePath: tempPath,
        onStatus: onStatus,
        cancelToken: cancelToken,
      );

      final file = File(tempPath);
      if (!file.existsSync()) {
        throw const MdtbbsException(message: '云端文件没下下来');
      }

      final expectedSize = ticket.size;
      if (expectedSize != null && file.lengthSync() != expectedSize) {
        throw MdtbbsException(
          message: '下载的文件大小与云端不符（期望 $expectedSize，实际 ${file.lengthSync()}）',
        );
      }

      final expectedSha = ticket.sha256;
      if (expectedSha != null && expectedSha.isNotEmpty) {
        final actual = sha256OfFile(tempPath);
        if (actual != expectedSha) {
          throw const MdtbbsException(message: '下载的文件校验不过（sha256 对不上），已丢弃');
        }
      }
      verified = true;
      return tempPath;
    } finally {
      if (!verified) _deleteQuietly(tempPath);
    }
  }

  /// 按云清单把模组的启用态落回本机；失败只记日志（别把整个恢复搞挂）
  static Future<void> _applyModStatesQuietly(
    Mindustry version,
    CloudManifest manifest,
  ) async {
    try {
      await applyModEnabledStates(dataPath: version.dataPath, manifest: manifest);
    } on Object catch (error) {
      addLog(
        .warning,
        '调整模组启用态失败：${removeNewlines('$error')}',
        tag: 'Cloud',
      );
    }
  }

  static Future<({CloudImportReport report, CloudManifest manifest})> _extract(
    String archivePath, {
    required Mindustry version,
    required CloudImportMode mode,
    String? backupDir,
  }) async {
    final reader = await CloudArchiveReader.open(archivePath);
    final report = await reader.extractTo(
      dataPath: version.dataPath,
      mode: mode,
      backupDir: backupDir,
    );
    return (report: report, manifest: reader.manifest);
  }

  /// keepBoth 下战役关键文件被覆盖前的本机副本目录
  static String _campaignBackupDir() {
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp('[:.]'), '-');
    return p.join(_accountBackupDir, 'local-$stamp');
  }

  /// 「恢复」前留的底：把本机这份按云包格式导出到账号自己的备份目录
  static Future<CloudArchiveExport> _backupForRestore(Mindustry version) async {
    final directory = Directory(_accountBackupDir);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    // 文件名带时间戳，清理时按名字倒序就是「最新在前」
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp('[:.]'), '-');
    try {
      return await _exportWithCache(
        version: version,
        outputPath: p.join(_accountBackupDir, '$backupFilePrefix$stamp.zip'),
        deviceName: deviceName,
      );
    } catch (error) {
      throw MdtbbsException(
        message: '备份本机存档失败，已中止恢复：${removeNewlines('$error')}',
      );
    }
  }

  /// 导出云包，顺带用上哈希缓存
  ///
  /// 一次扫描要给真数据里 248 MiB 的模组 jar 逐份算指纹（约 4-6 秒），而缓存让
  /// **没变过的文件只 stat 一次**。缓存读写失败都不影响导出（见 [CloudHashCache]）
  static Future<CloudArchiveExport> _exportWithCache({
    required Mindustry version,
    required String outputPath,
    required String deviceName,
    bool includePreviews = false,
    bool includeModBytes = false,
    bool Function(CloudModEntry mod)? includeBytesWhen,
    void Function(String status)? onStatus,
  }) async {
    final cache = CloudHashCache.load(hashCachePath);
    final account = currentAccountId;
    final state = localState(version);
    final profile = profileIdOf(version);
    try {
      return await CloudArchive.export(
        version: version,
        outputPath: outputPath,
        deviceName: deviceName,
        account: account,
        cloudSignature: state?.signature,
        boundTag: state?.boundTag,
        profileKind: profile == 'default' ? 'default' : 'instance',
        includePreviews: includePreviews,
        includeModBytes: includeModBytes,
        includeBytesWhen: includeBytesWhen,
        onStatus: onStatus,
        cache: cache,
      );
    } finally {
      cache.save();
      addLog(
        .info,
        '清单哈希缓存：复用 ${cache.hits} 份 / 重算 ${cache.misses} 份',
        tag: 'Cloud',
      );
    }
  }

  /// 备份只留最近 [backupKeep] 份：每次恢复留一份会一直涨
  static void _pruneBackups() {
    try {
      final directory = Directory(_accountBackupDir);
      if (!directory.existsSync()) return;
      final files = [
        for (final entity in directory.listSync())
          if (entity is File &&
              p.basename(entity.path).startsWith(backupFilePrefix))
            entity,
      ]..sort((a, b) => b.path.compareTo(a.path));
      for (final file in files.skip(backupKeep)) {
        file.deleteSync();
      }
    } catch (error) {
      addLog(.warning, '清理旧备份失败：${removeNewlines('$error')}', tag: 'Cloud');
    }
  }

  /// 删云端槽位（**不动本机存档**），顺手清掉本地绑定
  static Future<void> deleteSlot({
    required String accessToken,
    required String slotId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsCloudSaveApi.deleteSlot(
      accessToken: accessToken,
      slotId: slotId,
      cancelToken: cancelToken,
    );
    final account = currentAccountId;
    if (account == null) return;
    final store = _loadStore();
    final profiles = Map<String, CloudSyncState>.from(store.profilesOf(account));
    for (final entry in profiles.entries) {
      if (entry.value.slotId != slotId) continue;
      store.removeState(account, entry.key);
      store.clearOwner(entry.key);
    }
    _saveStore(store);
  }

  static List<CloudSaveModInfo> _modsOf(CloudManifest manifest) => [
    for (final mod in manifest.mods)
      if (mod.internalName != null && mod.internalName!.isNotEmpty)
        CloudSaveModInfo(
          id: mod.internalName!,
          name: mod.displayName,
          version: mod.version,
          sha256: mod.sha256,
        ),
  ];

  // ---- 本地绑定：数据目录 → 云端槽位 + 上次同步到哪儿 ----

  /// 开了云存档的数据目录清单（开关按**数据目录**存：同步单元就是它，
  /// 多个版本共用一份目录时天然共用这个开关，UI 按版本呈现）
  static String get enabledPath => p.join(_root, 'cloud-enabled.json');

  /// 绑定文件（`<数据根>/mdtbbs_cloud_slots.json`）：数据目录 → 云端槽位 + 上次同步到哪儿
  static String get bindingPath => _bindingPath;

  /// 这个版本当前使用的数据目录开没开云存档
  ///
  /// 总开关是前置条件；profile 按账号记，换账号不继承。
  static bool isEnabled(Mindustry version) {
    final account = currentAccountId;
    if (account == null || !globallyEnabled) return false;
    final profile = profileIdOf(version);
    final owner = ownerOf(version);
    if (owner != null && owner != account) return false;
    return _loadEnabled().profilesOf(account).contains(profile);
  }

  /// 云存档总开关（账户 → 云存档那一页用的就是这个）
  static bool get globallyEnabled {
    final account = currentAccountId;
    if (account == null) return false;
    return _loadEnabled().globalOf(account);
  }

  /// 打开 / 关掉总开关（按当前账号）
  static void setGlobalEnabled(bool enabled) {
    final account = currentAccountId;
    if (account == null) return;
    final store = _loadEnabled();
    store.setGlobal(account, enabled);
    if (!enabled) store.clearProfiles(account);
    _saveEnabled(store);
  }

  /// 开关：按当前账号 + profile 记；总开关关着时开不了
  static bool setEnabled(Mindustry version, bool enabled) {
    final account = currentAccountId;
    if (account == null) return false;
    if (enabled && !globallyEnabled) return false;
    final profile = profileIdOf(version);
    final owner = ownerOf(version);
    if (enabled && owner != null && owner != account) return false;
    final store = _loadEnabled();
    final changed = store.setProfile(account, profile, enabled);
    if (changed) _saveEnabled(store);
    return true;
  }

  /// 有多少个版本共用这份数据目录（含自己）
  ///
  /// 开关按数据目录记 ⇒ 共用目录的版本共用同一个开关，UI 得把这件事说清楚
  static int versionsSharingDataPath(
    Mindustry version,
    Iterable<Mindustry> versions,
  ) {
    final path = _normalize(version.dataPath);
    var count = 0;
    for (final other in versions) {
      if (_normalize(other.dataPath) == path) count++;
    }
    return count;
  }

  /// 这个数据目录上次同步到哪儿；没记过给 null
  static CloudSyncState? localState(Mindustry version) {
    final account = currentAccountId;
    if (account == null) return null;
    return _loadStore().stateOf(account, profileIdOf(version));
  }

  /// 现在处于什么状态（**纯函数**，不联网、不扫盘）
  static CloudSyncStatus statusOf({
    required CloudSaveSlot? slot,
    required CloudSyncState? state,
    required Map<String, String> localHashes,
  }) {
    if (slot == null) return CloudSyncStatus.noSlot;
    if (state != null && !state.hasBaseline) {
      return CloudSyncStatus.boundUnsynced;
    }

    final localChanged = state == null
        ? localHashes.isNotEmpty
        : !_sameHashes(localHashes, state.files);
    final remoteChanged = state == null
        ? slot.currentSnapshotId != null
        : slot.currentSnapshotId != null &&
              slot.currentSnapshotId != state.snapshotId;

    if (localChanged && remoteChanged) return CloudSyncStatus.conflicted;
    if (localChanged) return CloudSyncStatus.pendingUpload;
    if (remoteChanged) return CloudSyncStatus.pendingDownload;
    return CloudSyncStatus.upToDate;
  }

  /// 扫一遍本机清单（走哈希缓存）后给出完整判断；页面要显示「状态点」时用它
  ///
  /// 代价是一次扫描（真数据热扫约 0.67 s）；只要网络那半的便宜判断用
  /// [statusOf] + 只读槽位就够
  static Future<CloudSyncOutcome> syncStatus({
    required String accessToken,
    required Mindustry version,
    String? deviceName,
    bool includePreviews = false,
    CancelToken? cancelToken,
  }) async {
    final name = deviceName ?? CloudSaveService.deviceName;
    final slot = await findSlot(
      accessToken: accessToken,
      version: version,
      deviceName: name,
      cancelToken: cancelToken,
    );
    final cache = CloudHashCache.load(hashCachePath);
    final manifest = await CloudManifest.scan(
      version: version,
      deviceName: name,
      includePreviews: includePreviews,
      cache: cache,
    );
    cache.save();
    return outcomeOf(
      slot: slot,
      state: localState(version),
      manifest: manifest,
    );
  }

  /// 完整判断：状态 + 两侧各是什么 + 本机改了哪些文件
  ///
  /// **纯函数**（清单由调用方扫好）—— 与 [statusOf] 同一套判据，只是把界面要用的
  /// 上下文一起给出来；冲突时拿它拼「本机 vs 云上」的对照
  static CloudSyncOutcome outcomeOf({
    required CloudSaveSlot? slot,
    required CloudSyncState? state,
    required CloudManifest manifest,
  }) {
    final snapshot = slot?.currentSnapshot;
    return CloudSyncOutcome(
      status: statusOf(
        slot: slot,
        state: state,
        localHashes: manifest.fileHashes,
      ),
      local: _sideOfManifest(manifest),
      slot: slot,
      remote: snapshot == null ? null : _sideOfSnapshot(snapshot),
      changedFiles: _changedFiles(state?.files, manifest.fileHashes),
      hasBaseline: state?.hasBaseline ?? false,
    );
  }

  /// 本机这一侧：最新那份存档的地图 / 波次 / 时长，加清单合计
  static CloudSyncSide _sideOfManifest(CloudManifest manifest) {
    final newest = _newestSave(manifest);
    final save = _displayInfoOf(newest?.meta);
    return CloudSyncSide(
      deviceName: manifest.deviceName,
      mapName: save?.mapName,
      wave: save?.wave,
      playtimeSeconds: save?.playtimeSeconds,
      savedAt: newest?.savedAt,
      fileCount: manifest.includedFiles.length,
      totalBytes: manifest.totalIncludedBytes,
      modCount: manifest.mods.length,
    );
  }

  /// 云端 head 那一侧
  static CloudSyncSide _sideOfSnapshot(CloudSaveSnapshot snapshot) {
    final save = snapshot.save;
    return CloudSyncSide(
      deviceName: snapshot.deviceId,
      snapshotId: snapshot.id,
      revision: snapshot.revision,
      mapName: save?.mapName,
      wave: save?.wave,
      playtimeSeconds: save?.playtimeSeconds,
      createdAt: snapshot.createdAt,
      totalBytes: snapshot.size ?? 0,
      modCount: snapshot.mods?.count ?? 0,
    );
  }

  /// 本机最新那份存档：按游戏写在 meta 里的 `saved` 取最大，读不出时间的排最后
  static CloudFileEntry? _newestSave(CloudManifest manifest) {
    CloudFileEntry? newest;
    var newestAt = -1;
    for (final file in manifest.files) {
      if (file.category != CloudCategory.save) continue;
      final at = file.savedAt?.millisecondsSinceEpoch ?? 0;
      if (at < newestAt) continue;
      newest = file;
      newestAt = at;
    }
    return newest;
  }

  /// 与上次同步相比变了哪些文件（内容变了 / 新增 / 没了，已排序）；
  /// **没有可用的基线**（没记过，或记过但没逐文件哈希）时给空 —— 说不出「变了哪些」
  static List<String> _changedFiles(
    Map<String, String>? baseline,
    Map<String, String> current,
  ) {
    if (baseline == null || baseline.isEmpty) return const [];
    final changed = <String>[
      for (final entry in current.entries)
        if (baseline[entry.key] != entry.value) entry.key,
      for (final path in baseline.keys)
        if (!current.containsKey(path)) path,
    ];
    changed.sort();
    return changed;
  }

  /// 存档摘要（上传体里的 `save`，服务端列表与冲突对照都读它）
  ///
  /// 直接读 meta 原字段而不走 [CloudFileEntry.mapSave]：`MapSave` 会给缺失项填展示用的
  /// 「未知」，那个不该当成地图名发给服务端
  static CloudSaveDisplayInfo? _displayInfoOf(Map<String, dynamic>? meta) {
    if (meta == null) return null;
    final mapName = meta['mapname'];
    final wave = meta['wave'];
    final playtime = meta['playtime'];
    final info = CloudSaveDisplayInfo(
      mapName: mapName is String && mapName.isNotEmpty ? mapName : null,
      wave: wave is int && wave > 0 ? wave : null,
      playtimeSeconds: playtime is int && playtime > 0
          ? playtime ~/ 1000
          : null,
    );
    final empty =
        info.mapName == null &&
        info.wave == null &&
        info.playtimeSeconds == null;
    return empty ? null : info;
  }

  static bool _sameHashes(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static _EnabledStore _loadEnabled() {
    final file = File(enabledPath);
    if (!file.existsSync()) return _EnabledStore();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return _EnabledStore();
      return _EnabledStore.fromJson(decoded.cast<String, dynamic>());
    } catch (error) {
      addLog(
        .warning,
        '云存档开关读取失败，按都没开处理：${removeNewlines('$error')}',
        tag: 'Cloud',
      );
      return _EnabledStore();
    }
  }

  static void _saveEnabled(_EnabledStore store) {
    try {
      final directory = Directory(p.dirname(enabledPath));
      if (!directory.existsSync()) directory.createSync(recursive: true);
      File(enabledPath).writeAsStringSync(
        jsonEncode(store.toJson()),
        flush: true,
      );
    } catch (error) {
      addLog(.warning, '云存档开关写入失败：${removeNewlines('$error')}', tag: 'Cloud');
    }
  }

  /// 记下「这个数据目录同步到哪个槽位 / 哪个快照 / 哪些文件」
  static void _rememberSynced(
    Mindustry version, {
    required String slotId,
    required String? snapshotId,
    required Map<String, String> files,
  }) {
    final account = currentAccountId;
    if (account == null) return;
    final profile = profileIdOf(version);
    final store = _loadStore();
    final existing = store.stateOf(account, profile);
    final isDefault = profile == 'default';
    final signature = existing?.signature ?? cloudSignatureForSlot(slotId);
    store.putState(
      account,
      profile,
      CloudSyncState(
        slotId: slotId,
        cloudSignature: signature,
        snapshotId: snapshotId,
        files: files,
        boundTag: isDefault ? null : (existing?.boundTag ?? version.tag),
        cloudTag: isDefault ? null : (existing?.cloudTag ?? version.tag),
        slotName: existing?.slotName,
        pendingSlotRename: existing?.pendingSlotRename ?? false,
        baseline: true,
        profileKind: isDefault ? 'default' : 'instance',
        release: version.release,
        build: version.versionNumber ?? version.releaseInt,
        isBe: version.isBe,
        dataPath: version.dataPath,
      ),
    );
    store.setOwner(profile, account);
    _saveStore(store);
  }

  /// 路径大小写不敏感的平台上要归一，否则同一个目录会记成两条绑定
  static String _normalize(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // 临时文件删不掉不影响结果
    }
  }
}

/// `cloud-enabled.json` v2：账号 → 总开关 + 已启用的 profile
class _EnabledStore {
  _EnabledStore({
    Map<String, bool>? globals,
    Map<String, Set<String>>? profiles,
  }) : globals = globals ?? {},
       profiles = profiles ?? {};

  final Map<String, bool> globals;
  final Map<String, Set<String>> profiles;

  factory _EnabledStore.fromJson(Map<String, dynamic> json) {
    final globals = <String, bool>{};
    final profiles = <String, Set<String>>{};
    final rawAccounts = json['accounts'];
    if (rawAccounts is Map) {
      for (final entry in rawAccounts.entries) {
        final account = '${entry.key}';
        final value = entry.value;
        if (value is! Map) continue;
        globals[account] = value['global'] == true;
        final rawProfiles = value['profiles'];
        profiles[account] = rawProfiles is List
            ? {
                for (final item in rawProfiles)
                  if (item is String) item,
              }
            : {};
      }
    }
    return _EnabledStore(globals: globals, profiles: profiles);
  }

  bool globalOf(String account) => globals[account] == true;

  Set<String> profilesOf(String account) => profiles[account] ?? const {};

  void setGlobal(String account, bool enabled) {
    globals[account] = enabled;
    profiles.putIfAbsent(account, () => {});
  }

  bool setProfile(String account, String profile, bool enabled) {
    final set = profiles.putIfAbsent(account, () => {});
    return enabled ? set.add(profile) : set.remove(profile);
  }

  void clearProfiles(String account) {
    profiles[account] = {};
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'accounts': {
      for (final account in {
        ...globals.keys,
        ...profiles.keys,
      })
        account: {
          'global': globalOf(account),
          'profiles': profilesOf(account).toList(),
        },
    },
  };
}
