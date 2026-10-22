import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/account/account_store.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_error_text.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_state.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_relay_proxy.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_relay_tunnel.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_session_task.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _StoredPeerAdoption { adopted, absent, unknown }

/// 官方联机的**唯一状态源**：会话、能力、通道、心跳都由它持有。
class MdtbbsMultiplayerService {
  MdtbbsMultiplayerService._() {
    final snapshot = _accounts.snapshot.value;
    _accountLoggedIn = snapshot.loggedIn;
    _lastAccountSubject = snapshot.subject;
    _accounts.snapshot.addListener(_onAccountSnapshotChanged);
  }

  static final MdtbbsMultiplayerService instance = MdtbbsMultiplayerService._();

  final ValueNotifier<MultiplayerState> state = ValueNotifier(
    const MultiplayerState(),
  );

  AccountManager get _accounts => AccountManager.instance;

  MdtbbsRelayTunnel? _tunnel;
  MdtbbsRelayGuestProxy? _guest;
  MdtbbsRelayHostBridge? _host;
  StreamSubscription<MdtbbsRelaySignal>? _signalSubscription;

  late final MultiplayerSessionTask _sessionTask = MultiplayerSessionTask(
    onCancel: leave,
  );

  Timer? _heartbeatTimer;
  String? _heartbeatPeerId;
  String? _heartbeatSessionId;
  int _heartbeatFailures = 0;
  int _heartbeatGeneration = 0;
  int? _heartbeatInFlightGeneration;
  bool _heartbeatRecoveryInFlight = false;

  /// 断线重连：2s / 5s / 10s 三次，成功后清零
  static const _reconnectDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  /// 认证失败 / 额度满之后，等这次分配过期再自动重试
  DateTime? _authBlockedUntil;
  Timer? _authBlockedTimer;

  String? _lastAccountSubject;
  bool _accountLoggedIn = false;
  bool _accountResetInFlight = false;
  int _accountEpoch = 0;
  Timer? _accountResetTimer;

  Future<String?> _token() async =>
      tokenOverride != null ? tokenOverride!() : _accounts.ensureAccessToken();

  @visibleForTesting
  static Future<String?> Function()? tokenOverride;

  MultiplayerState get _current => state.value;

  bool _isAccountEpochCurrent(int epoch) => epoch == _accountEpoch;

  void _set(MultiplayerState next) {
    state.value = next;
    if (_sessionTask.status == TaskStatus.process) {
      _sessionTask.updateFrom(next);
    }
  }

  void _beginSessionTask() {
    _sessionTask.reset();
    addTask(_sessionTask);
  }

  void _finishSessionTask() => _sessionTask.finish();

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

  void _onAccountSnapshotChanged() {
    final snapshot = _accounts.snapshot.value;
    if (!snapshot.loggedIn) {
      if (_accountLoggedIn) _accountEpoch++;
      _accountLoggedIn = false;
      _lastAccountSubject = null;
      if (_hasLiveMultiplayerState) _scheduleAccountReset();
      return;
    }

    _accountResetTimer?.cancel();
    _accountResetTimer = null;
    final subject = snapshot.subject;
    final identityChanged =
        _accountLoggedIn &&
        subject != null &&
        subject.isNotEmpty &&
        _lastAccountSubject != null &&
        _lastAccountSubject != subject;
    if (!_accountLoggedIn || identityChanged) _accountEpoch++;
    _accountLoggedIn = true;

    if (subject != null && subject.isNotEmpty) {
      _lastAccountSubject = subject;
    }
    if (identityChanged && _hasLiveMultiplayerState) {
      addLogAndPrint(
        .warning,
        '账号已切换，结束旧账号的联机会话并停止通道',
        tag: 'Multiplayer',
      );
      unawaited(_resetForAccountChange());
    }
  }

  /// 「未登录」可能只是 `AccountManager.restore()` 清内存后广播的一次中间态
  /// （2026-10-21：云存档在启动游戏前调它，把正在用的房间拆了）
  /// ⇒ 等一下再看一次，确认真的退了才拆
  void _scheduleAccountReset() {
    _accountResetTimer?.cancel();
    _accountResetTimer = Timer(const Duration(milliseconds: 600), () {
      _accountResetTimer = null;
      if (_accounts.snapshot.value.loggedIn) return;
      if (!_hasLiveMultiplayerState) return;
      addLogAndPrint(
        .warning,
        '账号已退出，结束联机会话并停止通道',
        tag: 'Multiplayer',
      );
      unawaited(_resetForAccountChange());
    });
  }

  bool get _hasLiveMultiplayerState =>
      _current.session != null ||
      _tunnel != null ||
      _heartbeatSessionId != null ||
      _current.invites.isNotEmpty ||
      _current.sentInvites.isNotEmpty;

  Future<void> _resetForAccountChange() async {
    if (_accountResetInFlight) return;
    _accountResetInFlight = true;
    try {
      stopInvitePolling();
      forgetSession();
      _finishSessionTask();
      _cancelReconnect(reset: true);
      _cancelAuthBlock();
      // 先同步清掉旧账号的可见状态，再异步释放旧网络资源。
      // 这样新账号即使在 teardown 期间登录并建好状态，也不会被旧 reset 的尾声覆盖。
      _set(const MultiplayerState());
      await stopProxy();
    } finally {
      _accountResetInFlight = false;
    }
  }

  // ── 能力 ────────────────────────────────────────────────────

