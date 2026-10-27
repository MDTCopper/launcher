/// 联机会话（BBS 官方 `/api/v1/multiplayer`）的模型
///
/// 文档口径：**所有 ID（session/peer/invite/intent/allocation）都是不透明字符串，
/// 只能原样传回**；除好友用户 ID 外不要自行解析，也不要提交由服务端决定的字段
/// （`user_id` / `client_id` / 对端 `role` 等）。

library;

/// `GET /multiplayer/capabilities`
///
/// 展示任何联机入口前**必须**先核对这四个布尔与顶层 `multiplayer` 能力标志
class MdtbbsMultiplayerCapabilities {
  const MdtbbsMultiplayerCapabilities({
    required this.sessionsEnabled,
    required this.invitesEnabled,
    required this.relayEnabled,
    required this.thirdPartyEnabled,
    required this.visibility,
    required this.joinPolicies,
    required this.transports,
    required this.relayCredentialTtlSeconds,
    this.requireApprovalSupported = false,
    this.visibilityDeprecated = const [],
    this.joinPoliciesDeprecated = const [],
  });

  final bool sessionsEnabled;
  final bool invitesEnabled;
  final bool relayEnabled;
  final bool thirdPartyEnabled;

  /// `private` / `friends` / `public`（契约 1.7.0 起；旧值见 [visibilityDeprecated]）
  final List<String> visibility;

  /// `invite_only` / `friends` / `public`（契约 1.7.0 起）
  final List<String> joinPolicies;

  /// `udp` / `tcp` / `quic` / `custom`
  final List<String> transports;

  /// 中继凭证有效期（实测 120 秒）
  final int relayCredentialTtlSeconds;

  /// 服务端是否支持创建会话时带 `require_approval`
  final bool requireApprovalSupported;

  /// 旧客户端仍可提交的可见范围取值（`unlisted` 等），创建前不要主动选它们
  final List<String> visibilityDeprecated;

  /// 旧客户端仍可提交的加入方式取值（`open` / `request` 等）
  final List<String> joinPoliciesDeprecated;

  bool get usable => sessionsEnabled && thirdPartyEnabled; // 至少要有会话与第三方能力

  factory MdtbbsMultiplayerCapabilities.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) =>
        (json[key] as List?)?.map((e) => '$e').toList() ?? const [];
    return MdtbbsMultiplayerCapabilities(
      sessionsEnabled: json['sessions_v1'] == true,
      invitesEnabled: json['invites_v1'] == true,
      relayEnabled: json['relay_v1'] == true,
      thirdPartyEnabled: json['third_party_multiplayer'] == true,
      visibility: list('visibility'),
      joinPolicies: list('join_policies'),
      transports: list('transports'),
      // 文档示例 120；取不到就按 120 兜底（续签节奏的保守值）
      relayCredentialTtlSeconds:
          (json['relay_credential_ttl_seconds'] as num?)?.toInt() ?? 120,
      requireApprovalSupported: json['require_approval_supported'] == true,
      visibilityDeprecated: list('visibility_deprecated'),
      joinPoliciesDeprecated: list('join_policies_deprecated'),
    );
  }
}

/// 会话对象
class MdtbbsSession {
  const MdtbbsSession({
    required this.id,
    required this.ownerUserId,
    required this.visibility,
    required this.joinPolicy,
    required this.gameId,
    this.gameVersion,
    this.activityName,
    required this.currentPlayers,
    required this.maxPlayers,
    required this.status,
    this.expiresAt,
    this.requireApproval,
    this.joinable,
    this.blockedReason,
    this.canRequestJoin,
  });

  final String id;
  final String ownerUserId;
  final String visibility;
  final String joinPolicy;

  /// `game.id` / `game.version`
  final String gameId;
  final String? gameVersion;

  /// 好友看到的会话活动文字；缺省时服务端用 `game_id`
  final String? activityName;

  /// `joining` / `active` / 恢复窗口内的 `disconnected` 都占名额；`expired` 不占
  final int currentPlayers;
  final int maxPlayers;

  /// `active` / `closing` 等服务端状态
  final String status;
  final String? expiresAt;

  /// 服务端若回传就带上；没回传时界面用本机创建时的值兜底
  final bool? requireApproval;

  /// 大厅列表里服务端算好的「我能不能进」：`null` 表示这条信息没给
  final bool? joinable;

  /// 不能进的原因（人满 / 仅邀请 / 需审批…），只在 joinable == false 时有值
  final String? blockedReason;

  /// 需要审批时能不能发加入申请
  final bool? canRequestJoin;

