import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_api.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/account/account_store.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_state.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_session_task.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_relay_proxy.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_relay_tunnel.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 官方联机的**唯一状态源**：会话、能力、通道、心跳都由它持有
///
/// 页面只做两件事：订阅 [state] 渲染、调下面的动作。**网络调用一律不写在页面里**
/// —— 状态散在页面里会切页就丢（加入码只从创建响应里给一次，丢了找不回），
/// 也会让每次进页面都得重新拉一遍
class MdtbbsMultiplayerService {
  MdtbbsMultiplayerService._();

  static final MdtbbsMultiplayerService instance = MdtbbsMultiplayerService._();

  final ValueNotifier<MultiplayerState> state = ValueNotifier(
    const MultiplayerState(),
  );

  AccountManager get _accounts => AccountManager.instance;

  MdtbbsRelayTunnel? _tunnel;
  MdtbbsRelayGuestProxy? _guest;
  MdtbbsRelayHostBridge? _host;
  StreamSubscription<MdtbbsRelaySignal>? _signalSubscription;

  /// 会话任务卡片：owner 是任务管理器（页面切走也不失控）
  late final MultiplayerSessionTask _sessionTask = MultiplayerSessionTask(
    onCancel: leave,
  );

  Timer? _heartbeatTimer;
  String? _heartbeatPeerId;
  String? _heartbeatSessionId;
  int _heartbeatFailures = 0;

  /// 拿 BBS 的 Bearer 令牌；未登录返回 null
  Future<String?> _token() => _accounts.ensureAccessToken();

  void _set(MultiplayerState next) {
    state.value = next;
    // 会话在，任务卡片跟着刷新（人数 / 心跳 / 通道状态）
    if (_sessionTask.status == TaskStatus.process) {
      _sessionTask.updateFrom(next);
    }
  }

  /// 开会话时挂上任务卡片；结束（离开 / 被服务端清掉）时收尾
  void _beginSessionTask() {
    _sessionTask.reset();
    addTask(_sessionTask);
  }

  void _finishSessionTask() => _sessionTask.finish();

  MultiplayerState get _current => state.value;

  /// 统一出口：日志 + 右下角通知 + 存进状态（切页回来还看得到）
  void _notify(String text, {bool isError = false}) {
    if (isError) {
      addLogAndPrint(.warning, text, tag: 'Multiplayer');
    } else {
      addLogAndPrint(.info, text, tag: 'Multiplayer');
    }
    addNotice(
      icon: isError ? Icons.error_outline : Icons.check_circle_outline,
      title: isError ? '联机操作失败' : '联机',
      content: text,
      duration: const Duration(seconds: 8),
    );
    _set(_current.copyWith(lastMessage: text, lastMessageIsError: isError));
  }

  void clearMessage() => _set(_current.copyWith(clearMessage: true));

  // ── 能力 ────────────────────────────────────────────────────

  /// 拉一次能力并缓存（[force] 才重新拉）
  Future<void> loadCapabilities({bool force = false}) async {
    if (!force && _current.capabilitiesLoaded) return;
    final token = await _token();
    if (token == null) return;
    _set(_current.copyWith(loadingCapabilities: true));
    try {
      final caps = await MdtbbsMultiplayerApi.capabilities(accessToken: token);
      _set(
        _current.copyWith(
          capabilities: caps,
          capabilitiesLoaded: true,
          loadingCapabilities: false,
        ),
      );
    } on Object catch (error) {
      _set(_current.copyWith(loadingCapabilities: false));
      _notify('读取联机功能状态失败：$error', isError: true);
    }
  }

  // ── 恢复（进页面 / 重启后） ──────────────────────────────────