  Future<void> loadCapabilities({bool force = false}) async {
    if (!force && _current.capabilitiesLoaded) return;
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) return;
    _set(_current.copyWith(loadingCapabilities: true));
    try {
      final caps = await MdtbbsMultiplayerApi.capabilities(accessToken: token);
      if (!_isAccountEpochCurrent(epoch)) return;
      addLog(
        .info,
        '联机能力：visibility=${caps.visibility} joinPolicies=${caps.joinPolicies}',
        tag: 'Multiplayer',
      );
      _set(
        _current.copyWith(
          capabilities: caps,
          capabilitiesLoaded: true,
          loadingCapabilities: false,
        ),
      );
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(loadingCapabilities: false));
      _notify('读取联机功能状态失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  // ── 恢复 ────────────────────────────────────────────────────

  Future<void> restore() async {
    if (!_accounts.isConfigured) return;
    if (_current.session != null) return;
    // restore() 会先清内存、广播一次「未登录」；这里只要读一次盘
    await _accounts.ensureRestored();
    final stored = _accounts.multiplayerSession;
    if (stored == null || !stored.isFresh(DateTime.now())) {
      if (stored != null) {
        addLogAndPrint(.info, '落盘的联机会话太旧，丢弃', tag: 'Multiplayer');
        _accounts.clearMultiplayerSession();
      }
      return;
    }
    _set(_current.copyWith(joinCode: stored.joinCode, resuming: true));
    await _restoreStoredSession(stored);
  }

  Future<void> _restoreStoredSession(StoredMultiplayerSession stored) async {
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) {
      if (_isAccountEpochCurrent(epoch)) {
        _set(_current.copyWith(resuming: false));
      }
      return;
    }

    final resumeToken = stored.resumeToken;
    if (resumeToken != null && resumeToken.isNotEmpty) {
      try {
        final joined = await MdtbbsMultiplayerApi.join(
          accessToken: token,
          sessionId: stored.sessionId,
          resumeToken: resumeToken,
        );
        if (!_isAccountEpochCurrent(epoch)) return;
        if (!joined.resumed) {
          throw const MdtbbsException(
            code: 'PEER_RESUME_INVALID',
            message: '服务端没有确认恢复原对端',
          );
        }
        final session = await MdtbbsMultiplayerApi.session(
          accessToken: token,
          sessionId: stored.sessionId,
        );
        if (!_isAccountEpochCurrent(epoch)) return;
        _rememberSession(
          sessionId: session.id,
          peerId: joined.peer.peerId,
          resumeToken: joined.resumeToken,
          joinCode: stored.joinCode,
          activityName: session.activityName ?? stored.activityName,
        );
        _set(
          _current.copyWith(
            session: session,
            self: joined.peer,
            joinCode: stored.joinCode,
            resuming: false,
            heartbeatFailures: 0,
          ),
        );
        _beginSessionTask();
        _armHeartbeat();
        await refreshPeers();
        unawaited(_autoPrepareProxy());
        addLogAndPrint(.info, '已用恢复令牌恢复联机会话 ${session.id}', tag: 'Multiplayer');
        return;
      } on MdtbbsException catch (error) {
        if (!_isAccountEpochCurrent(epoch)) return;
        if (!_isTerminalResumeError(error.code)) {
          _set(_current.copyWith(resuming: false));
          _notify('恢复联机会话失败：${describeMdtbbsError(error)}', isError: true);
          return;
        }
        if (error.code == 'PEER_RESUME_INVALID') {
          _saveSessionWithoutResumeToken(stored);
          final adoption = await _adoptStillActiveStoredPeer(
            stored,
            token,
            expectedAccountEpoch: epoch,
          );
          if (!_isAccountEpochCurrent(epoch)) return;
          if (adoption == _StoredPeerAdoption.adopted) return;
          if (adoption == _StoredPeerAdoption.unknown) {
            _set(_current.copyWith(resuming: false));
            _notify('恢复令牌已失效，但当前房间状态暂时无法核验；已保留本地会话', isError: true);
            return;
          }
        }
        await _clearStoredSessionAfterServerRejection(
          expectedAccountEpoch: epoch,
        );
        return;
      } on Object catch (error) {
        if (!_isAccountEpochCurrent(epoch)) return;
        _set(_current.copyWith(resuming: false));
        _notify('恢复联机会话失败：$error', isError: true);
        return;
      }
    }

    final adoption = await _adoptStillActiveStoredPeer(
      stored,
      token,
      expectedAccountEpoch: epoch,
    );
    if (!_isAccountEpochCurrent(epoch)) return;
    if (adoption == _StoredPeerAdoption.adopted) return;
    if (adoption == _StoredPeerAdoption.unknown) {
      _set(_current.copyWith(resuming: false));
      return;
    }
    await _clearStoredSessionAfterServerRejection(expectedAccountEpoch: epoch);
  }

  bool _isTerminalResumeError(String? code) =>
      code == 'PEER_RESUME_INVALID' ||
      code == 'SESSION_NOT_FOUND' ||
      code == 'SESSION_CLOSED' ||
      code == 'PEER_EXPIRED';

  bool _isConfirmedAbsentPeerError(String? code) =>
      code == 'SESSION_NOT_FOUND' ||
      code == 'SESSION_CLOSED' ||
      code == 'PEER_EXPIRED' ||
      code == 'PEER_NOT_FOUND';