  factory MdtbbsSession.fromJson(Map<String, dynamic> json) {
    final game = (json['game'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MdtbbsSession(
      id: '${json['id'] ?? ''}',
      ownerUserId: '${json['owner_user_id'] ?? ''}',
      visibility: '${json['visibility'] ?? ''}',
      joinPolicy: '${json['join_policy'] ?? ''}',
      gameId: '${game['id'] ?? ''}',
      gameVersion: game['version']?.toString(),
      activityName: json['activity_name']?.toString(),
      currentPlayers: (json['current_players'] as num?)?.toInt() ?? 0,
      maxPlayers: (json['max_players'] as num?)?.toInt() ?? 0,
      status: '${json['status'] ?? ''}',
      expiresAt: json['expires_at']?.toString(),
      requireApproval: json['require_approval'] as bool?,
      joinable: json['joinable'] as bool?,
      blockedReason: json['blocked_reason']?.toString(),
      canRequestJoin: json['can_request_join'] as bool?,
    );
  }
}

/// 会话对端；`role` 是服务端定的（owner / member），客户端只读
class MdtbbsPeer {
  const MdtbbsPeer({
    required this.peerId,
    required this.userId,
    required this.clientId,
    required this.role,
    required this.status,
    this.joinedAt,
    this.lastSeenAt,
    this.capabilities = const {},
  });

  final String peerId;
  final String userId;
  final String clientId;
  final String role;

  /// `joining` / `active` / `disconnected` / `expired`
  final String status;
  final String? joinedAt;
  final String? lastSeenAt;

  /// 加入时客户端提交的能力 JSON，服务端原样返回
  final Map<String, dynamic> capabilities;

  factory MdtbbsPeer.fromJson(Map<String, dynamic> json) => MdtbbsPeer(
    peerId: '${json['peer_id'] ?? ''}',
    userId: '${json['user_id'] ?? ''}',
    clientId: '${json['client_id'] ?? ''}',
    role: '${json['role'] ?? ''}',
    status: '${json['status'] ?? ''}',
    joinedAt: json['joined_at']?.toString(),
    lastSeenAt: json['last_seen_at']?.toString(),
    capabilities:
        (json['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

/// 创建 / 加入 / 恢复的返回：对端 + 恢复令牌
///
/// `resumeToken` **立即安全保存**：绑定用户与 OAuth client、只能用一次、
/// 恢复后服务端会轮换出新令牌
class MdtbbsJoinResult {
  const MdtbbsJoinResult({
    required this.peer,
    required this.resumeToken,
    required this.resumed,
  });

  final MdtbbsPeer peer;
  final String resumeToken;

  /// 恢复既有对端时为 true
  final bool resumed;

  factory MdtbbsJoinResult.fromJson(Map<String, dynamic> json) =>
      MdtbbsJoinResult(
        peer: MdtbbsPeer.fromJson(
          (json['peer'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        resumeToken: '${json['resume_token'] ?? ''}',
        resumed: json['resumed'] == true,
      );
}

/// 创建会话的完整返回；不公开会话多一个**一次性展示**的 joinCode（10 位十六进制）
class MdtbbsCreatedSession {
  const MdtbbsCreatedSession({
    required this.session,
    required this.peer,
    required this.resumeToken,
    this.joinCode,
  });

  final MdtbbsSession session;
  final MdtbbsPeer peer;
  final String resumeToken;

  /// 只在创建响应里返回一次（API 不会再给）；**房间从控制面注销前可复用**
  final String? joinCode;

  factory MdtbbsCreatedSession.fromJson(Map<String, dynamic> json) =>
      MdtbbsCreatedSession(
        session: MdtbbsSession.fromJson(
          (json['session'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        peer: MdtbbsPeer.fromJson(
          (json['peer'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        resumeToken: '${json['resume_token'] ?? ''}',
        joinCode: json['join_code']?.toString(),
      );
}

/// `POST /sessions/{id}/relay` 的返回：官方中继的短期凭证分配
///
/// **`credential` 是短期秘密**：只允许放进 WSS 的第一条 AUTH 文本帧，
/// 禁止进 URL、查询参数、日志或分析事件
class MdtbbsRelayAllocation {
  const MdtbbsRelayAllocation({
    required this.allocationId,
    required this.agentId,
    required this.endpoint,
    required this.credential,
    required this.expiresIn,
    this.requestId,
  });

  final String allocationId;
  final String agentId;

  /// 例如 `wss://relay.example.invalid:443/relay/v1`
  final String endpoint;
  final String credential;

  /// 凭证有效期（秒），实测与 capabilities 的 ttl 一致（120）
  final int expiresIn;

  /// 这次分配请求的 `request_id`（诊断用：中继拒绝认证时交给管理员查）
  final String? requestId;

  factory MdtbbsRelayAllocation.fromJson(Map<String, dynamic> json) =>
      MdtbbsRelayAllocation(
        allocationId: '${json['allocation_id'] ?? ''}',
        agentId: '${json['agent_id'] ?? ''}',
        endpoint: '${json['endpoint'] ?? ''}',
        credential: '${json['credential'] ?? ''}',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
        requestId: json['_requestId']?.toString(),
      );
}

/// 收到的邀请；`session` 是会话摘要
class MdtbbsInvite {
  const MdtbbsInvite({
    required this.inviteId,
    required this.sessionId,
    required this.senderUserId,
    required this.targetUserId,
    required this.status,
    this.expiresAt,
    this.session,
  });

  final String inviteId;
  final String sessionId;
  final String senderUserId;
  final String targetUserId;
  final String status;
  final String? expiresAt;
  final MdtbbsSession? session;

  factory MdtbbsInvite.fromJson(Map<String, dynamic> json) => MdtbbsInvite(
    inviteId: '${json['invite_id'] ?? ''}',
    sessionId: '${json['session_id'] ?? ''}',
    senderUserId: '${json['sender_user_id'] ?? ''}',
    targetUserId: '${json['target_user_id'] ?? ''}',
    status: '${json['status'] ?? ''}',
    expiresAt: json['expires_at']?.toString(),
    session: (json['session'] as Map?) == null
        ? null
        : MdtbbsSession.fromJson(
            (json['session'] as Map).cast<String, dynamic>(),
          ),
  );
}

/// 网络候选地址（STUN/NAT 探测由客户端负责）
class MdtbbsCandidate {
  const MdtbbsCandidate({
    required this.kind,
    required this.transport,
    required this.address,
    required this.port,
    required this.priority,
    this.metadata = const {},
    this.candidateId,
  });

  /// `public` / `local` 等
  final String kind;

  /// `udp` / `tcp` / …
  final String transport;
  final String address;
  final int port;
  final int priority;
  final Map<String, dynamic> metadata;

  /// 发布后服务端返回的 ID（删除候选时要原样传回）
  final String? candidateId;

  Map<String, dynamic> toRequestJson() => {
    'kind': kind,
    'transport': transport,
    'address': address,
    'port': port,
    'priority': priority,
    'metadata': metadata,
  };

  factory MdtbbsCandidate.fromJson(Map<String, dynamic> json) =>
      MdtbbsCandidate(
        kind: '${json['kind'] ?? ''}',
        transport: '${json['transport'] ?? ''}',
        address: '${json['address'] ?? ''}',
        port: (json['port'] as num?)?.toInt() ?? 0,
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        metadata:
            (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
        candidateId: json['candidate_id']?.toString() ?? json['id']?.toString(),
      );
}

/// 加入意图：60 秒内首次使用，同一用户与 OAuth 客户端可在 10 分钟内恢复相同结果
class MdtbbsJoinIntent {
  const MdtbbsJoinIntent({required this.intentId, this.expiresAt});

  final String intentId;
  final String? expiresAt;

  factory MdtbbsJoinIntent.fromJson(Map<String, dynamic> json) {
    // 服务端可能把意图包一层（`join_intent` / `intent`）给出对象，也可能直接给 id 字符串
    final nested = json['join_intent'] ?? json['intent'];
    final source = nested is Map ? nested.cast<String, dynamic>() : json;
    final direct = nested is String ? nested : null;
    return MdtbbsJoinIntent(
      intentId:
          '${direct ?? source['intent_id'] ?? source['id'] ?? json['join_intent_id'] ?? ''}',
      expiresAt: (source['expires_at'] ?? json['expires_at'])?.toString(),
    );
  }
}

/// `GET /multiplayer/preferences`：用户默认的加入意图客户端
class MdtbbsMultiplayerPreferences {
  const MdtbbsMultiplayerPreferences({
    required this.defaultClientId,
    required this.clients,
  });

  final String? defaultClientId;
  final List<MdtbbsClientSummary> clients;

  factory MdtbbsMultiplayerPreferences.fromJson(Map<String, dynamic> json) =>
      MdtbbsMultiplayerPreferences(
        defaultClientId: json['default_client_id']?.toString(),
        clients: ((json['clients'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MdtbbsClientSummary.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

/// 客户端摘要（来自用户授权过的 OAuth 应用）
class MdtbbsClientSummary {
  const MdtbbsClientSummary({
    required this.clientId,
    required this.name,
    this.iconUrl,
    this.supportsMultiplayer = false,
    this.supportsJoinIntent = false,
  });

  final String clientId;
  final String name;
  final String? iconUrl;
  final bool supportsMultiplayer;
  final bool supportsJoinIntent;

  factory MdtbbsClientSummary.fromJson(Map<String, dynamic> json) =>
      MdtbbsClientSummary(
        clientId: '${json['client_id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        iconUrl: json['application_icon_url']?.toString(),
        supportsMultiplayer: json['supports_multiplayer'] == true,
        supportsJoinIntent: json['supports_join_intent'] == true,
      );
}

/// 把服务端 JSON 里的整数 / 字符串用户 ID 统一成字符串（只原样传回，不解析）
String mdtbbsUserIdOf(Object? value) => '$value';
