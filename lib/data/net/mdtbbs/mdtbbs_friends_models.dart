/// BBS 官方好友与在线聚合的模型（`/api/v1/friends*`、`/api/v1/social/friends/presence`）
///
/// 三条口径：
/// - **按钮权限由服务端算**：`actions` 里的 `can_*` 直接用，客户端不按在线状态或会话策略自己推导
/// - 好友用户 ID 是**唯一允许自行解析**的 ID（其余 ID 一律当不透明字符串原样传回）
/// - 隐私策略不允许展示的资料服务端根本不返回 ⇒ 可选字段都可能缺，缺了按最保守的语义兜底
class MdtbbsFriendUser {
  const MdtbbsFriendUser({
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.friendshipSince,
  });

  /// 论坛用户**整数** ID：加好友 / 发邀请 / 删好友都用它
  final int userId;
  final String username;
  final String? avatarUrl;

  /// 成为好友的时间（服务端给字符串，不解析）
  final String? friendshipSince;

  factory MdtbbsFriendUser.fromJson(Map<String, dynamic> json) =>
      MdtbbsFriendUser(
        userId: (json['id'] as num?)?.toInt() ?? 0,
        username: '${json['username'] ?? ''}',
        avatarUrl: json['avatar_url']?.toString(),
        friendshipSince: json['friendship_since']?.toString(),
      );
}

/// 在线状态；隐藏或不可见时服务端按隐私策略给 `offline`
class MdtbbsFriendPresence {
  const MdtbbsFriendPresence({required this.status, this.lastSeenAt});

  /// `online` / `idle` / `dnd` / `offline`
  final String status;

  /// 只在设置允许且当前离线时出现
  final DateTime? lastSeenAt;

  bool get isOnline => status != 'offline';

  factory MdtbbsFriendPresence.fromJson(Map<String, dynamic> json) {
    final seconds = (json['last_seen_at'] as num?)?.toInt();
    return MdtbbsFriendPresence(
      // 认不出就按离线，别把状态不明的人显示成在线
      status: '${json['status'] ?? 'offline'}',
      lastSeenAt: seconds == null || seconds <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    );
  }
}

/// 富活动状态（好友正在玩什么）
class MdtbbsFriendActivity {
  const MdtbbsFriendActivity({
    required this.type,
    required this.name,
    this.details,
    this.state,
    this.gameId,
    this.gameVersion,
    this.partyCurrent,
    this.partyMax,
    this.joinSessionId,
    this.clientId,
    this.clientName,
  });

  /// `playing` / `hosting` / `editing` / `browsing` / `downloading` / `uploading` / `launcher` / `custom`
  final String type;
  final String name;
  final String? details;
  final String? state;
  final String? gameId;
  final String? gameVersion;
  final int? partyCurrent;
  final int? partyMax;

  /// 好友正在玩的会话 —— 配合 [MdtbbsFriendActions.canJoin] 用
  final String? joinSessionId;
  final String? clientId;
  final String? clientName;

