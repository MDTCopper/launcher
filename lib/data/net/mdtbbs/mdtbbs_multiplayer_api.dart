import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:dio/dio.dart';

/// 当前用户不在任何会话里（`/sessions/mine` 的语义化 404）
const _kSessionNotFound = 'SESSION_NOT_FOUND';

/// BBS 官方多人联机 API（`/api/v1/multiplayer`，Public API 1.4.1）
///
/// **主线联机路径**（2026-10-11 拍板）：MindAuth OAuth 令牌直接作 Bearer，
/// 免密码；LanLink 控制面那条是兼容位。
///
/// 文档口径：
/// - 所有 ID 是不透明字符串，**原样传回**；不提交服务端决定的字段
/// - join 的请求体即使没有可选字段也要发 `{}`；恢复成功带 `resumed: true`
/// - 对端心跳 30 秒；90 秒未收到 → disconnected + 清候选 + 60 秒恢复窗口
/// - `credential` 是短期秘密，只能进中继 WSS 的第一条 AUTH 文本帧
class MdtbbsMultiplayerApi {
  MdtbbsMultiplayerApi._();

  static const _base = '/multiplayer';

  /// 联机接口都是快请求：cio 的 receive 超时是 600 秒，这里统一收紧，
  /// 否则一笔挂住的请求会把 UI 卡十分钟
  static const Duration _callTimeout = Duration(seconds: 30);

  // ── 能力与偏好 ──────────────────────────────────────────────

