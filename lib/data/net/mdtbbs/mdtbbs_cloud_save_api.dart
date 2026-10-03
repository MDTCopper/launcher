import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/util/io/copper_io.dart';

/// MDTBBS 云存档接口（Cloud Saves V1）
///
/// 槽位（slot）是同步单元、快照（snapshot）**不可变**；上传是三段式：
/// 开上传会话（此时占配额）→ PUT 字节 → commit 让服务端重新校验后建快照。
///
/// 请求体字段来自官方 OpenAPI 的 `components.schemas`；
/// **响应结构契约里没导出**（`paths` 为空），所以解析一律「读不出给 null」，
/// 不拿猜测的字段名硬取
class MdtbbsCloudSaveApi {
  MdtbbsCloudSaveApi._();

  static const _base = '/game-saves';

  /// 列自己的槽位（游标翻页）
  static Future<CloudSaveSlotPage> listSlots({
    required String accessToken,
    int limit = 20,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final envelope = await MdtbbsClient.getEnvelope(
      _base,
      accessToken: accessToken,
      queryParameters: {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
      cancelToken: cancelToken,
    );
    return CloudSaveSlotPage(
      slots: [
        for (final item in _listOf(envelope.data, const ['slots', 'items']))
          CloudSaveSlot.fromJson(item),
      ],
      nextCursor: envelope.nextCursor,
    );
  }

  /// 配额与上限：传大包之前先看，别传一半被拒
  static Future<CloudSaveQuota> quota({
    required String accessToken,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/quota',
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    return CloudSaveQuota.fromJson(_mapOf(data, '配额'));
  }

  /// 建槽位；[name] 上限 100 字符
  static Future<CloudSaveSlot> createSlot({
    required String accessToken,
    required String name,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      _base,
      body: {'name': name},
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    return CloudSaveSlot.fromJson(_mapOf(data, '槽位'));
  }

  /// 单个槽位的详情（含当前 head）
  static Future<CloudSaveSlot> slot({
    required String accessToken,
    required String slotId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/$slotId',
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    return CloudSaveSlot.fromJson(_mapOf(data, '槽位'));
  }

  /// 改槽位名
  static Future<void> renameSlot({
    required String accessToken,
    required String slotId,
    required String name,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.patchJson(
      '$_base/$slotId',
      body: {'name': name},
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
  }

  /// 删槽位（连带它的快照引用；**不影响本机存档**）
  static Future<void> deleteSlot({
    required String accessToken,
    required String slotId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.deleteJson(
      '$_base/$slotId',
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
  }

  /// 快照历史（不可变、只增；恢复旧快照会产生一个新版本）
  static Future<CloudSaveSnapshotPage> listSnapshots({
    required String accessToken,
    required String slotId,
    int limit = 20,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final envelope = await MdtbbsClient.getEnvelope(
      '$_base/$slotId/snapshots',
      accessToken: accessToken,
      queryParameters: {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
      cancelToken: cancelToken,
    );
    return CloudSaveSnapshotPage(
      snapshots: [
        for (final item in _listOf(envelope.data, const ['snapshots', 'items']))
          CloudSaveSnapshot.fromJson(item),
      ],
      nextCursor: envelope.nextCursor,
    );
  }

  /// 固定 / 取消固定：固定的快照不会被保留策略清掉
  static Future<void> setSnapshotPinned({
    required String accessToken,
    required String slotId,
    required String snapshotId,
    required bool pinned,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.patchJson(
      '$_base/$slotId/snapshots/$snapshotId',
      body: {'pinned': pinned},
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
  }

  static Future<void> deleteSnapshot({
    required String accessToken,
    required String slotId,
    required String snapshotId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.deleteJson(
      '$_base/$slotId/snapshots/$snapshotId',
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
  }

  /// 把旧快照恢复成**新版本**（不是原地回滚）
  ///
  /// [confirmCurrentSnapshotId] 用来避免「确认期间 head 又变了」
  static Future<CloudSaveSnapshot?> restoreSnapshot({
    required String accessToken,
    required String slotId,
    required String snapshotId,
    String? confirmCurrentSnapshotId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/$slotId/snapshots/$snapshotId/restore',
      body: {'confirm_current_snapshot_id': ?confirmCurrentSnapshotId},
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    return _maybeSnapshot(data);
  }

  /// 开上传会话：服务端此时占配额，并给出该往哪 PUT
  ///
  /// [baseSnapshotId] 是本机已知的云端 head；传对了才能防止覆盖别人（或另一台设备）
  /// 刚推上去的新快照 —— 不匹配时服务端返回冲突并报出当前快照 ID
  static Future<CloudSaveUploadSession> createUpload({
    required String accessToken,
    required String slotId,
    required String sha256,
    required int size,
    String? baseSnapshotId,
    CloudSaveUploadReason reason = CloudSaveUploadReason.manual,
    CloudSaveConflictPolicy? conflictPolicy,
    String? confirmCurrentSnapshotId,
    CloudSaveGameInfo? game,
    CloudSaveDisplayInfo? save,
    List<CloudSaveModInfo> mods = const [],
    String? deviceId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/$slotId/uploads',
      body: {
        'sha256': sha256,
        'size': size,
        'base_snapshot_id': ?baseSnapshotId,
        'reason': reason.wire,
        if (conflictPolicy != null) 'conflict_resolution': conflictPolicy.wire,
        'confirm_current_snapshot_id': ?confirmCurrentSnapshotId,
        if (game != null) 'game': game.toJson(),
        if (save != null) 'save': save.toJson(),
        if (mods.isNotEmpty)
          'mods': [for (final mod in mods.take(100)) mod.toJson()],
        'device_id': ?deviceId,
      },
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    return CloudSaveUploadSession.fromJson(_mapOf(data, '上传会话'));
  }

  /// 把字节原样 PUT 上去：**不能压缩、不能改一个字节**（服务端会重算 sha256 核对）
  static Future<void> putUploadBytes({
    required String accessToken,
    required CloudSaveUploadSession session,
    required List<int> bytes,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.putBytes(
      session.url,
      bytes: bytes,
      accessToken: accessToken,
      headers: session.headers,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// 提交：服务端重新读一遍文件、核对字节数与 sha256，然后才建快照
  ///
  /// 同一上传会话重复 commit 是幂等的
  static Future<CloudSaveSnapshot?> commitUpload({
    required String accessToken,
    required String uploadId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/uploads/$uploadId/commit',
      body: const <String, dynamic>{},
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    return _maybeSnapshot(data);
  }

  /// 取消没用完的上传会话（**释放它占的配额**）
  static Future<void> cancelUpload({
    required String accessToken,
    required String uploadId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.deleteJson(
      '$_base/uploads/$uploadId',
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
  }

  /// 取下载凭据：先拿它，再按它对文件发 GET
  static Future<CloudSaveDownloadTicket> createDownload({
    required String accessToken,
    required String slotId,
    required String snapshotId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/$slotId/snapshots/$snapshotId/download',
      body: const <String, dynamic>{},
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    return CloudSaveDownloadTicket.fromJson(_mapOf(data, '下载凭据'));
  }

  /// 把快照字节下到 [savePath]（**先落临时文件**，由调用方校验后再替换本机存档）
  static Future<void> downloadSnapshotFile({
    required String accessToken,
    required CloudSaveDownloadTicket ticket,
    required String savePath,
    CancelToken? cancelToken,
    HttpStatusCallback? onStatus,
  }) async {
    await MdtbbsClient.downloadFile(
      path: ticket.url,
      savePath: savePath,
      accessToken: accessToken,
      headers: ticket.headers,
      cancelToken: cancelToken,
      onStatus: onStatus,
    );
  }

  static Map<String, dynamic> _mapOf(Object? data, String what) {
    if (data is! Map) {
      throw MdtbbsException(message: '$what 响应不是 JSON 对象');
    }
    return data.cast<String, dynamic>();
  }

  /// 列表可能直接是数组，也可能包在 `{ slots: [...] }` 之类的键里
  static List<Map<String, dynamic>> _listOf(Object? data, List<String> keys) {
    final raw = data is List
        ? data
        : (data is Map
              ? keys
                    .map((key) => data[key])
                    .firstWhere((value) => value is List, orElse: () => null)
              : null);
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  /// 写操作的响应结构没进契约：能解出快照就解，解不出给 null
  static CloudSaveSnapshot? _maybeSnapshot(Object? data) {
    if (data is! Map) return null;
    final map = data.cast<String, dynamic>();
    final nested = map['snapshot'];
    final candidate = nested is Map ? nested.cast<String, dynamic>() : map;
    final snapshot = CloudSaveSnapshot.fromJson(candidate);
    return snapshot.id.isEmpty ? null : snapshot;
  }
}
