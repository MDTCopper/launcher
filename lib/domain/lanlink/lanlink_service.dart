import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/data/net/lanlink/lanlink_api.dart';
import 'package:copper_launcher/data/net/lanlink/lanlink_host_client.dart';
import 'package:copper_launcher/data/net/lanlink/lanlink_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/lanlink/lanlink_host_session.dart';
import 'package:copper_launcher/domain/lanlink/lanlink_join_session.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 联机会话的门面：房间码解析 / 开房 / 本地桥的生命周期
///
/// **凭据不在这里**：联机令牌与 BBS 同属一个论坛账号，存在 [AccountManager] 里
/// （同一份账号文件、同一套加密），这里只取用
class LanLinkService {
  LanLinkService._();

  static final LanLinkService instance = LanLinkService._();

  AccountManager get _accounts => AccountManager.instance;

  /// 控制面地址，留空用官方服务
  String? controlUrl;

  LanLinkJoinSession? _active;
  LanLinkRoom? _activeRoom;

  /// 最近一次登录 / 刷新拿到的用户资料（只在内存，凭据在账号层）
  LanLinkAuthSession? _profile;

  LanLinkHostClient? _hostClient;
  LanLinkHostSession? _hostSession;
  LanLinkHostRoom? _hostedRoom;

  LanLinkJoinSession? get activeSession => _active;
  LanLinkRoom? get activeRoom => _activeRoom;
  bool get isJoined => _active?.isRunning ?? false;

  /// 开房后的房间信息（房间码与公网地址都在里面）
  LanLinkHostRoom? get hostedRoom => _hostedRoom;
  bool get isHosting => _hostSession?.isRunning ?? false;

  /// 当前这条桥走的是直连还是节点中继（界面提示用）
  bool get isDirectJoined => _active?.direct ?? false;

  /// MDT 兼容：本机桥地址（游戏「局域网游戏」列表里显示的就是它）
  String get localAddress =>
      _active?.localAddress ??
      '127.0.0.1:${LanLinkJoinSession.defaultLocalPort}';

  /// 已接进来的客人数（TCP 数据链 + UDP 会话）
  int get guestCount =>
      (_hostSession?.guestTcpCount ?? 0) +
      (_hostSession?.guestUdpSessions ?? 0);

  /// 最近一次拿到的用户资料；没有就退回社区账号的用户名
  LanLinkAuthSession? get auth => _profile;

  /// 联机服务是否已登录：**只看账号层那份令牌**
  bool get isLoggedIn => token != null;

  String? get token => _accounts.lanlinkToken;

  /// 号码验证状态；未知时按社区账号那份来（同一个账号，结论一致）
  bool get phoneVerified =>
      _profile?.phoneVerified ?? _accounts.account?.phoneVerified == true;

  /// 显示名；优先用联机服务回的，其次社区账号的
  String get displayName =>
      _profile?.displayName ??
      _accounts.account?.username ??
      _profile?.username ??
      '';

  // -- 登录态 ------------------------------------------------------------

  /// 用论坛账号登录联机服务，令牌存进账号层
  Future<LanLinkAuthSession> login({
    required String username,
    required String password,
  }) async {
    final session = await LanLinkApi.login(
      username: username,
      password: password,
      controlUrl: controlUrl,
    );
    _profile = session;
    _accounts.saveLanlinkToken(session.token);
    return session;
  }

  /// **优先走这条路**：拿社区账号（浏览器登录）的凭证直接换联机令牌
  ///
  /// 前提是那次授权带了 `openid`；服务端还没给本应用批这个 scope 时返回 false，
  /// 调用方就退回 [login]（账号密码）。这样两头的逻辑都在，开关只差一个 scope
  Future<bool> loginWithAccount() async {
    final accessToken = await _accounts.ensureAccessToken();
    if (accessToken == null) return false;
    try {
      final session = await LanLinkApi.exchangeMindAuthToken(
        accessToken: accessToken,
        controlUrl: controlUrl,
      );
      _profile = session;
      _accounts.saveLanlinkToken(session.token);
      return true;
    } on LanLinkException catch (error) {
      // 令牌没带 openid（还没获批）就是这条路走不通，让用户退回密码登录
      if (error.isUnauthorized) return false;
      rethrow;
    }
  }

  /// 用令牌重新问一次用户与手机号验证状态（令牌可能过期，失败就当作登出）
  Future<LanLinkAuthSession> refreshAuth() async {
    final current = token;
    if (current == null) {
      throw const LanLinkException(message: '还没有登录联机服务');
    }
    final session = await LanLinkApi.refresh(current, controlUrl: controlUrl);
    _profile = session;
    // 刷新会轮换令牌，要覆盖回去
    _accounts.saveLanlinkToken(session.token);
    return session;
  }

  Future<void> logout() async {
    _profile = null;
    _accounts.clearLanlinkToken();
  }

  // -- 查询 --------------------------------------------------------------