  factory MdtbbsFriendActivity.fromJson(Map<String, dynamic> json) {
    final game = (json['game'] as Map?)?.cast<String, dynamic>() ?? const {};
    final party = (json['party'] as Map?)?.cast<String, dynamic>() ?? const {};
    final join = (json['join'] as Map?)?.cast<String, dynamic>() ?? const {};
    final client = (json['client'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MdtbbsFriendActivity(
      type: '${json['type'] ?? ''}',
      name: '${json['name'] ?? ''}',
      details: json['details']?.toString(),
      state: json['state']?.toString(),
      gameId: game['id']?.toString(),
      gameVersion: game['version']?.toString(),
      partyCurrent: (party['current'] as num?)?.toInt(),
      partyMax: (party['max'] as num?)?.toInt(),
      joinSessionId: join['session_id']?.toString(),
      clientId: json['client_id']?.toString(),
      clientName: client['name']?.toString(),
    );
  }
}

/// 服务端算好的动作门禁（含屏蔽关系、隐私、会话策略、名额）
class MdtbbsFriendActions {
  const MdtbbsFriendActions({
    this.canJoin = false,
    this.canRequestJoin = false,
    this.canInvite = false,
    this.inviteSessionId,
    this.sessionVisible = false,
  });

  final bool canJoin;
  final bool canRequestJoin;
  final bool canInvite;

  /// 可以邀请对方进哪个会话（我的会话）；[canInvite] 为真时才给
  final String? inviteSessionId;

  /// 我能不能看见关联的那个会话
  final bool sessionVisible;

  /// 邀请这条路的完整判定：允许 + 有可用的会话 ID 才算真能邀请
  bool get canInviteIntoSession =>
      canInvite && (inviteSessionId?.isNotEmpty ?? false);

  factory MdtbbsFriendActions.fromJson(Map<String, dynamic> json) =>
      MdtbbsFriendActions(
        canJoin: json['can_join'] == true,
        canRequestJoin: json['can_request_join'] == true,
        canInvite: json['can_invite'] == true,
        inviteSessionId: json['invite_session_id']?.toString(),
        sessionVisible: json['session_visible'] == true,
      );
}

/// 好友在线聚合的一项：好友 + 在线 + 活动 + 门禁
class MdtbbsFriendEntry {
  const MdtbbsFriendEntry({
    required this.user,
    required this.presence,
    required this.actions,
    this.activity,
  });

  final MdtbbsFriendUser user;
  final MdtbbsFriendPresence presence;
  final MdtbbsFriendActions actions;
  final MdtbbsFriendActivity? activity;

  bool get isOnline => presence.isOnline;

  factory MdtbbsFriendEntry.fromJson(Map<String, dynamic> json) {
    final activity = json['activity'];
    return MdtbbsFriendEntry(
      user: MdtbbsFriendUser.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      presence: MdtbbsFriendPresence.fromJson(
        (json['presence'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      actions: MdtbbsFriendActions.fromJson(
        (json['actions'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      activity: activity is Map
          ? MdtbbsFriendActivity.fromJson(activity.cast<String, dynamic>())
          : null,
    );
  }
}

/// 好友在线聚合的一页（`GET /social/friends/presence` 的 `data`）
///
/// 翻页信息官方在 `data.pagination` 与 `meta.pagination` 各给一份，
/// 这里读 `data` 那份（`totalPages` 换算成 [hasMore]）
class MdtbbsFriendPage {
  const MdtbbsFriendPage({
    required this.entries,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  final List<MdtbbsFriendEntry> entries;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  bool get hasMore => page < totalPages;
  int get onlineCount => entries.where((entry) => entry.isOnline).length;

  factory MdtbbsFriendPage.fromJson(Map<String, dynamic> json) {
    final rows = (json['data'] as List?) ?? const [];
    final pagination = (json['pagination'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final entries = <MdtbbsFriendEntry>[
      for (final row in rows)
        if (row is Map) MdtbbsFriendEntry.fromJson(row.cast<String, dynamic>()),
    ];
    return MdtbbsFriendPage(
      entries: entries,
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      limit: (pagination['limit'] as num?)?.toInt() ?? entries.length,
      total: (pagination['total'] as num?)?.toInt() ?? entries.length,
      totalPages: (pagination['totalPages'] as num?)?.toInt() ??
          (pagination['total_pages'] as num?)?.toInt() ??
          1,
    );
  }
}

/// 待处理的好友请求
///
/// 官方文档只写「返回当前账号可见记录数组」，没给逐字段表 ⇒ 请求 ID 与请求人
/// 都从几个候选键里取（见 [fromJson]），取不到就给 null，别硬猜；
/// [raw] 留一份原始记录，真机 probe 回来后再收紧
class MdtbbsFriendRequest {
  const MdtbbsFriendRequest({
    required this.requestId,
    this.user,
    this.createdAt,
    this.message,
    this.raw = const {},
  });

  /// **请求 ID**（接受 / 拒绝用它），不是用户 ID
  final String requestId;

  /// 对方公开资料；服务端可能不给（隐私 / 形态不同）
  final MdtbbsFriendUser? user;
  final String? createdAt;
  final String? message;
  final Map<String, dynamic> raw;

  factory MdtbbsFriendRequest.fromJson(Map<String, dynamic> json) {
    final user = _userPayloadOf(json);
    return MdtbbsFriendRequest(
      requestId:
          '${json['request_id'] ?? json['id'] ?? json['friendship_request_id'] ?? ''}',
      user: user == null ? null : MdtbbsFriendUser.fromJson(user),
      createdAt:
          json['created_at']?.toString() ?? json['requested_at']?.toString(),
      message: json['message']?.toString(),
      raw: json,
    );
  }

  /// 请求人可能挂在 `requester` / `sender` / `user` 等键下，
  /// 也可能直接把 `id` + `username` 摊在顶层
  static Map<String, dynamic>? _userPayloadOf(Map<String, dynamic> json) {
    for (final key in const ['requester', 'sender', 'user', 'from', 'target']) {
      final value = json[key];
      if (value is Map) return value.cast<String, dynamic>();
    }
    return json.containsKey('username') ? json : null;
  }
}

/// 好友请求的一页；形态在 `data` / `requests` / 裸数组之间都认
class MdtbbsFriendRequestPage {
  const MdtbbsFriendRequestPage({
    required this.requests,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  final List<MdtbbsFriendRequest> requests;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  bool get hasMore => page < totalPages;

  factory MdtbbsFriendRequestPage.fromJson(Map<String, dynamic> json) {
    final rows = _rowsOf(json);
    final pagination = (json['pagination'] as Map?)?.cast<String, dynamic>() ??
        const {};
    return MdtbbsFriendRequestPage(
      requests: [
        for (final row in rows)
          if (row is Map)
            MdtbbsFriendRequest.fromJson(row.cast<String, dynamic>()),
      ],
      total: (json['total'] as num?)?.toInt() ?? rows.length,
      page: (pagination['page'] as num?)?.toInt() ??
          (json['page'] as num?)?.toInt() ??
          1,
      limit: (pagination['limit'] as num?)?.toInt() ??
          (json['limit'] as num?)?.toInt() ??
          rows.length,
      totalPages: (pagination['totalPages'] as num?)?.toInt() ??
          (pagination['total_pages'] as num?)?.toInt() ??
          (json['totalPages'] as num?)?.toInt() ??
          (json['total_pages'] as num?)?.toInt() ??
          1,
    );
  }

  static List<Object?> _rowsOf(Map<String, dynamic> json) {
    for (final key in const ['data', 'requests', 'items']) {
      final value = json[key];
      if (value is List) return value;
    }
    return const [];
  }
}

/// 好友在线聚合里的一项能不能直接加入（`canJoin` 的现成判断，免得各页面各写一遍）
extension MdtbbsFriendJoinTarget on MdtbbsFriendEntry {
  /// 好友正在玩、且服务端允许我直接加入时，给出去哪个会话
  String? get joinableSessionId {
    if (!actions.canJoin) return null;
    final sessionId = activity?.joinSessionId;
    return (sessionId?.isEmpty ?? true) ? null : sessionId;
  }
}