  /// 先用落盘状态点亮界面，再向服务端核验一次
  ///
  /// 加入码只存在盘上这一份里，所以**必须**先读回来
  Future<void> restore() async {
    if (!_accounts.isConfigured) return;
    // 服务里已经有活着的会话（同一进程内切页回来）就不必重读重拉
    if (_current.session != null) return;
    await _accounts.restore();
    final stored = _accounts.multiplayerSession;
    if (stored == null || !stored.isFresh(DateTime.now())) {
      if (stored != null) {
        addLogAndPrint(.info, '落盘的联机会话太旧，丢弃', tag: 'Multiplayer');
        _accounts.clearMultiplayerSession();
      }
      return;
    }
    // 落盘里记着的会话：先把码与身份摆上，界面立刻有东西看
    _set(_current.copyWith(joinCode: stored.joinCode, resuming: true));
    _heartbeatPeerId = stored.peerId;
    _heartbeatSessionId = stored.sessionId;
    await verifySession();
  }

  /// 向服务端核验当前会话；不在会话里就清掉落盘
  Future<void> verifySession() async {
    final token = await _token();
    if (token == null) {
      _set(_current.copyWith(resuming: false));
      return;
    }
    try {
      final session = await MdtbbsMultiplayerApi.currentSession(
        accessToken: token,
      );
      if (session == null) {
        _accounts.clearMultiplayerSession();
        _finishSessionTask();
        _set(
          _current.copyWith(
            clearSession: true,
            clearJoinCode: true,
            clearSelf: true,
            resuming: false,
          ),
        );
        return;
      }
      _set(_current.copyWith(session: session, resuming: false));
      _beginSessionTask();
      _armHeartbeat();
      await refreshPeers();
    } on Object catch (error) {
      _set(_current.copyWith(resuming: false));
      _notify('读取房间状态失败：$error', isError: true);
    }
  }

  // ── 会话动作 ────────────────────────────────────────────────