  Future<_StoredPeerAdoption> _adoptStillActiveStoredPeer(
    StoredMultiplayerSession stored,
    String token, {
    required int expectedAccountEpoch,
    bool beginSessionTask = true,
  }) async {
    final peerId = stored.peerId;
    if (peerId == null || peerId.isEmpty) return _StoredPeerAdoption.absent;
    try {
      final session = await MdtbbsMultiplayerApi.currentSession(
        accessToken: token,
      );
      if (!_isAccountEpochCurrent(expectedAccountEpoch)) {
        return _StoredPeerAdoption.unknown;
      }
      if (session == null || session.id != stored.sessionId) {
        return _StoredPeerAdoption.absent;
      }
      final peers = await MdtbbsMultiplayerApi.peers(
        accessToken: token,
        sessionId: session.id,
      );
      if (!_isAccountEpochCurrent(expectedAccountEpoch)) {
        return _StoredPeerAdoption.unknown;
      }
      MdtbbsPeer? self;
      for (final peer in peers) {
        if (peer.peerId == peerId && peer.status == 'active') {
          self = peer;
          break;
        }
      }
      if (self == null) return _StoredPeerAdoption.absent;

      _heartbeatPeerId = self.peerId;
      _heartbeatSessionId = session.id;
      _heartbeatFailures = 0;
      _accounts.saveMultiplayerSession(
        StoredMultiplayerSession(
          sessionId: session.id,
          peerId: self.peerId,
          resumeToken: null,
          joinCode: stored.joinCode,
          activityName: session.activityName ?? stored.activityName,
        ),
      );
      _set(
        _current.copyWith(
          session: session,
          self: self,
          joinCode: stored.joinCode,
          peers: peers,
          resuming: false,
          heartbeatFailures: 0,
        ),
      );
      if (beginSessionTask) _beginSessionTask();
      _armHeartbeat();
      unawaited(_autoPrepareProxy());
      addLogAndPrint(
        .warning,
        '恢复令牌不可用，但服务端仍确认旧 peer 活跃；本次进程继续使用该 peer',
        tag: 'Multiplayer',
      );
      return _StoredPeerAdoption.adopted;
    } on MdtbbsException catch (error) {
      if (_isConfirmedAbsentPeerError(error.code)) {
        return _StoredPeerAdoption.absent;
      }
      return _StoredPeerAdoption.unknown;
    } on Object {
      return _StoredPeerAdoption.unknown;
    }
  }

  void _saveSessionWithoutResumeToken(StoredMultiplayerSession stored) {
    _accounts.saveMultiplayerSession(
      StoredMultiplayerSession(
        sessionId: stored.sessionId,
        peerId: stored.peerId,
        resumeToken: null,
        joinCode: stored.joinCode,
        activityName: stored.activityName,
      ),
    );
  }

  Future<void> _clearStoredSessionAfterServerRejection({
    required int expectedAccountEpoch,
  }) async {
    if (!_isAccountEpochCurrent(expectedAccountEpoch)) return;
    forgetSession();
    _finishSessionTask();
    _cancelReconnect(reset: true);
    _cancelAuthBlock();
    await stopProxy();
    if (!_isAccountEpochCurrent(expectedAccountEpoch)) return;
    _accounts.clearMultiplayerSession();
    _set(
      _current.copyWith(
        clearSession: true,
        clearJoinCode: true,
        clearSelf: true,
        peers: const [],
        resuming: false,
        startingProxy: false,
        stoppingProxy: false,
        reconnecting: false,
        reconnectAttempt: 0,
        clearProxyError: true,
        clearProxyRetryAt: true,
        clearSentInvites: true,
      ),
    );
  }

