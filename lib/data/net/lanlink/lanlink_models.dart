/// LanLink 控制面的数据模型
///
/// 协议契约见社区模组仓库的 `proto/PROTOCOL.md`（控制面 / 节点 / Mod 三端共用）；
/// 字段名以此为准，控制面新增字段一律当可选处理
library;

/// 房间码：形如 `MDT-XXXXXX`
///
/// 官方定义 6 位、字母表剔除易混的 `0O1I`；控制面按不透明字符串处理，
/// 所以这里只做「去空格 + 大写 + 补前缀」这类规范化，不校验字符集，免得误伤
class LanLinkRoomCode {
  const LanLinkRoomCode(this.value);

  final String value;

  /// 把用户输入整理成 `MDT-XXXXXX` 的形状；给不出就返回 null
  static LanLinkRoomCode? tryParse(String raw) {
    var text = raw.trim().toUpperCase().replaceAll(' ', '');
    if (text.isEmpty) return null;
    if (!text.startsWith('MDT-')) {
      if (text.startsWith('MDT')) {
        text = 'MDT-${text.substring(3)}';
      } else {
        text = 'MDT-$text';
      }
    }
    final body = text.substring(4);
    if (body.length != 6) return null;
    return LanLinkRoomCode(text);
  }

  static const int bodyLength = 6;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is LanLinkRoomCode && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// 直连候选（`create_room.direct` 与 `direct_candidates` 的元素）
///
/// 只是「提示」：v3 里真正可用的打洞地址由房主开房后经 `host_candidates` 上报
class LanLinkDirectCandidate {
  const LanLinkDirectCandidate({
    required this.mode,
    required this.addr,
    required this.tcpPort,
    required this.udpPort,
  });

  /// `upnp` | `stun` | `manual`
  final String mode;
  final String addr;
  final int tcpPort;
  final int udpPort;

  bool get isValid => addr.isNotEmpty && udpPort > 0 && udpPort <= 65535;

  /// 旧控制面只给单一 `port` 字段，这里按协议兼容规则补齐另一侧
  factory LanLinkDirectCandidate.fromJson(Map<String, dynamic> json) {
    var tcp = _toInt(json['tcp_port']);
    var udp = _toInt(json['udp_port']);
    if (tcp <= 0 && udp <= 0) {
      final single = _toInt(json['port']);
      tcp = single;
      udp = single;
    } else if (udp <= 0) {
      udp = tcp;
    } else if (tcp <= 0) {
      tcp = udp;
    }
    return LanLinkDirectCandidate(
      mode: '${json['mode'] ?? ''}',
      addr: '${json['addr'] ?? ''}',
      tcpPort: tcp,
      udpPort: udp,
    );
  }

  @override
  String toString() => mode.isEmpty ? '$addr:$udpPort' : '$mode $addr:$udpPort';
}

/// 房间
class LanLinkRoom {
  const LanLinkRoom({
    required this.code,
    required this.name,
    required this.displayName,
    required this.isPublic,
    required this.ownerId,
    required this.ownerUsername,
    required this.ownerPhoneVerified,
    required this.nodeId,
    required this.nodeName,
    required this.nodeAddr,
    required this.roomPort,
    required this.directCandidates,
  });

  final String code;
  final String name;
  final String displayName;
  final bool isPublic;

  final String ownerId;
  final String ownerUsername;
  final bool ownerPhoneVerified;

  final String nodeId;
  final String nodeName;
  final String nodeAddr;
  final int roomPort;

  final List<LanLinkDirectCandidate> directCandidates;

  /// 原版客户端（含本项目）加入用的地址；节点房间端口就是原生 Mindustry 端口
  String get relayAddress => '$nodeAddr:$roomPort';

  bool get hasRelayAddress => nodeAddr.isNotEmpty && roomPort > 0;

