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
  });

  final CloudSaveSlot slot;

  /// 服务端建好的快照；响应结构契约没导出，解不出时为 null（不代表失败）
  final CloudSaveSnapshot? snapshot;

  /// 上传的 zip 体积
  final int archiveBytes;

  /// 扫完到打包之间又变过、没能进包的文件
  final List<String> dropped;
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
    final bindings = _loadBindings();

    final boundId = bindings[dataPath];
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
        bindings.remove(dataPath);
        _saveBindings(bindings);
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
      final export = await CloudArchive.export(
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
      final session = await MdtbbsCloudSaveApi.createUpload(
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
  /// 解包按 [mode] 处理同名文件 —— 默认留两份，**不覆盖本机**
  static Future<CloudImportReport> download({
    required String accessToken,
    required Mindustry version,
    required String slotId,
    required String snapshotId,
    CloudImportMode mode = CloudImportMode.keepBoth,
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
      return await _extract(tempPath, version: version, mode: mode);
    } finally {
      _deleteQuietly(tempPath);
    }
  }

  /// 用云端快照**覆盖本机**这份数据目录（页面上那个「恢复」）
  ///
  /// 覆盖前先把本机这份导出成 zip 存进 [backupDir]；**备份失败就中止** ——
  /// 不能在没有退路的情况下盖掉玩家的存档
  static Future<CloudSaveRestoreResult> restore({
    required String accessToken,
    required Mindustry version,
    required String slotId,
    required String snapshotId,
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
      final report = await _extract(
        tempPath,
        version: version,
        mode: CloudImportMode.overwrite,
      );
      _pruneBackups();
      return CloudSaveRestoreResult(
        report: report,
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

  static Future<CloudImportReport> _extract(
    String archivePath, {
    required Mindustry version,
    required CloudImportMode mode,
  }) async {
    final reader = await CloudArchiveReader.open(archivePath);
    return reader.extractTo(dataPath: version.dataPath, mode: mode);
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
      return await CloudArchive.export(
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
    final bindings = _loadBindings();
    bindings.removeWhere((_, value) => value == slotId);
    _saveBindings(bindings);
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

  // ---- 本地绑定：数据目录 → 云端槽位 id ----

  static Map<String, String> _loadBindings() {
    final file = File(_bindingPath);
    if (!file.existsSync()) return {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } catch (error) {
      addLog(
        .warning,
        '云槽位绑定读取失败，按没有绑定处理：${removeNewlines('$error')}',
        tag: 'Cloud',
      );
      return {};
    }
  }

  static void _saveBindings(Map<String, String> bindings) {
    try {
      final directory = Directory(p.dirname(_bindingPath));
      if (!directory.existsSync()) directory.createSync(recursive: true);
      File(_bindingPath).writeAsStringSync(jsonEncode(bindings), flush: true);
    } catch (error) {
      addLog(.warning, '云槽位绑定写入失败：${removeNewlines('$error')}', tag: 'Cloud');
    }
  }

  static void _bind(String dataPath, String slotId) {
    final bindings = _loadBindings();
    bindings[dataPath] = slotId;
    _saveBindings(bindings);
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