  Future<void> create({
    required String activityName,
    required String visibility,
    required String joinPolicy,
    required int maxPlayers,
  }) async {
    if (_current.creating) return;
    if (maxPlayers < 2 || maxPlayers > 64) {
      _notify('人数上限需在 2–64 之间', isError: true);
      return;
    }
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }
    _set(_current.copyWith(creating: true));
    try {
      final created = await MdtbbsMultiplayerApi.createSession(
        accessToken: token,
        gameId: 'mindustry',
        activityName: activityName,
        visibility: visibility,
        joinPolicy: joinPolicy,
        maxPlayers: maxPlayers,
      );
      _rememberSession(
        sessionId: created.session.id,
        peerId: created.peer.peerId,
        resumeToken: created.resumeToken,
        joinCode: created.joinCode,
        activityName: activityName,
      );
      _set(
        _current.copyWith(
          session: created.session,
          self: created.peer,
          joinCode: created.joinCode,
          resuming: false,
          creating: false,
        ),
      );
      _beginSessionTask();
      _notify(
        created.joinCode == null
            ? '房间已创建（${created.session.id}）；这个可见范围不给加入码，只能靠邀请'
            : '房间已创建，加入码 ${created.joinCode}（服务端只给这一次，先记下来）',
      );
      _armHeartbeat();
      unawaited(refreshPeers());
    } on Object catch (error) {
      _set(_current.copyWith(creating: false));
      _notify('创建房间失败：$error', isError: true);
    }
  }

  Future<void> joinByCode(String code) async {
    if (_current.joining) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      _notify('请输入加入码', isError: true);
      return;
    }
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }
    _set(_current.copyWith(joining: true));
    try {
      final session = await MdtbbsMultiplayerApi.resolveCode(
        accessToken: token,
        code: trimmed,
      );
      final joined = await MdtbbsMultiplayerApi.join(
        accessToken: token,
        sessionId: session.id,
        joinCode: trimmed,
      );
      _rememberSession(
        sessionId: session.id,
        peerId: joined.peer.peerId,
        resumeToken: joined.resumeToken,
        joinCode: trimmed,
      );
      _set(
        _current.copyWith(
          session: session,
          self: joined.peer,
          joinCode: trimmed,
          resuming: false,
          joining: false,
        ),
      );
      _beginSessionTask();
      _notify('已加入房间（${session.id}）');
      _armHeartbeat();
      unawaited(refreshPeers());
    } on Object catch (error) {
      _set(_current.copyWith(joining: false));
      _notify('加入房间失败：$error', isError: true);
    }
  }

  Future<void> leave() async {
    final session = _current.session;
    if (session == null) {
      _notify('当前不在任何房间中', isError: true);
      return;
    }
    final token = await _token();
    if (token == null) {
      _notify('登录状态已失效，请到账户页重新登录', isError: true);
      return;
    }
    _set(_current.copyWith(leaving: true));
    try {
      final outcome = await MdtbbsMultiplayerApi.leave(
        accessToken: token,
        sessionId: session.id,
      );
      forgetSession();
      _finishSessionTask();
      await stopProxy();
      _accounts.clearMultiplayerSession();
      _set(
        _current.copyWith(
          clearSession: true,
          clearJoinCode: true,
          clearSelf: true,
          peers: const [],
          leaving: false,
        ),
      );
      _notify(
        outcome.isOwnerLeaving
            ? '已离开房间；你是房主，房间将在 ${outcome.graceSeconds} 秒后关闭'
            : '已离开房间',
      );
    } on Object catch (error) {
      _set(_current.copyWith(leaving: false));
      _notify('离开房间失败：$error', isError: true);
    }
  }

  Future<void> refreshPeers({bool announce = false}) async {
    final session = _current.session;
    if (session == null) return;
    final token = await _token();
    if (token == null) {
      _notify('登录状态已失效，请到账户页重新登录', isError: true);
      return;
    }
    _set(_current.copyWith(refreshingPeers: true));
    try {
      final peers = await MdtbbsMultiplayerApi.peers(
        accessToken: token,
        sessionId: session.id,
      );
      _set(_current.copyWith(peers: peers, refreshingPeers: false));
      if (announce) {
        _notify(peers.isEmpty ? '成员：暂无' : '成员：${peers.length} 人');
      }
    } on Object catch (error) {
      _set(_current.copyWith(refreshingPeers: false));
      _notify('刷新成员失败：$error', isError: true);
    }
  }

  // ── 心跳 ────────────────────────────────────────────────────

  void _armHeartbeat() {
    _heartbeatTimer?.cancel();
    final sessionId = _heartbeatSessionId;
    final peerId = _heartbeatPeerId;
    if (sessionId == null || peerId == null) return;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_beat(sessionId, peerId));
    });
  }

  Future<void> _beat(String sessionId, String peerId) async {
    try {
      final token = await _token();
      if (token == null) {
        addLogAndPrint(.warning, '心跳拿不到访问令牌，跳过这次', tag: 'Multiplayer');
        return;
      }
      final beat = await MdtbbsMultiplayerApi.peerHeartbeat(
        accessToken: token,
        sessionId: sessionId,
        peerId: peerId,
      );
      _heartbeatFailures = 0;
      _set(
        _current.copyWith(
          lastHeartbeatAt: DateTime.now(),
          heartbeatFailures: 0,
        ),
      );
      addLogAndPrint(
        .debug,
        '心跳成功（服务端节奏 ${beat.heartbeatIntervalSeconds}s / 判定 ${beat.expiresInSeconds}s）',
        tag: 'Multiplayer',
      );
    } on Object catch (error) {
      _heartbeatFailures++;
      _set(_current.copyWith(heartbeatFailures: _heartbeatFailures));
      addLogAndPrint(
        .warning,
        '心跳失败（第 $_heartbeatFailures 次）：$error',
        tag: 'Multiplayer',
      );
      if (_heartbeatFailures >= 3) {
        addLogAndPrint(.error, '心跳连续失败，会话多半已被判过期', tag: 'Multiplayer');
      }
    }
  }

  /// 会话结束才彻底忘掉心跳身份
  void forgetSession() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatPeerId = null;
    _heartbeatSessionId = null;
    _heartbeatFailures = 0;
  }

  // ── 联机通道（中继隧道 + 本机桥） ───────────────────────────

  /// 启动通道：申请凭证 → 隧道认证 → 按角色起房主桥或房客代理
  ///
  /// 房主不绑端口（6567 是游戏自己的），房客绑 6567 供游戏当服务器地址连
  Future<void> startProxy() async {
    final session = _current.session;
    if (session == null) {
      _notify('当前不在任何房间中', isError: true);
      return;
    }
    if (_tunnel != null) return;
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }
    _set(_current.copyWith(startingProxy: true));
    final tunnel = MdtbbsRelayTunnel(
      allocateRelay: () => MdtbbsMultiplayerApi.allocateRelay(
        accessToken: token,
        sessionId: session.id,
      ),
    );
    String? address;
    try {
      // 整段兜底超时：任何一步挂住都要变成错误，免得按钮永久禁用
      final auth = await tunnel.start().timeout(const Duration(seconds: 30));
      _heartbeatPeerId = auth.peerId;
      _heartbeatSessionId = session.id;
      _accounts.saveMultiplayerSession(
        StoredMultiplayerSession(
          sessionId: session.id,
          peerId: auth.peerId,
          resumeToken: _accounts.multiplayerSession?.resumeToken,
          joinCode: _current.joinCode,
          activityName: session.activityName,
        ),
      );
      if (auth.peerRole == 'owner') {
        final bridge = MdtbbsRelayHostBridge(tunnel: tunnel);
        await bridge.start().timeout(const Duration(seconds: 10));
        _host = bridge;
        address = '127.0.0.1:6567';
      } else {
        final ports = await bindRelayProxyPorts();
        if (ports == null) {
          throw const MdtbbsRelayException('本机端口 6567 起不来（游戏或别的程序占着？）');
        }
        final peers = await MdtbbsMultiplayerApi.peers(
          accessToken: token,
          sessionId: session.id,
        ).timeout(const Duration(seconds: 15));
        final owner = peers.where((p) => p.role == 'owner').toList();
        if (owner.isEmpty) {
          throw const MdtbbsRelayException('会话里没有房主对端');
        }
        final proxy = MdtbbsRelayGuestProxy(
          tunnel: tunnel,
          ownerPeerId: owner.first.peerId,
          ports: ports,
        );
        await proxy.start();
        _guest = proxy;
        address = '127.0.0.1:${ports.port}';
      }
    } on Object catch (error) {
      await tunnel.dispose();
      _set(_current.copyWith(startingProxy: false));
      _notify('启动联机通道失败：$error', isError: true);
      return;
    }
    _tunnel = tunnel;
    _signalSubscription = tunnel.signals.listen((signal) {
      if (signal is MdtbbsRelayClosed) {
        addLogAndPrint(.info, '官方中继已断开：${signal.reason}', tag: 'Multiplayer');
        unawaited(stopProxy());
      }
    });
    _set(
      _current.copyWith(
        proxyRunning: true,
        localAddress: address,
        startingProxy: false,
      ),
    );
    _notify('联机通道已启动，请在游戏中连接 $address');
  }

  Future<void> stopProxy() async {
    final wasRunning = _tunnel != null;
    final guest = _guest;
    final host = _host;
    final tunnel = _tunnel;
    final subscription = _signalSubscription;
    _guest = null;
    _host = null;
    _tunnel = null;
    _signalSubscription = null;
    await guest?.dispose();
    await host?.dispose();
    await subscription?.cancel();
    await tunnel?.dispose();
    if (_current.proxyRunning) {
      _set(
        _current.copyWith(
          proxyRunning: false,
          clearLocalAddress: true,
          stoppingProxy: false,
        ),
      );
    }
    if (wasRunning) _notify('联机通道已停止');
  }

  // ── 落盘 ────────────────────────────────────────────────────

  void _rememberSession({
    required String sessionId,
    required String peerId,
    required String resumeToken,
    String? joinCode,
    String? activityName,
  }) {
    _heartbeatPeerId = peerId;
    _heartbeatSessionId = sessionId;
    _accounts.saveMultiplayerSession(
      StoredMultiplayerSession(
        sessionId: sessionId,
        peerId: peerId,
        resumeToken: resumeToken,
        joinCode: joinCode,
        activityName: activityName,
      ),
    );
  }
}