  factory LanLinkRoom.fromJson(Map<String, dynamic> json) {
    final node = (json['node'] as Map?)?.cast<String, dynamic>() ?? const {};
    final owner = (json['owner'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawCandidates = json['direct_candidates'];
    final candidates = <LanLinkDirectCandidate>[];
    if (rawCandidates is List) {
      for (final item in rawCandidates) {
        if (item is Map) {
          final candidate = LanLinkDirectCandidate.fromJson(
            item.cast<String, dynamic>(),
          );
          if (candidate.isValid) candidates.add(candidate);
        }
      }
    }
    // 兼容旧控制面：只有 direct 单对象
    if (candidates.isEmpty && json['direct'] is Map) {
      final candidate = LanLinkDirectCandidate.fromJson(
        (json['direct'] as Map).cast<String, dynamic>(),
      );
      if (candidate.isValid) candidates.add(candidate);
    }
    return LanLinkRoom(
      code: '${json['code'] ?? ''}',
      name: '${json['name'] ?? ''}',
      displayName: '${json['display_name'] ?? ''}',
      isPublic: json['public'] == true,
      ownerId: '${owner['id'] ?? ''}',
      ownerUsername: '${owner['username'] ?? ''}',
      ownerPhoneVerified: owner['phone_verified'] == true,
      nodeId: '${node['id'] ?? ''}',
      nodeName: '${node['name'] ?? ''}',
      nodeAddr: '${node['addr'] ?? ''}',
      roomPort: _toInt(node['room_port']),
      directCandidates: candidates,
    );
  }
}

/// 中继节点
class LanLinkNode {
  const LanLinkNode({
    required this.id,
    required this.name,
    required this.addr,
    required this.tunnelPort,
    required this.rooms,
    required this.official,
    required this.requiresLogin,
    required this.reason,
    required this.region,
  });

  final String id;
  final String name;
  final String addr;
  final int tunnelPort;
  final int rooms;

  /// 官方节点 / 社区节点
  final bool official;

  /// 控制面标记该节点是否要求先登录；未登录时 `usable` 为 false
  final bool requiresLogin;
  final String reason;
  final String region;

  factory LanLinkNode.fromJson(Map<String, dynamic> json) => LanLinkNode(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    addr: '${json['addr'] ?? ''}',
    tunnelPort: _toInt(json['tunnel_port']),
    rooms: _toInt(json['rooms']),
    official: json['official'] == true,
    requiresLogin: json['requires_login'] == true,
    reason: '${json['reason'] ?? ''}',
    region: '${json['region'] ?? ''}',
  );
}

/// 好友（含在线状态与所在房间）
///
/// `roomCode` 非空表示对方正在一个可加入的房间里，界面据此给「加入」入口
class LanLinkFriend {
  const LanLinkFriend({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.presenceStatus,
    required this.roomCode,
    required this.roomName,
  });

  final String id;
  final String username;
  final String avatarUrl;

  /// `online` | `idle` | `dnd` | `offline`
  final String presenceStatus;

  final String roomCode;
  final String roomName;

  bool get isOnline => presenceStatus != 'offline';
  bool get canJoin => roomCode.isNotEmpty;

  factory LanLinkFriend.fromJson(Map<String, dynamic> json) {
    final presence =
        (json['presence'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LanLinkFriend(
      id: '${json['id'] ?? ''}',
      username: '${json['username'] ?? ''}',
      avatarUrl: '${json['avatar_url'] ?? ''}',
      presenceStatus: '${presence['status'] ?? 'offline'}',
      roomCode: '${presence['room_code'] ?? ''}',
      roomName: '${presence['room_name'] ?? ''}',
    );
  }
}

/// 控制面版本信息（`GET /api/version`）
class LanLinkVersion {
  const LanLinkVersion({
    required this.latest,
    required this.minimum,
    required this.downloadUrl,
  });

  final String latest;
  final String minimum;
  final String downloadUrl;
}

/// 控制面登录态（`/api/auth/login` 与 `/api/auth/refresh` 同一形状）
class LanLinkAuthSession {
  const LanLinkAuthSession({
    required this.token,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.phoneVerified,
  });

  final String token;
  final String userId;
  final String username;
  final String displayName;

  /// 控制面在开房 / 加房时会查手机号验证，未验证会被挡下
  final bool phoneVerified;

  bool get isLoggedIn => token.isNotEmpty;

  factory LanLinkAuthSession.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LanLinkAuthSession(
      token: '${json['token'] ?? ''}',
      userId: '${user['id'] ?? ''}',
      username: '${user['username'] ?? ''}',
      displayName: '${user['display_name'] ?? user['username'] ?? ''}',
      phoneVerified: user['phone_verified'] == true,
    );
  }
}

/// 开房结果（控制面 `room_ok`）
///
/// `roomToken` 是房主与节点之间的唯一凭证，**不下发给客人**；
/// `guestToken` 是 v3 直连用的打洞凭证，取不到就只能走中继
class LanLinkHostRoom {
  const LanLinkHostRoom({
    required this.code,
    required this.roomTokenHex,
    required this.guestTokenHex,
    required this.displayName,
    required this.nodeId,
    required this.nodeName,
    required this.nodeAddr,
    required this.tunnelPort,
    required this.roomPort,
    required this.serverProtocol,
  });

  final String code;
  final String roomTokenHex;
  final String guestTokenHex;
  final String displayName;

  final String nodeId;
  final String nodeName;
  final String nodeAddr;

  /// 房主连节点的隧道端口
  final int tunnelPort;

  /// 客人用的公网端口（原生 Mindustry 端口）
  final int roomPort;

  /// 控制面支持的协议版本；低于 3 时直连不可用
  final int serverProtocol;

  /// 给朋友的那串地址
  String get publicAddress => '$nodeAddr:$roomPort';

  bool get canOpenTunnel =>
      nodeAddr.isNotEmpty && tunnelPort > 0 && roomTokenHex.length == 32;

  factory LanLinkHostRoom.fromJson(Map<String, dynamic> json) {
    final node = (json['node'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LanLinkHostRoom(
      code: '${json['code'] ?? ''}',
      roomTokenHex: '${json['room_token'] ?? ''}',
      guestTokenHex: '${json['guest_token'] ?? ''}',
      displayName: '${json['display_name'] ?? ''}',
      nodeId: '${node['id'] ?? ''}',
      nodeName: '${node['name'] ?? ''}',
      nodeAddr: '${node['addr'] ?? ''}',
      tunnelPort: _toInt(node['tunnel_port']),
      roomPort: _toInt(node['room_port']),
      serverProtocol: _toInt(json['protocol']),
    );
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
