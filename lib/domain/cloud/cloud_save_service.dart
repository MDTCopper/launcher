import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_cloud_save_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/cloud/cloud_archive.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 一次上传的结果
class CloudSaveUploadResult {
  const CloudSaveUploadResult({
    required this.slot,
    required this.snapshot,
    required this.archiveBytes,
    required this.dropped,
    this.alreadyUpToDate = false,
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
}

/// 本地记的「这个数据目录上次同步到哪儿」
///
/// 没有它就只能在上传时被服务端 409 告知冲突，或者让用户自己看时间猜；
/// 有了它才能在本地分辨「本机改没改 / 云端有没有新的」（Steam 的 `remotecache.vdf` 干的就是这事）
class CloudSyncState {
  const CloudSyncState({
    required this.slotId,
    this.snapshotId,
    this.files = const {},
  });

  final String slotId;

  /// 上次同步到的云端快照（上传成功后是新快照，恢复后是那个被恢复的快照）
  final String? snapshotId;

  /// 上次同步时各文件的 sha256（键是数据目录内的相对路径）
  final Map<String, String> files;

  Map<String, dynamic> toJson() => {
    'slot_id': slotId,
    if (snapshotId != null) 'snapshot_id': snapshotId,
    if (files.isNotEmpty) 'files': files,
  };

  /// 读一条绑定；认不出来给 null
  ///
  /// 兼容老形态（值是**槽位 id 字符串**，那时还没有「上次同步到哪儿」这回事）
  static CloudSyncState? fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return CloudSyncState(slotId: value);
    }
    if (value is! Map) return null;

    final slotId = '${value['slot_id'] ?? ''}';
    if (slotId.isEmpty) return null;
    final rawFiles = value['files'];
    return CloudSyncState(
      slotId: slotId,
      snapshotId: value['snapshot_id'] is String
          ? value['snapshot_id'] as String
          : null,
      files: rawFiles is Map
          ? {
              for (final entry in rawFiles.entries)
                if (entry.value is String) '${entry.key}': '${entry.value}',
            }
          : const {},
    );
  }
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

