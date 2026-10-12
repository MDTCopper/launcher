import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_api.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_relay_proxy.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_relay_tunnel.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 官方联机会话的门面：会话状态 + 本机代理（中继隧道 + 桥）的生命周期
///
/// 与 LanLink 兼容位的服务同构的考虑：状态收在单例里而不是页面里，
/// 页面切走再回来也能看到当前会话与代理
class MdtbbsMultiplayerService {
  MdtbbsMultiplayerService._();

  static final MdtbbsMultiplayerService instance = MdtbbsMultiplayerService._();

  MdtbbsRelayTunnel? _tunnel;
  MdtbbsRelayGuestProxy? _guest;
  MdtbbsRelayHostBridge? _host;
  StreamSubscription<MdtbbsRelaySignal>? _signalSubscription;

  String? _sessionId;
  String? _peerRole;
  String? _localAddress;

  /// 恢复令牌：绑定用户与 OAuth client、一次性、恢复后轮换；
  /// **内存暂存**，断线恢复（P5）时用，退出会话即弃
  String? _resumeToken;

  Timer? _heartbeatTimer;
  String? _peerId;
  int _heartbeatFailures = 0;

  bool get isProxyRunning => _tunnel != null;

  /// 当前会话（代理启动后才有意义）
  String? get sessionId => _sessionId;

  /// 本会话里的角色（owner / member），来自中继 auth_ok
  String? get peerRole => _peerRole;

  /// 游戏该连的本机地址
  String get localAddress => _localAddress ?? '127.0.0.1:6567';

  /// 页面在建会话 / 加入成功后把恢复令牌交进来
  void storeResumeToken({required String sessionId, required String token}) {
    _sessionId = sessionId;
    _resumeToken = token.isEmpty ? null : token;
  }

  /// 当前会话的恢复令牌（P5 的断线恢复用：join 时作为 `resume_token` 提交）
  String? get resumeToken => _resumeToken;

  /// 开始对端心跳：**30 秒一次**，90 秒收不到服务端就把我们判过期
  /// （不心跳的会话会被清理，`sessions/mine` 随后就查不到了）
  void startHeartbeat({
    required String sessionId,
    required String peerId,
    required Future<String?> Function() tokenProvider,
  }) {
    stopHeartbeat();
    _peerId = peerId;
    _heartbeatFailures = 0;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_beat(sessionId, peerId, tokenProvider));
    });
    addLog(.info, '已开始对端心跳（30 秒一次，peer=$peerId）', tag: 'Multiplayer');
  }

  Future<void> _beat(
    String sessionId,
    String peerId,
    Future<String?> Function() tokenProvider,
  ) async {
    try {
      final token = await tokenProvider();
      if (token == null) return;
      final beat = await MdtbbsMultiplayerApi.peerHeartbeat(
        accessToken: token,
        sessionId: sessionId,
        peerId: peerId,
      );
      _heartbeatFailures = 0;
      addLog(
        .debug,
        '心跳成功（服务端节奏 ${beat.heartbeatIntervalSeconds}s / 判定 ${beat.expiresInSeconds}s）',
        tag: 'Multiplayer',
      );
    } on Object catch (error) {
      _heartbeatFailures++;
      addLog(
        .warning,
        '心跳失败（第 $_heartbeatFailures 次）：$error',
        tag: 'Multiplayer',
      );
      if (_heartbeatFailures >= 3) {
        addLog(.error, '心跳连续失败，会话多半已被判过期', tag: 'Multiplayer');
      }
    }
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _peerId = null;
    _heartbeatFailures = 0;
  }

  /// 当前心跳绑定的对端
  String? get heartbeatPeerId => _peerId;

  /// 启动本机代理：申请中继凭证 → 隧道认证 → 按角色起桥或代理
  ///
  /// 返回游戏该连的本机地址；房主（owner）不绑端口（6567 是游戏自己的），
  /// 房客（member）绑 `127.0.0.1:6567` 供游戏当服务器地址连
  Future<String> startProxy({
    required String accessToken,
    required String sessionId,
  }) async {
    if (_tunnel != null) return localAddress;
    final tunnel = MdtbbsRelayTunnel(
      allocateRelay: () => MdtbbsMultiplayerApi.allocateRelay(
        accessToken: accessToken,
        sessionId: sessionId,
      ),
    );
    try {
      // 整段兜底超时：任何一步挂住都要变成错误，免得页面按钮永久禁用
      final auth = await tunnel.start().timeout(const Duration(seconds: 30));
      _sessionId = sessionId;
      _peerRole = auth.peerRole;

      if (auth.peerRole == 'owner') {
        final bridge = MdtbbsRelayHostBridge(tunnel: tunnel);
        await bridge.start().timeout(const Duration(seconds: 10));
        _host = bridge;
        _localAddress = '127.0.0.1:6567';
      } else {
        final ports = await bindRelayProxyPorts();
        if (ports == null) {
          await tunnel.dispose();
          throw const MdtbbsRelayException('本机端口 6567 起不来（游戏或别的程序占着？）');
        }
        final peers = await MdtbbsMultiplayerApi.peers(
          accessToken: accessToken,
          sessionId: sessionId,
        ).timeout(const Duration(seconds: 15));
        final owner = peers.where((p) => p.role == 'owner').toList();
        if (owner.isEmpty) {
          await tunnel.dispose();
          throw const MdtbbsRelayException('会话里没有房主对端');
        }
        final proxy = MdtbbsRelayGuestProxy(
          tunnel: tunnel,
          ownerPeerId: owner.first.peerId,
          ports: ports,
        );
        await proxy.start();
        _guest = proxy;
        _localAddress = '127.0.0.1:${ports.port}';
      }
    } on Object {
      await tunnel.dispose();
      rethrow;
    }
    _tunnel = tunnel;
    _signalSubscription = tunnel.signals.listen((signal) {
      if (signal is MdtbbsRelayClosed) {
        addLog(.info, '官方中继已断开：${signal.reason}', tag: 'Multiplayer');
        unawaited(stopProxy());
      }
    });
    addLog(
      .info,
      '官方会话代理已启动：$_localAddress（角色 $_peerRole）',
      tag: 'Multiplayer',
    );
    return _localAddress!;
  }

  Future<void> stopProxy() async {
    stopHeartbeat();
    final guest = _guest;
    final host = _host;
    final tunnel = _tunnel;
    final subscription = _signalSubscription;
    _guest = null;
    _host = null;
    _tunnel = null;
    _signalSubscription = null;
    _localAddress = null;
    _peerRole = null;
    await guest?.dispose();
    await host?.dispose();
    await subscription?.cancel();
    await tunnel?.dispose();
  }
}
