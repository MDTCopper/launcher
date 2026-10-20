import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';

/// 联机（官方 multiplayer）在界面上的唯一状态源
///
/// 这些数据曾经散在页面 State 里 ⇒ 切页就丢、每次进页面都要重新拉四个接口。
/// 现在由 [MdtbbsMultiplayerService] 持有，页面只订阅
class MultiplayerState {
  const MultiplayerState({
    this.capabilities,
    this.capabilitiesLoaded = false,
    this.session,
    this.joinCode,
    this.self,
    this.peers = const [],
    this.resuming = false,
    this.proxyRunning = false,
    this.localAddress,
    this.reconnecting = false,
    this.reconnectAttempt = 0,
    this.proxyError,
    this.lastHeartbeatAt,
    this.heartbeatFailures = 0,
    this.lastMessage,
    this.lastMessageIsError = false,
    this.creating = false,
    this.joining = false,
    this.leaving = false,
    this.refreshingPeers = false,
    this.startingProxy = false,
    this.stoppingProxy = false,
    this.loadingCapabilities = false,
    this.invites = const [],
    this.sentInvites = const [],
    this.loadingInvites = false,
    this.inviting = false,
    this.busyInviteId,
  });

  // ── 能力（进页面拉一次，缓存住） ──
  final MdtbbsMultiplayerCapabilities? capabilities;
  final bool capabilitiesLoaded;
  final bool loadingCapabilities;

  // ── 会话 ──
  final MdtbbsSession? session;

  /// 加入码：**服务端只在创建响应里给一次**，随会话落盘保住
  final String? joinCode;

  /// 自己在会话里的对端（心跳要用它）
  final MdtbbsPeer? self;

  final List<MdtbbsPeer> peers;

  /// 是否正在从落盘状态恢复（界面可先显示「恢复中」）
  final bool resuming;

  // ── 联机通道 ──
  final bool proxyRunning;
  final String? localAddress;

  /// 通道断开后正在自动重连
  final bool reconnecting;

  /// 已重连次数（1 起；界面显示「正在重连（n/3）」）
  final int reconnectAttempt;

  /// 最终失败给用户看的一句话（原始错误只进日志）
  final String? proxyError;

  // ── 心跳 ──
  final DateTime? lastHeartbeatAt;
  final int heartbeatFailures;

  // ── 最近一条消息（切页也不丢） ──
  final String? lastMessage;
  final bool lastMessageIsError;

  // ── 按操作粒度：只禁用相关按钮，不再整页锁死 ──
  final bool creating;
  final bool joining;
  final bool leaving;
  final bool refreshingPeers;
  final bool startingProxy;
  final bool stoppingProxy;

  bool get inSession => session != null;

  /// 在线成员数：**人数显示用它，不读建 / 加房那一刻的 `currentPlayers`**
  int get onlinePeerCount =>
      peers.where((peer) => peer.status == 'active').length;

  // ── 邀请 ──
  /// 收到的邀请；只有 5 分钟有效期，靠页面可见时定时刷
  final List<MdtbbsInvite> invites;

  /// **我发出的邀请**：服务端不提供「我发出的」列表，只能在创建响应里记下来
  /// ⇒ 这是内存态，重启即丢（列表本身也会在 5 分钟后失效，不值得落盘）
  final List<MdtbbsInvite> sentInvites;

  final bool loadingInvites;

  /// 正在发邀请（弹窗里按这个禁用按钮）
  final bool inviting;

  /// 正在处理的邀请 ID（接受 / 拒绝 / 撤销）：按操作粒度禁用，不整页锁死
  final String? busyInviteId;

  /// 从落盘恢复过会话 ID、但服务端快照还没回来
  bool get waitingForSession => session == null && joinCode != null;

  /// 长动作中（用于「处理中…」提示，不用于禁用整页）
  bool get anyBusy =>
      creating ||
      joining ||
      leaving ||
      refreshingPeers ||
      startingProxy ||
      stoppingProxy ||
      inviting;

  String get workloadLabel {
    if (creating) return '正在创建房间…';
    if (joining) return '正在加入房间…';
    if (leaving) return '正在离开房间…';
    if (startingProxy) return '正在启动联机通道…';
    if (stoppingProxy) return '正在停止联机通道…';
    if (refreshingPeers) return '正在刷新成员…';
    if (inviting) return '正在发送邀请…';
    if (resuming) return '正在恢复房间…';
    return '处理中…';
  }

  /// 待处理的邀请条数（页面上的角标用）
  int get pendingInviteCount => invites.length;

  MultiplayerState copyWith({
    MdtbbsMultiplayerCapabilities? capabilities,
    bool? capabilitiesLoaded,
    bool? loadingCapabilities,
    MdtbbsSession? session,
    String? joinCode,
    MdtbbsPeer? self,
    List<MdtbbsPeer>? peers,
    bool? resuming,
    bool? proxyRunning,
    String? localAddress,
    bool? reconnecting,
    int? reconnectAttempt,
    String? proxyError,
    DateTime? lastHeartbeatAt,
    int? heartbeatFailures,
    String? lastMessage,
    bool? lastMessageIsError,
    bool? creating,
    bool? joining,
    bool? leaving,
    bool? refreshingPeers,
    bool? startingProxy,
    bool? stoppingProxy,
    List<MdtbbsInvite>? invites,
    List<MdtbbsInvite>? sentInvites,
    bool? loadingInvites,
    bool? inviting,
    String? busyInviteId,
    bool clearSession = false,
    bool clearJoinCode = false,
    bool clearSelf = false,
    bool clearLocalAddress = false,
    bool clearProxyError = false,
    bool clearMessage = false,
    bool clearInvites = false,
    bool clearSentInvites = false,
    bool clearBusyInvite = false,
  }) => MultiplayerState(
    capabilities: capabilities ?? this.capabilities,
    capabilitiesLoaded: capabilitiesLoaded ?? this.capabilitiesLoaded,
    loadingCapabilities: loadingCapabilities ?? this.loadingCapabilities,
    session: clearSession ? null : (session ?? this.session),
    joinCode: clearJoinCode ? null : (joinCode ?? this.joinCode),
    self: clearSelf ? null : (self ?? this.self),
    peers: peers ?? this.peers,
    resuming: resuming ?? this.resuming,
    proxyRunning: proxyRunning ?? this.proxyRunning,
    localAddress: clearLocalAddress
        ? null
        : (localAddress ?? this.localAddress),
    reconnecting: reconnecting ?? this.reconnecting,
    reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    proxyError: clearProxyError ? null : (proxyError ?? this.proxyError),
    lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
    heartbeatFailures: heartbeatFailures ?? this.heartbeatFailures,
    lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
    lastMessageIsError: lastMessageIsError ?? this.lastMessageIsError,
    creating: creating ?? this.creating,
    joining: joining ?? this.joining,
    leaving: leaving ?? this.leaving,
    refreshingPeers: refreshingPeers ?? this.refreshingPeers,
    startingProxy: startingProxy ?? this.startingProxy,
    stoppingProxy: stoppingProxy ?? this.stoppingProxy,
    invites: clearInvites ? const [] : (invites ?? this.invites),
    sentInvites: clearSentInvites
        ? const []
        : (sentInvites ?? this.sentInvites),
    loadingInvites: loadingInvites ?? this.loadingInvites,
    inviting: inviting ?? this.inviting,
    busyInviteId: clearBusyInvite ? null : (busyInviteId ?? this.busyInviteId),
  );
}