  /// 槽位名：设备名 + 游戏版本（上限 100 字符，这里截断兜底）
  static String slotNameFor({
    required String deviceName,
    required CloudGameInfo game,
  }) {
    final release = game.release.isNotEmpty ? game.release : game.tag;
    final name = '$deviceName · $release';
    return name.length <= 100 ? name : name.substring(0, 100);
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

  /// 找这个数据目录**已有**的云端槽位；找不到给 null，**不创建**
  ///
  /// 页面加载走这条：只是看看状态，不该产生写操作（建槽是占配额的动作，要用户点）
  static Future<CloudSaveSlot?> findSlot({
    required String accessToken,
    required Mindustry version,
    String? deviceName,
    CancelToken? cancelToken,
  }) async {
    final name = deviceName ?? CloudSaveService.deviceName;
    final dataPath = _normalize(version.dataPath);
    final states = _loadStates();

    final boundId = states[dataPath]?.slotId;
    if (boundId != null) {
      try {
        return await MdtbbsCloudSaveApi.slot(
          accessToken: accessToken,
          slotId: boundId,
          cancelToken: cancelToken,
        );
      } on MdtbbsException catch (error) {
        // 云端删掉了 / 换账号了：绑定作废，往下走按名字再认一次
        if (error.statusCode != 404) rethrow;
        addLog(.info, '云端槽位已不存在，重新认一个', tag: 'Cloud');
        states.remove(dataPath);
        _saveStates(states);
      }
    }

    final wanted = slotNameFor(
      deviceName: name,
      game: CloudGameInfo.fromVersion(version),
    );
    final page = await MdtbbsCloudSaveApi.listSlots(
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    for (final slot in page.slots) {
      if (slot.name == wanted) {
        _bind(dataPath, slot.id);
        return slot;
      }
    }
    return null;
  }

  /// 找（或建）这个版本的数据目录对应的云端槽位
  ///
  /// 先认本地记下的槽位 id（用户改过名也找得到），再退到按名字认，最后才新建
  static Future<CloudSaveSlot> resolveSlot({
    required String accessToken,
    required Mindustry version,
    String? deviceName,
    CancelToken? cancelToken,
  }) async {
    final found = await findSlot(
      accessToken: accessToken,
      version: version,
      deviceName: deviceName,
      cancelToken: cancelToken,
    );
    if (found != null) return found;

    final name = deviceName ?? CloudSaveService.deviceName;
    final created = await MdtbbsCloudSaveApi.createSlot(
      accessToken: accessToken,
      name: slotNameFor(
        deviceName: name,
        game: CloudGameInfo.fromVersion(version),
      ),
      cancelToken: cancelToken,
    );
    _bind(_normalize(version.dataPath), created.id);
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
        onStatus: onStatus,
      );

      final bytes = File(archivePath).readAsBytesSync();
      final sha256 = sha256OfBytes(bytes);

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
        if (head.currentSnapshot?.sha256 != sha256) rethrow;

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
      await MdtbbsCloudSaveApi.putUploadBytes(
        accessToken: accessToken,
        session: session,
        bytes: bytes,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );

      onStatus?.call('等云端确认');
      final snapshot = await MdtbbsCloudSaveApi.commitUpload(
        accessToken: accessToken,
        uploadId: session.uploadId,
        cancelToken: cancelToken,
      );

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
      );
    } finally {
      _deleteQuietly(archivePath);
    }
  }

  /// 把某个快照拉下来并解进本机数据目录
  ///
  /// 严格按官方要求：**先落临时文件 → 校验字节数与 sha256 → 才交给解包**；
  /// 解包按 [mode] 处理同名文件 —— 默认留两份，**不覆盖本机**。
  /// [applyModStates] 默认关：这条路是「把云上那份拿下来」，不该顺手改本机设置
  static Future<CloudImportReport> download({
    required String accessToken,
    required Mindustry version,
    required String slotId,
    required String snapshotId,
    CloudImportMode mode = CloudImportMode.keepBoth,
    bool applyModStates = false,
    HttpStatusCallback? onStatus,
    CancelToken? cancelToken,
  }) async {
    final tempPath = await _fetchSnapshot(
      accessToken: accessToken,
      slotId: slotId,
      snapshotId: snapshotId,
      onStatus: onStatus,
      cancelToken: cancelToken,
    );
    try {
      final extracted = await _extract(
        tempPath,
        version: version,
        mode: mode,
        applyModStates: applyModStates,
      );
      return extracted.report;
    } finally {
      _deleteQuietly(tempPath);
    }
  }

  /// 用云端快照**覆盖本机**这份数据目录（页面上那个「恢复」）
  ///
  /// 覆盖前先把本机这份导出成 zip 存进 [backupDir]；**备份失败就中止** ——
  /// 不能在没有退路的情况下盖掉玩家的存档。
  /// [applyModStates] 默认**开**：云包记着当时哪些模组是启用的，不写回去会出现
  /// 「存档要 NewHorizon 但模组没启用」这类错配
  static Future<CloudSaveRestoreResult> restore({
    required String accessToken,
    required Mindustry version,
    required String slotId,
    required String snapshotId,
    bool applyModStates = true,
    void Function(String status)? onStatus,
    HttpStatusCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
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
      final extracted = await _extract(
        tempPath,
        version: version,
        mode: CloudImportMode.overwrite,
        applyModStates: applyModStates,
      );
      _pruneBackups();
      // 落干净了才记「同步到这个快照」；有拒收说明本机与云上并不一致，别谎报
      if (extracted.report.rejected.isEmpty) {
        _rememberSynced(
          version,
          slotId: slotId,
          snapshotId: snapshotId,
          files: extracted.manifest.fileHashes,
        );
      }
      return CloudSaveRestoreResult(
        report: extracted.report,
        backupPath: backup.path,
        backupBytes: backup.bytes,
      );
    } finally {
      _deleteQuietly(tempPath);
    }
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

  static Future<({CloudImportReport report, CloudManifest manifest})> _extract(
    String archivePath, {
    required Mindustry version,
    required CloudImportMode mode,
    required bool applyModStates,
  }) async {
    final reader = await CloudArchiveReader.open(archivePath);
    final report = await reader.extractTo(
      dataPath: version.dataPath,
      mode: mode,
    );
    if (applyModStates) {
      report.appliedModStates = CloudArchiveReader.mergeModStates(
        dataPath: version.dataPath,
        states: reader.manifest.modStates,
      );
    }
    return (report: report, manifest: reader.manifest);
  }

  /// 「恢复」前留的底：把本机这份按云包格式导出到 [backupDir]
  static Future<CloudArchiveExport> _backupForRestore(Mindustry version) async {
    final directory = Directory(backupDir);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    // 文件名带时间戳，清理时按名字倒序就是「最新在前」
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp('[:.]'), '-');
    try {
      return await _exportWithCache(
        version: version,
        outputPath: p.join(backupDir, '$backupFilePrefix$stamp.zip'),
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
    void Function(String status)? onStatus,
  }) async {
    final cache = CloudHashCache.load(hashCachePath);
    try {
      return await CloudArchive.export(
        version: version,
        outputPath: outputPath,
        deviceName: deviceName,
        includePreviews: includePreviews,
        includeModBytes: includeModBytes,
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
      final directory = Directory(backupDir);
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
    final states = _loadStates();
    states.removeWhere((_, value) => value.slotId == slotId);
    _saveStates(states);
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

  /// 这个数据目录上次同步到哪儿；没记过给 null
  static CloudSyncState? localState(Mindustry version) =>
      _loadStates()[_normalize(version.dataPath)];

  /// 现在处于什么状态（**纯函数**，不联网、不扫盘）
  ///
  /// [localHashes] 是本机现在的文件投影（`CloudManifest.fileHashes`）；没有本机记录时
  /// 只能保守判断：本机有东西 + 云端有 head ⇒ 当作冲突让用户选，别替他把一边盖掉
  static CloudSyncStatus statusOf({
    required CloudSaveSlot? slot,
    required CloudSyncState? state,
    required Map<String, String> localHashes,
  }) {
    if (slot == null) return CloudSyncStatus.noSlot;

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

  /// 扫一遍本机清单（走哈希缓存）后判状态；页面要显示「状态点」时用它
  ///
  /// 代价是一次扫描（真数据热扫约 0.67 s）；只要网络那半的便宜判断用
  /// [statusOf] + 只读槽位就够
  static Future<
    ({CloudSyncStatus status, CloudSaveSlot? slot, CloudManifest manifest})
  >
  syncStatus({
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
    return (
      status: statusOf(
        slot: slot,
        state: localState(version),
        localHashes: manifest.fileHashes,
      ),
      slot: slot,
      manifest: manifest,
    );
  }

  static bool _sameHashes(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static Map<String, CloudSyncState> _loadStates() {
    final file = File(_bindingPath);
    if (!file.existsSync()) return {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return {};

      // 新形态是 { version, slots: { 数据目录: {...} } }；老形态直接是 { 数据目录: 槽位id }
      final raw = decoded['slots'] is Map ? decoded['slots'] as Map : decoded;
      final states = <String, CloudSyncState>{};
      for (final entry in raw.entries) {
        final state = CloudSyncState.fromJson(entry.value);
        if (state != null) states['${entry.key}'] = state;
      }
      return states;
    } catch (error) {
      addLog(
        .warning,
        '云槽位绑定读取失败，按没有绑定处理：${removeNewlines('$error')}',
        tag: 'Cloud',
      );
      return {};
    }
  }

  static void _saveStates(Map<String, CloudSyncState> states) {
    try {
      final directory = Directory(p.dirname(_bindingPath));
      if (!directory.existsSync()) directory.createSync(recursive: true);
      File(_bindingPath).writeAsStringSync(
        jsonEncode({
          'version': 2,
          'slots': {
            for (final entry in states.entries) entry.key: entry.value.toJson(),
          },
        }),
        flush: true,
      );
    } catch (error) {
      addLog(.warning, '云槽位绑定写入失败：${removeNewlines('$error')}', tag: 'Cloud');
    }
  }

  /// 记下「这个数据目录同步到哪个槽位 / 哪个快照 / 哪些文件」
  static void _rememberSynced(
    Mindustry version, {
    required String slotId,
    required String? snapshotId,
    required Map<String, String> files,
  }) {
    final states = _loadStates();
    states[_normalize(version.dataPath)] = CloudSyncState(
      slotId: slotId,
      snapshotId: snapshotId,
      files: files,
    );
    _saveStates(states);
  }

  static void _bind(String dataPath, String slotId) {
    final states = _loadStates();
    final existing = states[dataPath];
    // 只是认了个槽位：上次同步到哪儿保持不变（别把已有记录清了）
    states[dataPath] = CloudSyncState(
      slotId: slotId,
      snapshotId: existing?.snapshotId,
      files: existing?.files ?? const {},
    );
    _saveStates(states);
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