  /// 展示联机入口前先核对：四个布尔 + 顶层 `multiplayer` 标志
  static Future<MdtbbsMultiplayerCapabilities> capabilities({
    required String accessToken,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/capabilities',
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsMultiplayerCapabilities.fromJson(_map(data));
  }

  static Future<MdtbbsMultiplayerPreferences> preferences({
    required String accessToken,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/preferences',
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsMultiplayerPreferences.fromJson(_map(data));
  }

  /// 设置用户默认的加入意图客户端；`clientId` 必须来自 [preferences] 的 `clients`
  static Future<void> setDefaultClient({
    required String accessToken,
    required String clientId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.patchJson(
      '$_base/preferences',
      body: {'client_id': clientId},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  // ── 会话 ────────────────────────────────────────────────────

  /// 创建会话
  ///
  /// 契约 1.7.0 把三件事拆开：
  /// - [visibility]（`private` / `friends` / `public`）**只决定发现**：能不能在列表里被看到
  /// - [joinPolicy]（`invite_only` / `friends` / `public`）**只决定资格**：谁有资格加入
  /// - [requireApproval] 是独立的布尔，不要塞进 `join_policy`
  ///
  /// 三者是正交的；房间码 / 邀请链接 / 大厅点击都只是**入口**，不是权限
  /// （有码不等于有资格）。[maxPlayers] 2–64，缺省 8。
  /// 房主会在创建响应里拿到 joinCode（API 只回这一次，房间存续期间可复用）。
  /// **创建会话要求手机号验证**（站长确认）；加入会话自 2026-10-20 起对 Copper Launcher
  /// 免验证（服务端按 OAuth client_id 识别启动器）
  static Future<MdtbbsCreatedSession> createSession({
    required String accessToken,
    required String gameId,
    String? gameVersion,
    String? activityName,
    String visibility = 'private',
    String joinPolicy = 'friends',
    bool requireApproval = false,
    int maxPlayers = 8,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/sessions',
      body: {
        'game_id': gameId,
        if (gameVersion != null && gameVersion.isNotEmpty)
          'game_version': gameVersion,
        if (activityName != null && activityName.isNotEmpty)
          'activity_name': activityName,
        'visibility': visibility,
        'join_policy': joinPolicy,
        'require_approval': requireApproval,
        'max_players': maxPlayers,
      },
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsCreatedSession.fromJson(_map(data));
  }

  /// 查询单个会话
  static Future<MdtbbsSession> session({
    required String accessToken,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/sessions/$sessionId',
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsSession.fromJson(_map(data));
  }

  /// 当前用户所在的会话；不在任何会话里时返回 null（服务端 404 SESSION_NOT_FOUND）
  static Future<MdtbbsSession?> currentSession({
    required String accessToken,
    CancelToken? cancelToken,
  }) async {
    try {
      final data = await MdtbbsClient.getJson(
        '$_base/sessions/mine',
        accessToken: accessToken,
        cancelToken: cancelToken,
        timeout: _callTimeout,
      );
      return MdtbbsSession.fromJson(_map(data));
    } on MdtbbsException catch (error) {
      if (error.code == _kSessionNotFound) return null;
      rethrow;
    }
  }

  /// 会话对端列表；**要求调用者本身是活跃对端**
  static Future<List<MdtbbsPeer>> peers({
    required String accessToken,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/sessions/$sessionId/peers',
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return _list(data).map(MdtbbsPeer.fromJson).toList();
  }

  /// 解析不公开会话的加入码（10 位十六进制）
  ///
  /// 未知的码返回 `SESSION_NOT_FOUND`（语义错误码，不是路由错误）
  static Future<MdtbbsSession> resolveCode({
    required String accessToken,
    required String code,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/sessions/resolve-code',
      body: {'code': code},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsSession.fromJson(_map(data));
  }

  /// 加入会话；请求体没有可选字段也要发 `{}`
  ///
  /// [inviteId] / [joinCode] / [resumeToken] 三选一或组合（恢复优先）；
  /// 恢复成功时返回的 `resumed == true` 且**令牌已轮换**，要覆盖保存
  static Future<MdtbbsJoinResult> join({
    required String accessToken,
    required String sessionId,
    String? inviteId,
    String? joinCode,
    String? resumeToken,
    Map<String, dynamic>? capabilities,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/sessions/$sessionId/join',
      body: {
        if (inviteId != null && inviteId.isNotEmpty) 'invite_id': inviteId,
        if (joinCode != null && joinCode.isNotEmpty) 'join_code': joinCode,
        if (resumeToken != null && resumeToken.isNotEmpty)
          'resume_token': resumeToken,
        'capabilities': ?capabilities,
      },
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsJoinResult.fromJson(_map(data));
  }

  /// 退出会话
  ///
  /// 普通成员 → `left`；**房主主动退出 → `closing`（60 秒宽限）**
  static Future<MdtbbsLeaveOutcome> leave({
    required String accessToken,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/sessions/$sessionId/leave',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    final map = _map(data);
    return MdtbbsLeaveOutcome(
      status: '${map['status'] ?? ''}',
      graceSeconds: (map['grace_seconds'] as num?)?.toInt() ?? 0,
    );
  }

  /// 对端心跳；**每 30 秒一次**，响应里的 `expiresIn` 是 90 秒的判定线
  static Future<MdtbbsHeartbeat> peerHeartbeat({
    required String accessToken,
    required String sessionId,
    required String peerId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/sessions/$sessionId/peers/$peerId/heartbeat',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    final map = _map(data);
    return MdtbbsHeartbeat(
      peerId: '${map['peer_id'] ?? ''}',
      heartbeatIntervalSeconds:
          (map['heartbeat_interval'] as num?)?.toInt() ?? 30,
      expiresInSeconds: (map['expires_in'] as num?)?.toInt() ?? 90,
    );
  }

  // ── 网络候选地址 ────────────────────────────────────────────

  /// 发布自己的候选地址（STUN/NAT 探测由客户端负责）
  static Future<MdtbbsCandidate> publishCandidate({
    required String accessToken,
    required String sessionId,
    required MdtbbsCandidate candidate,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/sessions/$sessionId/candidates',
      body: {'candidate': candidate.toRequestJson()},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsCandidate.fromJson(_map(data));
  }

  /// 读取某个对端发布的候选地址（只在同会话对端之间短期交换）
  static Future<List<MdtbbsCandidate>> peerCandidates({
    required String accessToken,
    required String sessionId,
    required String peerId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/sessions/$sessionId/peers/$peerId/candidates',
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return _list(data).map(MdtbbsCandidate.fromJson).toList();
  }

  /// 删除自己发布的一条候选
  static Future<void> deleteCandidate({
    required String accessToken,
    required String sessionId,
    required String candidateId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.deleteJson(
      '$_base/sessions/$sessionId/candidates/$candidateId',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  // ── 邀请 ────────────────────────────────────────────────────

  /// 邀请好友进自己的会话；[targetUserId] 是论坛**整数**用户 ID
  /// （文档与 OpenAPI 都写 `target_user_id` 是 number，**不能传字符串**）。
  /// 邀请属于写操作，仍要求手机号验证（站长确认），未验证会被拒
  static Future<MdtbbsInvite> createInvite({
    required String accessToken,
    required String sessionId,
    required int targetUserId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/invites',
      body: {'session_id': sessionId, 'target_user_id': targetUserId},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsInvite.fromJson(_map(data));
  }

  /// 列出收到的邀请（含会话摘要）；5 分钟过期
  static Future<List<MdtbbsInvite>> invites({
    required String accessToken,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '$_base/invites',
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return _list(data).map(MdtbbsInvite.fromJson).toList();
  }

  /// 接受邀请 → 返回加入意图（60 秒内使用）
  ///
  /// 服务端不一定给意图：没给时返回空 id，由调用方退回「直接加入会话」。
  /// 这里把应答的键名记下来（只记键，不记值），下次形状变了能一眼看出来
  static Future<MdtbbsJoinIntent> acceptInvite({
    required String accessToken,
    required String inviteId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/invites/$inviteId/accept',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    final map = _map(data);
    final intent = MdtbbsJoinIntent.fromJson(map);
    if (intent.intentId.isEmpty) {
      addLogAndPrint(
        .warning,
        '接受邀请的应答里没有 intent_id（键：${map.keys.join(', ')}），'
        '改为直接加入会话',
        tag: 'Mdtbbs',
      );
    }
    return intent;
  }

  /// 拒绝 / 撤销邀请
  static Future<void> respondInvite({
    required String accessToken,
    required String inviteId,
    required bool revoke,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      '$_base/invites/$inviteId/${revoke ? 'revoke' : 'decline'}',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  // ── 加入申请与加入意图 ──────────────────────────────────────

  /// 对 `join_policy = request` 的会话发起加入申请；有效期 5 分钟
  static Future<void> createJoinRequest({
    required String accessToken,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      '$_base/sessions/$sessionId/join-requests',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  /// 房主批准加入申请 → 返回**绑定申请者 OAuth 客户端**的加入意图（10 分钟有效）
  static Future<MdtbbsJoinIntent> approveJoinRequest({
    required String accessToken,
    required String requestId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/join-requests/$requestId/approve',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsJoinIntent.fromJson(_map(data));
  }

  static Future<void> rejectJoinRequest({
    required String accessToken,
    required String requestId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      '$_base/join-requests/$requestId/reject',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
  }

  /// 用加入码给不公开会话创建**直接加入意图**（60 秒内首次使用）
  static Future<MdtbbsJoinIntent> createJoinIntent({
    required String accessToken,
    required String sessionId,
    String? joinCode,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/sessions/$sessionId/join-intents',
      body: {
        if (joinCode != null && joinCode.isNotEmpty) 'join_code': joinCode,
      },
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsJoinIntent.fromJson(_map(data));
  }

  /// 启动器消费加入意图并成为对端；同一用户与客户端 10 分钟内恢复相同结果
  static Future<MdtbbsJoinResult> consumeJoinIntent({
    required String accessToken,
    required String intentId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      '$_base/join-intents/$intentId/consume',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
      timeout: _callTimeout,
    );
    return MdtbbsJoinResult.fromJson(_map(data));
  }

  // ── 中继 ────────────────────────────────────────────────────

  /// 为当前对端申请官方中继凭证
  ///
  /// 返回的 `credential` 是短期秘密：**只放进中继 WSS 的第一条 AUTH 文本帧**，
  /// 不落盘、不进日志（P2 的隧道层负责）
  static Future<MdtbbsRelayAllocation> allocateRelay({
    required String accessToken,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    final envelope = await MdtbbsClient.postEnvelope(
      '$_base/sessions/$sessionId/relay',
      body: const {},
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    final map = _map(envelope.data);
    if (envelope.requestId != null) map['_requestId'] = envelope.requestId;
    return MdtbbsRelayAllocation.fromJson(map);
  }

  // ── 工具 ────────────────────────────────────────────────────

  static Map<String, dynamic> _map(Object? data) =>
      (data as Map?)?.cast<String, dynamic>() ?? const {};

  static List<Map<String, dynamic>> _list(Object? data) =>
      ((data as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
}

/// 退出的结果：普通成员离开 / 房主触发 60 秒关闭宽限
class MdtbbsLeaveOutcome {
  const MdtbbsLeaveOutcome({required this.status, required this.graceSeconds});

  /// `left` 或 `closing`
  final String status;

  /// 房主退出时的宽限秒数（60），普通成员为 0
  final int graceSeconds;

  bool get isOwnerLeaving => status == 'closing';
}

/// 对端心跳的返回
class MdtbbsHeartbeat {
  const MdtbbsHeartbeat({
    required this.peerId,
    required this.heartbeatIntervalSeconds,
    required this.expiresInSeconds,
  });

  final String peerId;

  /// 服务端给的节奏（30 秒），**以响应为准**而不是写死
  final int heartbeatIntervalSeconds;

  /// 判定线（90 秒）
  final int expiresInSeconds;
}