  /// 按房间码解析房间；房间不存在或已关闭返回 null
  Future<LanLinkRoom?> resolve(LanLinkRoomCode code) =>
      LanLinkApi.room(code, controlUrl: controlUrl);

  Future<List<LanLinkRoom>> publicRooms() =>
      LanLinkApi.publicRooms(controlUrl: controlUrl);

  Future<List<LanLinkNode>> nodes() => LanLinkApi.nodes(controlUrl: controlUrl);

  Future<List<LanLinkFriend>> friends() async {
    final current = token;
    if (current == null) {
      throw const LanLinkException(message: '请先登录联机服务');
    }
    return LanLinkApi.friends(current, controlUrl: controlUrl);
  }

  // -- 本地桥 ------------------------------------------------------------

  /// 加入房间：先拆掉上一条桥，再起新的
  ///
  /// 拆旧桥是必须的：本地端口与组播端口都只有一个，不释放就绑不上
  Future<LanLinkJoinSession> join(LanLinkRoom room) async {
    if (!room.hasRelayAddress) {
      throw const LanLinkException(message: '房间缺少可加入的地址');
    }
    // 进房与开房互斥：本机要么是房主要么是客人
    await leave();
    await stopHosting();
    // **直连优先**：候选地址先试连通，都不通才回落节点中继
    final upstream = await _chooseUpstream(room);
    final session = LanLinkJoinSession(
      roomCode: room.code,
      remoteHost: upstream.host,
      remotePort: upstream.tcpPort,
      remoteUdpPort: upstream.udpPort,
      direct: upstream.direct,
      roomName: room.name.isEmpty ? room.code : room.name,
    );
    await session.start();
    _active = session;
    _activeRoom = room;
    return session;
  }

  /// 直连优先：把房间给的候选逐个试 TCP 连通，全不通回落节点中继
  ///
  /// 候选是模组那边发布出来的（`upnp` / `stun` / `manual`），所以这条路
  /// 不需要我们自己打洞；试连超时给得短，别让用户等
  Future<({String host, int tcpPort, int udpPort, bool direct})>
  _chooseUpstream(LanLinkRoom room) async {
    final candidates = room.directCandidates.where((it) => it.isValid).toList();
    if (candidates.isNotEmpty) {
      // **并行**试连：串行会按 1.5 秒 × 候选数加在加入耗时上，
      // 而实测基本都回落中继，不值得让用户等
      final reachable = await Future.wait([
        for (final candidate in candidates)
          _isReachable(candidate.addr, candidate.tcpPort),
      ]);
      for (var index = 0; index < candidates.length; index++) {
        final candidate = candidates[index];
        addLogAndPrint(
          .info,
          '直连候选 ${candidate.mode} ${candidate.addr}:${candidate.tcpPort}'
          ' → ${reachable[index] ? '可用' : '不通'}',
          tag: 'LanLink',
        );
        if (reachable[index]) {
          return (
            host: candidate.addr,
            tcpPort: candidate.tcpPort,
            udpPort: candidate.udpPort,
            direct: true,
          );
        }
      }
    }
    addLogAndPrint(
      .info,
      '直连都不通，回落节点中继 ${room.nodeAddr}:${room.roomPort}',
      tag: 'LanLink',
    );
    return (
      host: room.nodeAddr,
      tcpPort: room.roomPort,
      udpPort: room.roomPort,
      direct: false,
    );
  }

  Future<bool> _isReachable(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> leave() async {
    final session = _active;
    _active = null;
    _activeRoom = null;
    await session?.dispose();
  }

  // -- 开房 --------------------------------------------------------------

  /// 开房：向控制面要一个房间，再把端点隧道接到本机游戏端口
  ///
  /// [gamePort] 是游戏自己的监听端口；玩家要先在游戏里「开放主机」把服务器开起来，
  /// 否则隧道接上去也是空的
  Future<LanLinkHostRoom> host({
    required String roomName,
    required int gamePort,
    bool isPublic = false,
  }) async {
    // 开房与进房互斥：本机要么是房主要么是客人
    await leave();
    await stopHosting();

    final client = await LanLinkHostClient.open(
      roomName: roomName,
      gamePort: gamePort,
      isPublic: isPublic,
      token: token,
      controlUrl: controlUrl,
    );
    final session = LanLinkHostSession(room: client.room, gamePort: gamePort);
    try {
      await session.start();
    } on Object {
      await client.close();
      rethrow;
    }
    _hostClient = client;
    _hostSession = session;
    _hostedRoom = client.room;
    // 房间被服务端关掉时把本地也收干净，免得界面还显示在开房
    unawaited(
      client.onRoomClosed.then((reason) {
        if (_hostClient != client) return;
        addLog(.info, '房间已关闭：$reason', tag: 'LanLink');
        unawaited(stopHosting());
      }),
    );
    return client.room;
  }

  Future<void> stopHosting() async {
    final client = _hostClient;
    final session = _hostSession;
    _hostClient = null;
    _hostSession = null;
    _hostedRoom = null;
    await session?.dispose();
    await client?.close();
  }
}