  Future<void> verifySession() async {
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) {
      if (_isAccountEpochCurrent(epoch)) {
        _set(_current.copyWith(resuming: false));
      }
      return;
    }
    try {
      final session = await MdtbbsMultiplayerApi.currentSession(
        accessToken: token,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
      if (session == null) {
        await _clearStoredSessionAfterServerRejection(
          expectedAccountEpoch: epoch,
        );
        return;
      }
      final peers = await MdtbbsMultiplayerApi.peers(
        accessToken: token,
        sessionId: session.id,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
      final peerId = _heartbeatPeerId ?? _accounts.multiplayerSession?.peerId;
      MdtbbsPeer? self;
      if (peerId != null) {
        for (final peer in peers) {
          if (peer.peerId == peerId) {
            self = peer;
            break;
          }
        }
      }
      _set(
        _current.copyWith(
          session: session,
          self: self,
          clearSelf: self == null,
          peers: peers,
          resuming: false,
        ),
      );
      _beginSessionTask();
      _armHeartbeat();
      unawaited(_autoPrepareProxy());
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(resuming: false));
      _notify('读取房间状态失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  // ── 会话动作 ────────────────────────────────────────────────

  Future<void> create({
    required String activityName,
    required String visibility,
    required String joinPolicy,
    bool requireApproval = false,
    required int maxPlayers,
  }) async {
    if (_current.creating) return;
    if (maxPlayers < 2 || maxPlayers > 64) {
      _notify('人数上限需在 2–64 之间', isError: true);
      return;
    }
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) {
      if (_isAccountEpochCurrent(epoch)) _notify('请先登录社区账号', isError: true);
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
        requireApproval: requireApproval,
        maxPlayers: maxPlayers,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
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
      final joinCode = created.joinCode;
      if (joinCode != null) {
        try {
          await Clipboard.setData(ClipboardData(text: joinCode));
        } on Object {
          // 剪贴板不可用不影响建房
        }
      }
      if (!_isAccountEpochCurrent(epoch)) return;
      _notify(
        joinCode == null
            ? '房间已创建（${created.session.id}）；这个可见范围不给房间码，只能靠邀请'
            : '房间已创建，房间码 $joinCode（已复制到剪贴板）',
      );
      _armHeartbeat();
      unawaited(refreshPeers());
      unawaited(_autoPrepareProxy());
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(creating: false));
      _notify('创建房间失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  Future<void> joinByCode(String code) async {
    if (_current.joining) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      _notify('请输入房间码', isError: true);
      return;
    }
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) {
      if (_isAccountEpochCurrent(epoch)) _notify('请先登录社区账号', isError: true);
      return;
    }
    _set(_current.copyWith(joining: true));
    try {
      final session = await MdtbbsMultiplayerApi.resolveCode(
        accessToken: token,
        code: trimmed,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
      final joined = await MdtbbsMultiplayerApi.join(
        accessToken: token,
        sessionId: session.id,
        joinCode: trimmed,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
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
      unawaited(_autoPrepareProxy());
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(joining: false));
      _notify('加入房间失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  Future<void> leave() async {
    final session = _current.session;
    if (session == null) {
      _notify('当前不在任何房间中', isError: true);
      return;
    }
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) {
      if (_isAccountEpochCurrent(epoch)) {
        _notify('登录状态已失效，请到账户页重新登录', isError: true);
      }
      return;
    }
    _set(_current.copyWith(leaving: true));
    try {
      final outcome = await MdtbbsMultiplayerApi.leave(
        accessToken: token,
        sessionId: session.id,
      );
      await _finishLeaveLocally(epoch);
      if (!_isAccountEpochCurrent(epoch)) return;
      _notify(
        outcome.isOwnerLeaving
            ? '已离开房间；你是房主，房间将在 ${outcome.graceSeconds} 秒后关闭'
            : '已离开房间',
      );
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      // 房主先走了 / 会话已过期：服务端已经没这个房间了，本地照常收尾
      if (_isSessionAlreadyGone(error)) {
        await _finishLeaveLocally(epoch);
        if (!_isAccountEpochCurrent(epoch)) return;
        _notify('房间已经关闭，已退出');
        return;
      }
      _set(_current.copyWith(leaving: false));
      _notify('离开房间失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  bool _isSessionAlreadyGone(Object error) {
    if (error is! MdtbbsException) return false;
    return const {
      'SESSION_CLOSED',
      'SESSION_NOT_FOUND',
      'SESSION_EXPIRED',
    }.contains(error.code);
  }

  /// 离开 / 房间已不存在后的本地收尾；调用方负责提示
  Future<void> _finishLeaveLocally(int epoch) async {
    forgetSession();
    _finishSessionTask();
    _cancelReconnect(reset: true);
    _cancelAuthBlock();
    await stopProxy();
    if (!_isAccountEpochCurrent(epoch)) return;
    _accounts.clearMultiplayerSession();
    _set(
      _current.copyWith(
        clearSession: true,
        clearJoinCode: true,
        clearSelf: true,
        peers: const [],
        leaving: false,
        startingProxy: false,
        stoppingProxy: false,
        reconnecting: false,
        reconnectAttempt: 0,
        clearProxyError: true,
        clearProxyRetryAt: true,
        clearSentInvites: true,
      ),
    );
  }

  Future<void> refreshPeers({bool announce = false}) async {
    final session = _current.session;
    if (session == null) return;
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) {
      if (announce && _isAccountEpochCurrent(epoch)) {
        _notify('登录状态已失效，请到账户页重新登录', isError: true);
      }
      return;
    }
    _set(_current.copyWith(refreshingPeers: true));
    try {
      final peers = await MdtbbsMultiplayerApi.peers(
        accessToken: token,
        sessionId: session.id,
      );
      if (!_isAccountEpochCurrent(epoch) ||
          _current.session?.id != session.id) {
        return;
      }
      _set(_current.copyWith(peers: peers, refreshingPeers: false));
      if (announce) {
        _notify(peers.isEmpty ? '成员：暂无' : '成员：${peers.length} 人');
      }
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch) ||
          _current.session?.id != session.id) {
        return;
      }
      _set(_current.copyWith(refreshingPeers: false));
      if (announce) _notify('刷新成员失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  // ── 邀请 ────────────────────────────────────────────────────

  Timer? _inviteTimer;

  void startInvitePolling({Duration interval = const Duration(seconds: 20)}) {
    stopInvitePolling();
    _inviteTimer = Timer.periodic(interval, (_) {
      unawaited(refreshInvites());
    });
  }

  void stopInvitePolling() {
    _inviteTimer?.cancel();
    _inviteTimer = null;
  }

  Future<void> refreshInvites({bool announce = false}) async {
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) return;
    _set(_current.copyWith(loadingInvites: true));
    try {
      final invites = await MdtbbsMultiplayerApi.invites(accessToken: token);
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(invites: invites, loadingInvites: false));
      if (announce) {
        _notify(invites.isEmpty ? '没有待处理的邀请' : '待处理邀请 ${invites.length} 条');
      }
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(loadingInvites: false));
      if (announce) {
        _notify('读取邀请失败：${describeMdtbbsError(error)}', isError: true);
      } else {
        addLogAndPrint(
          .debug,
          '读取邀请失败（轮询）：${describeMdtbbsError(error)}',
          tag: 'Multiplayer',
        );
      }
    }
  }

  Future<void> inviteFriend(int targetUserId) async {
    final session = _current.session;
    if (session == null) {
      _notify('先创建或加入一个房间，再邀请好友', isError: true);
      return;
    }
    if (targetUserId <= 0) {
      _notify('用户 ID 不对', isError: true);
      return;
    }
    if (_current.inviting) return;
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) return;
    _set(_current.copyWith(inviting: true));
    try {
      final invite = await MdtbbsMultiplayerApi.createInvite(
        accessToken: token,
        sessionId: session.id,
        targetUserId: targetUserId,
      );
      if (!_isAccountEpochCurrent(epoch) ||
          _current.session?.id != session.id) {
        return;
      }
      _set(
        _current.copyWith(
          sentInvites: [
            invite,
            for (final sent in _current.sentInvites)
              if (sent.inviteId != invite.inviteId) sent,
          ],
          inviting: false,
        ),
      );
      _notify('已邀请用户 $targetUserId（邀请 5 分钟内有效）');
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(inviting: false));
      _notify('邀请失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  Future<void> revokeInvite(String inviteId) =>
      _respondInvite(inviteId, revoke: true);

  Future<void> declineInvite(String inviteId) =>
      _respondInvite(inviteId, revoke: false);

  Future<void> _respondInvite(String inviteId, {required bool revoke}) async {
    if (inviteId.isEmpty) {
      _notify('这条邀请没有 ID，无法处理', isError: true);
      return;
    }
    if (_current.busyInviteId != null) return;
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) return;
    _set(_current.copyWith(busyInviteId: inviteId));
    try {
      await MdtbbsMultiplayerApi.respondInvite(
        accessToken: token,
        inviteId: inviteId,
        revoke: revoke,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(
        _current.copyWith(
          clearBusyInvite: true,
          invites: revoke ? _current.invites : _withoutInvite(inviteId),
          sentInvites: revoke
              ? _withoutSentInvite(inviteId)
              : _current.sentInvites,
        ),
      );
      _notify(revoke ? '已撤销邀请' : '已拒绝邀请');
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(clearBusyInvite: true));
      _notify(
        '${revoke ? '撤销' : '拒绝'}邀请失败：${describeMdtbbsError(error)}',
        isError: true,
      );
    }
  }

  Future<void> acceptInvite(String inviteId) async {
    final invite = _inviteOf(inviteId);
    if (invite == null) {
      _notify('这条邀请已经不在了', isError: true);
      return;
    }
    if (_current.session != null) {
      _notify('已经在房间里了，先离开再接受邀请', isError: true);
      return;
    }
    if (_current.busyInviteId != null) return;
    final epoch = _accountEpoch;
    final token = await _token();
    if (token == null || !_isAccountEpochCurrent(epoch)) return;
    _set(_current.copyWith(busyInviteId: inviteId));
    try {
      final intent = await MdtbbsMultiplayerApi.acceptInvite(
        accessToken: token,
        inviteId: inviteId,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
      final joined = await MdtbbsMultiplayerApi.consumeJoinIntent(
        accessToken: token,
        intentId: intent.intentId,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
      final session = await MdtbbsMultiplayerApi.session(
        accessToken: token,
        sessionId: invite.sessionId,
      );
      if (!_isAccountEpochCurrent(epoch)) return;
      _rememberSession(
        sessionId: session.id,
        peerId: joined.peer.peerId,
        resumeToken: joined.resumeToken,
        activityName: session.activityName,
      );
      _set(
        _current.copyWith(
          session: session,
          self: joined.peer,
          resuming: false,
          clearJoinCode: true,
          clearBusyInvite: true,
          invites: _withoutInvite(inviteId),
        ),
      );
      _beginSessionTask();
      _notify('已接受邀请，进入房间（${session.id}）');
      _armHeartbeat();
      unawaited(refreshPeers());
      unawaited(_autoPrepareProxy());
    } on Object catch (error) {
      if (!_isAccountEpochCurrent(epoch)) return;
      _set(_current.copyWith(clearBusyInvite: true));
      _notify('接受邀请失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  MdtbbsInvite? _inviteOf(String inviteId) {
    for (final invite in _current.invites) {
      if (invite.inviteId == inviteId) return invite;
    }
    return null;
  }

  List<MdtbbsInvite> _withoutInvite(String inviteId) => [
    for (final invite in _current.invites)
      if (invite.inviteId != inviteId) invite,
  ];

  List<MdtbbsInvite> _withoutSentInvite(String inviteId) => [
    for (final invite in _current.sentInvites)
      if (invite.inviteId != inviteId) invite,
  ];

  // ── 心跳 ────────────────────────────────────────────────────

  void _armHeartbeat() {
    _heartbeatTimer?.cancel();
    final sessionId = _heartbeatSessionId;
    final peerId = _heartbeatPeerId;
    if (sessionId == null || peerId == null) return;
    final generation = ++_heartbeatGeneration;
    // 先立刻打一次：服务端把「没心跳过的 Peer」当中继上不可达，
    // 房主第一次往房客发 UDP 会拿到 PEER_UNAVAILABLE（10-22 实测）
    unawaited(_beat(sessionId, peerId, generation));
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_heartbeatInFlightGeneration == generation) return;
      unawaited(_beat(sessionId, peerId, generation));
    });
  }

  bool _isCurrentHeartbeat(String sessionId, String peerId, int generation) =>
      generation == _heartbeatGeneration &&
      _heartbeatSessionId == sessionId &&
      _heartbeatPeerId == peerId;

  Future<void> _beat(String sessionId, String peerId, int generation) async {
    if (!_isCurrentHeartbeat(sessionId, peerId, generation) ||
        _heartbeatInFlightGeneration == generation) {
      return;
    }
    _heartbeatInFlightGeneration = generation;
    try {
      final token = await _token();
      if (token == null ||
          !_isCurrentHeartbeat(sessionId, peerId, generation)) {
        return;
      }
      final beat = await MdtbbsMultiplayerApi.peerHeartbeat(
        accessToken: token,
        sessionId: sessionId,
        peerId: peerId,
      );
      if (!_isCurrentHeartbeat(sessionId, peerId, generation)) return;
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
      if (!_isCurrentHeartbeat(sessionId, peerId, generation)) return;
      _heartbeatFailures++;
      _set(_current.copyWith(heartbeatFailures: _heartbeatFailures));
      addLogAndPrint(
        .warning,
        '心跳失败（第 $_heartbeatFailures 次）：$error',
        tag: 'Multiplayer',
      );
      if (_heartbeatFailures >= 3 && !_heartbeatRecoveryInFlight) {
        unawaited(_recoverHeartbeatSession(sessionId, peerId, generation));
      }
    } finally {
      if (_heartbeatInFlightGeneration == generation) {
        _heartbeatInFlightGeneration = null;
      }
    }
  }

  Future<void> _recoverHeartbeatSession(
    String sessionId,
    String peerId,
    int generation,
  ) async {
    if (_heartbeatRecoveryInFlight ||
        !_isCurrentHeartbeat(sessionId, peerId, generation)) {
      return;
    }
    _heartbeatRecoveryInFlight = true;
    final epoch = _accountEpoch;
    try {
      final stored = _accounts.multiplayerSession;
      final token = await _token();
      if (!_isAccountEpochCurrent(epoch) ||
          !_isCurrentHeartbeat(sessionId, peerId, generation) ||
          stored == null ||
          stored.sessionId != sessionId ||
          token == null) {
        return;
      }

      final resumeToken = stored.resumeToken;
      if (resumeToken != null && resumeToken.isNotEmpty) {
        try {
          final joined = await MdtbbsMultiplayerApi.join(
            accessToken: token,
            sessionId: sessionId,
            resumeToken: resumeToken,
          );
          if (!_isAccountEpochCurrent(epoch) ||
              !_isCurrentHeartbeat(sessionId, peerId, generation)) {
            return;
          }
          if (joined.resumed) {
            final session = await MdtbbsMultiplayerApi.session(
              accessToken: token,
              sessionId: sessionId,
            );
            if (!_isAccountEpochCurrent(epoch) ||
                !_isCurrentHeartbeat(sessionId, peerId, generation)) {
              return;
            }
            _rememberSession(
              sessionId: session.id,
              peerId: joined.peer.peerId,
              resumeToken: joined.resumeToken,
              joinCode: stored.joinCode,
              activityName: session.activityName ?? stored.activityName,
            );
            _heartbeatFailures = 0;
            _set(
              _current.copyWith(
                session: session,
                self: joined.peer,
                heartbeatFailures: 0,
              ),
            );
            _armHeartbeat();
            unawaited(refreshPeers());
            unawaited(_autoPrepareProxy());
            addLogAndPrint(.info, '心跳异常后已恢复原联机 peer', tag: 'Multiplayer');
            return;
          }
        } on MdtbbsException catch (error) {
          if (!_isAccountEpochCurrent(epoch) ||
              !_isCurrentHeartbeat(sessionId, peerId, generation)) {
            return;
          }
          if (!_isTerminalResumeError(error.code)) {
            addLogAndPrint(
              .warning,
              '心跳恢复请求失败，保留会话等待下一轮：${describeMdtbbsError(error)}',
              tag: 'Multiplayer',
            );
            return;
          }
          if (error.code == 'PEER_RESUME_INVALID') {
            _saveSessionWithoutResumeToken(stored);
          }
        } on Object catch (error) {
          addLogAndPrint(
            .warning,
            '心跳恢复请求失败，保留会话等待下一轮：$error',
            tag: 'Multiplayer',
          );
          return;
        }
      }

      final adoption = await _adoptStillActiveStoredPeer(
        stored,
        token,
        expectedAccountEpoch: epoch,
        beginSessionTask: false,
      );
      if (!_isAccountEpochCurrent(epoch) ||
          !_isCurrentHeartbeat(sessionId, peerId, generation)) {
        return;
      }
      if (adoption == _StoredPeerAdoption.adopted) return;
      if (adoption == _StoredPeerAdoption.unknown) {
        addLogAndPrint(
          .warning,
          '心跳恢复后仍无法确认服务端状态，保留本地会话等待下一轮',
          tag: 'Multiplayer',
        );
        return;
      }

      addLogAndPrint(.error, '心跳连续失败且服务端确认原 peer 已失效', tag: 'Multiplayer');
      await _clearStoredSessionAfterServerRejection(
        expectedAccountEpoch: epoch,
      );
    } finally {
      _heartbeatRecoveryInFlight = false;
    }
  }

  void forgetSession() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatGeneration++;
    _heartbeatInFlightGeneration = null;
    _heartbeatRecoveryInFlight = false;
    _heartbeatPeerId = null;
    _heartbeatSessionId = null;
    _heartbeatFailures = 0;
  }

  // ── 联机通道 ────────────────────────────────────────────────

  /// 建房 / 加房 / 恢复后自动准备，玩家不再自己点「启动通道」
  Future<void> _autoPrepareProxy() async {
    if (_current.session == null ||
        _tunnel != null ||
        _current.startingProxy) {
      return;
    }
    final caps = _current.capabilities;
    if (caps != null && !caps.relayEnabled) return;
    await _startProxy(auto: true);
  }

  /// 自动重连都失败后，界面上的「重试」
  Future<void> retryProxy() async {
    final blocked = _authBlockedUntil;
    if (blocked != null && blocked.isAfter(DateTime.now())) {
      final seconds = blocked.difference(DateTime.now()).inSeconds;
      _notify('联机服务器刚拒绝过，等约 $seconds 秒再试', isError: true);
      return;
    }
    _cancelAuthBlock();
    _cancelReconnect(reset: true);
    _set(
      _current.copyWith(
        reconnecting: false,
        reconnectAttempt: 0,
        clearProxyError: true,
        clearProxyRetryAt: true,
      ),
    );
    await _startProxy(auto: false);
  }

  Future<void> _startProxy({required bool auto}) async {
    final session = _current.session;
    if (session == null) {
      if (!auto) _notify('当前不在任何房间中', isError: true);
      return;
    }
    if (_tunnel != null || _current.startingProxy) return;

    final epoch = _accountEpoch;
    String? cachedToken = await _token();
    if (cachedToken == null || !_isAccountEpochCurrent(epoch)) {
      if (!auto && _isAccountEpochCurrent(epoch)) {
        _notify('请先登录社区账号', isError: true);
      }
      return;
    }

    _set(
      _current.copyWith(
        startingProxy: true,
        clearProxyError: true,
        clearProxyRetryAt: true,
      ),
    );

    MdtbbsRelayTunnel? tunnel;
    MdtbbsRelayAuthOk? auth;
    try {
      final created = MdtbbsRelayTunnel(
        allocateRelay: () async {
          if (!_isAccountEpochCurrent(epoch)) {
            throw const MdtbbsRelayException('账号已切换，中止旧会话的中继续签');
          }
          final accessToken = cachedToken ?? await _token();
          cachedToken = null;
          if (accessToken == null || !_isAccountEpochCurrent(epoch)) {
            throw const MdtbbsRelayException('登录状态已失效，无法续签中继凭证');
          }
          return MdtbbsMultiplayerApi.allocateRelay(
            accessToken: accessToken,
            sessionId: session.id,
          );
        },
      );
      tunnel = created;
      auth = await created.start().timeout(const Duration(seconds: 30));

      final openedTunnel = tunnel;
      final openedAuth = auth;
      if (!_isAccountEpochCurrent(epoch) ||
          _current.session?.id != session.id) {
        _set(_current.copyWith(startingProxy: false));
        await openedTunnel.dispose();
        return;
      }
      _heartbeatPeerId = openedAuth.peerId;
      _heartbeatSessionId = session.id;
      _accounts.saveMultiplayerSession(
        StoredMultiplayerSession(
          sessionId: session.id,
          peerId: openedAuth.peerId,
          resumeToken: _accounts.multiplayerSession?.resumeToken,
          joinCode: _current.joinCode,
          activityName: session.activityName,
        ),
      );

      String? address;
      MdtbbsRelayProxyPorts? unownedPorts;
      try {
        if (openedAuth.peerRole == 'owner') {
          final bridge = MdtbbsRelayHostBridge(tunnel: openedTunnel);
          await bridge.start().timeout(const Duration(seconds: 10));
          if (!_isAccountEpochCurrent(epoch) ||
              _current.session?.id != session.id) {
            await bridge.dispose();
            await openedTunnel.dispose();
            return;
          }
          _host = bridge;
          address = '127.0.0.1:6567';
        } else {
          final ports = await bindRelayProxyPorts();
          if (ports == null) {
            throw const MdtbbsRelayException('本机端口 6567 起不来（游戏或别的程序占着？）');
          }
          unownedPorts = ports;
          final peersToken = await _token();
          if (peersToken == null || !_isAccountEpochCurrent(epoch)) {
            throw const MdtbbsRelayException('登录状态已失效，无法读取房间成员');
          }
          final peers = await MdtbbsMultiplayerApi.peers(
            accessToken: peersToken,
            sessionId: session.id,
          ).timeout(const Duration(seconds: 15));
          if (!_isAccountEpochCurrent(epoch) ||
              _current.session?.id != session.id) {
            throw const MdtbbsRelayException('会话或账号已经切换');
          }
          final owner = peers.where((p) => p.role == 'owner').toList();
          if (owner.isEmpty) {
            throw const MdtbbsRelayException('会话里没有房主对端');
          }
          final proxy = MdtbbsRelayGuestProxy(
            tunnel: openedTunnel,
            ownerPeerId: owner.first.peerId,
            ports: ports,
            roomName: session.activityName ?? 'Copper 联机房间',
            maxPlayers: session.maxPlayers,
            players: _current.onlinePeerCount > 0
                ? _current.onlinePeerCount
                : 1,
          );
          await proxy.start();
          _guest = proxy;
          unownedPorts = null;
          address = '127.0.0.1:${ports.port}';
        }
      } on Object {
        await _closeProxyPorts(unownedPorts);
        await openedTunnel.dispose();
        rethrow;
      }

      if (!_isAccountEpochCurrent(epoch) ||
          _current.session?.id != session.id) {
        _set(_current.copyWith(startingProxy: false));
        await _closeGuestAndHost();
        await openedTunnel.dispose();
        return;
      }
      _tunnel = openedTunnel;
      _signalSubscription = openedTunnel.signals.listen((signal) {
        if (signal is MdtbbsRelayClosed) {
          addLogAndPrint(
            .warning,
            '联机服务器连接断开：${signal.reason}',
            tag: 'Multiplayer',
          );
          // 旧 tunnel 的 closed 事件如果在 teardown 期间晚到，不能去停掉新 tunnel
          if (identical(_tunnel, openedTunnel)) {
            unawaited(_onRelayLost(openedTunnel));
          }
        }
      });
      _cancelReconnect();
      _reconnectAttempt = 0;
      _cancelAuthBlock();
      _set(
        _current.copyWith(
          proxyRunning: true,
          localAddress: address,
          startingProxy: false,
          reconnecting: false,
          reconnectAttempt: 0,
          clearProxyError: true,
          clearProxyRetryAt: true,
        ),
      );
      if (!auto) _notify('已连上联机服务器');
      unawaited(refreshPeers());
    } on Object catch (error) {
      await tunnel?.dispose();
      if (!_isAccountEpochCurrent(epoch) ||
          _current.session?.id != session.id) {
        _set(_current.copyWith(startingProxy: false));
        return;
      }
      await _onProxyStartFailed(error, auto: auto);
    }
  }

  Future<void> _onRelayLost(MdtbbsRelayTunnel tunnel) async {
    if (!identical(_tunnel, tunnel)) return;
    await stopProxy();
    if (_current.session == null || _current.leaving) return;
    _scheduleReconnect();
  }

  Future<void> _onProxyStartFailed(Object error, {required bool auto}) async {
    addLogAndPrint(.warning, '联机准备失败：$error', tag: 'Multiplayer');

    // 认证失败 / 额度满：服务端会把这次分配挂 120 秒，立刻再申请只会 429
    // ⇒ 等它过期再自动试一次，别把客户端自己锁死
    if (_isRelayAuthRejected(error) || _isRelayLimitReached(error)) {
      _blockUntilAllocationExpires(
        authRejected: _isRelayAuthRejected(error),
      );
      return;
    }

    final message = _describeProxyError(error);
    final retryExhausted =
        !auto || _reconnectAttempt >= _reconnectDelays.length;
    if (retryExhausted) {
      _set(
        _current.copyWith(
          startingProxy: false,
          reconnecting: false,
          proxyError: message,
          clearProxyRetryAt: true,
        ),
      );
      _notify(
        auto ? '$message（已自动重试 ${_reconnectDelays.length} 次）' : message,
        isError: true,
      );
      return;
    }
    _scheduleReconnect();
  }

  bool _isRelayAuthRejected(Object error) =>
      error is MdtbbsRelayException && error.authRejected;

  bool _isRelayLimitReached(Object error) =>
      '$error'.contains('RELAY_LIMIT_REACHED');

  void _blockUntilAllocationExpires({required bool authRejected}) {
    const wait = Duration(seconds: 125);
    _cancelReconnect(reset: true);
    _authBlockedTimer?.cancel();
    _authBlockedUntil = DateTime.now().add(wait);
    final owner = _current.self?.role == 'owner';
    final hint = owner
        ? '；也可以关闭房间后重新创建（换新房间码）'
        : '；也可以退出房间重新加入';
    final message = authRejected
        ? '联机服务器没通过这次连接（服务端问题）$hint'
        : '联机服务器上还有这个房间的旧连接$hint';
    _set(
      _current.copyWith(
        startingProxy: false,
        reconnecting: false,
        proxyError: message,
        proxyRetryAt: _authBlockedUntil,
      ),
    );
    addLogAndPrint(.warning, '等这次中继分配过期后再试：$message', tag: 'Multiplayer');
    _authBlockedTimer = Timer(wait, () {
      _authBlockedTimer = null;
      _authBlockedUntil = null;
      if (_current.session == null) return;
      _set(_current.copyWith(clearProxyRetryAt: true));
      unawaited(_startProxy(auto: true));
    });
  }

  void _cancelAuthBlock() {
    _authBlockedTimer?.cancel();
    _authBlockedTimer = null;
    _authBlockedUntil = null;
  }

  void _scheduleReconnect() {
    final session = _current.session;
    if (session == null || _current.leaving) return;
    _reconnectAttempt++;
    final delay = _reconnectDelays[_reconnectAttempt - 1];
    _reconnectTimer?.cancel();
    _set(
      _current.copyWith(
        startingProxy: false,
        reconnecting: true,
        reconnectAttempt: _reconnectAttempt,
        proxyRetryAt: DateTime.now().add(delay),
      ),
    );
    addLogAndPrint(
      .info,
      '${delay.inSeconds} 秒后重连联机服务器（第 $_reconnectAttempt 次）',
      tag: 'Multiplayer',
    );
    _reconnectTimer = Timer(delay, () {
      if (_current.session?.id != session.id) return;
      unawaited(_startProxy(auto: true));
    });
  }

  void _cancelReconnect({bool reset = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (reset) _reconnectAttempt = 0;
  }

  Future<void> _closeGuestAndHost() async {
    final guest = _guest;
    final host = _host;
    _guest = null;
    _host = null;
    await guest?.dispose();
    await host?.dispose();
  }

  Future<void> _closeProxyPorts(MdtbbsRelayProxyPorts? ports) async {
    if (ports == null) return;
    try {
      await ports.tcpServer.close();
    } on Object {
      // 已关闭
    }
    ports.udpSocket.close();
  }

  Future<void> stopProxy() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final guest = _guest;
    final host = _host;
    final tunnel = _tunnel;
    final subscription = _signalSubscription;
    _guest = null;
    _host = null;
    _tunnel = null;
    _signalSubscription = null;

    if (_current.proxyRunning) {
      _set(
        _current.copyWith(
          proxyRunning: false,
          clearLocalAddress: true,
          stoppingProxy: false,
        ),
      );
    }

    // 先摘掉 service 层 closed 回调，再拆 guest/host，避免旧 tunnel teardown
    // 期间的晚到事件重新进入 stopProxy 并碰到后续的新 tunnel。
    await subscription?.cancel();
    await guest?.dispose();
    await host?.dispose();
    await tunnel?.dispose();
  }

  String _describeProxyError(Object error) {
    final text = '$error';
    if (text.contains('AUTH_INVALID')) {
      return '连不上联机服务器，请稍后再试';
    }
    if (text.contains('RELAY_LIMIT_REACHED') || text.contains('额度已满')) {
      return '联机服务器还有一份你的旧连接，等 1 分钟再试';
    }
    if (text.contains('端口 6567')) {
      return '本机联机端口被占用，关掉游戏后再试';
    }
    if (text.contains('没有房主')) {
      return '房间信息还没同步好，稍后重试';
    }
    return '联机准备失败，请稍后再试';
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
