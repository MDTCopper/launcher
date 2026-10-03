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

  /// 找（或建）这个版本的数据目录对应的云端槽位
  ///
  /// 先认本地记下的槽位 id（用户改过名也找得到），再退到按名字认，最后才新建
  static Future<CloudSaveSlot> resolveSlot({
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
        // 云端删掉了 / 换账号了：绑定作废，往下走重新认
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

    final created = await MdtbbsCloudSaveApi.createSlot(
      accessToken: accessToken,
      name: wanted,
      cancelToken: cancelToken,
    );
    _bind(dataPath, created.id);
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
  /// 解包本身不静默覆盖（同名不同内容会留两份）
  static Future<CloudImportReport> download({
    required String accessToken,
    required Mindustry version,
    required String slotId,
    required String snapshotId,
    bool keepBoth = true,
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
          throw MdtbbsException(message: '下载的文件校验不过（sha256 对不上），已丢弃');
        }
      }

      final reader = await CloudArchiveReader.open(tempPath);
      return await reader.extractTo(
        dataPath: version.dataPath,
        keepBoth: keepBoth,
      );
    } finally {
      _deleteQuietly(tempPath);
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
