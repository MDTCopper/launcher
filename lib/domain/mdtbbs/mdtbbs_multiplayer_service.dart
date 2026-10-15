import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/account/account_store.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_error_text.dart';
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
import 'package:flutter/services.dart';

/// 官方联机的**唯一状态源**：会话、能力、通道、心跳都由它持有
///
/// 页面只做两件事：订阅 [state] 渲染、调下面的动作。**网络调用一律不写在页面里**
/// —— 状态散在页面里会切页就丢（加入码只从创建响应里给一次，丢了找不回），
/// 也会让每次进页面都得重新拉一遍
class MdtbbsMultiplayerService {
  MdtbbsMultiplayerService._() {
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

  /// 会话任务卡片：owner 是任务管理器（页面切走也不失控）
  late final MultiplayerSessionTask _sessionTask = MultiplayerSessionTask(
    onCancel: leave,
  );

  Timer? _heartbeatTimer;
  String? _heartbeatPeerId;
  String? _heartbeatSessionId;
  int _heartbeatFailures = 0;
  bool _heartbeatInFlight = false;
  bool _heartbeatRecoveryInFlight = false;

  String? _boundAccountSubject;
  bool _accountResetInFlight = false;

  /// 拿 BBS 的 Bearer 令牌；未登录返回 null
  Future<String?> _token() async => tokenOverride != null
      ? tokenOverride!()
      : _accounts.ensureAccessToken();

  /// 用例里替换令牌来源；生产代码不设置它
  @visibleForTesting
  static Future<String?> Function()? tokenOverride;

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

  void _onAccountSnapshotChanged() {
    final snapshot = _accounts.snapshot.value;
    if (!snapshot.loggedIn) {
      _boundAccountSubject = null;
      if (_hasLiveMultiplayerState) unawaited(_resetForAccountChange());
      return;
    }

    final subject = snapshot.subject;
    if (subject == null || subject.isEmpty) return;
    final previous = _boundAccountSubject;
    _boundAccountSubject = subject;
    if (previous != null && previous != subject) {
      unawaited(_resetForAccountChange());
    }
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
      await stopProxy(announce: false);
      _set(const MultiplayerState());
    } finally {
      _accountResetInFlight = false;
    }
  }

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

  /// 先读落盘的加入码和恢复令牌，再按服务端恢复协议恢复同一个 peer。
  Future<void> restore() async {
    if (!_accounts.isConfigured) return;
    // 服务里已经有活着的会话（同一进程内切页回来）就不必重读重拉
    if (_current.session != null) return;
    await _accounts.restore();
    _boundAccountSubject = _accounts.subject;
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
    final token = await _token();
    if (token == null) {
      _set(_current.copyWith(resuming: false));
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
        addLogAndPrint(.info, '已用恢复令牌恢复联机会话 ${session.id}', tag: 'Multiplayer');
        return;
      } on MdtbbsException catch (error) {
        if (!_isTerminalResumeError(error.code)) {
          _set(_current.copyWith(resuming: false));
          _notify('恢复联机会话失败：${describeMdtbbsError(error)}', isError: true);
          return;
        }
        // PEER_RESUME_INVALID 也可能是上一次恢复请求已成功、但响应在客户端落盘前丢失。
        // 先检查旧 peer 是否仍处于 active，再决定是否清掉本地会话。
        if (error.code == 'PEER_RESUME_INVALID' &&
            await _adoptStillActiveStoredPeer(stored, token)) {
          return;
        }
        await _clearStoredSessionAfterServerRejection();
        return;
      } on Object catch (error) {
        _set(_current.copyWith(resuming: false));
        _notify('恢复联机会话失败：$error', isError: true);
        return;
      }
    }

    // 兼容旧落盘：没有 resume token 时只能确认旧 peer 仍然活跃，不能伪造一次恢复。
    if (await _adoptStillActiveStoredPeer(stored, token)) return;
    await _clearStoredSessionAfterServerRejection();
  }

  bool _isTerminalResumeError(String? code) =>
      code == 'PEER_RESUME_INVALID' ||
      code == 'SESSION_NOT_FOUND' ||
      code == 'SESSION_CLOSED' ||
      code == 'PEER_EXPIRED';

  Future<bool> _adoptStillActiveStoredPeer(
    StoredMultiplayerSession stored,
    String token,
  ) async {
    final peerId = stored.peerId;
    if (peerId == null || peerId.isEmpty) return false;
    try {
      final session = await MdtbbsMultiplayerApi.currentSession(
        accessToken: token,
      );
      if (session == null || session.id != stored.sessionId) return false;
      final peers = await MdtbbsMultiplayerApi.peers(
        accessToken: token,
        sessionId: session.id,
      );
      MdtbbsPeer? self;
      for (final peer in peers) {
        if (peer.peerId == peerId && peer.status == 'active') {
          self = peer;
          break;
        }
      }
      if (self == null) return false;

      _heartbeatPeerId = self.peerId;
      _heartbeatSessionId = session.id;
      _heartbeatFailures = 0;
      _accounts.saveMultiplayerSession(
        StoredMultiplayerSession(
          sessionId: session.id,
          peerId: self.peerId,
          // 旧 token 已被服务端判无效，不能继续假装它还能恢复下一次重启。
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
      _beginSessionTask();
      _armHeartbeat();
      addLogAndPrint(
        .warning,
        '恢复令牌不可用，但服务端仍确认旧 peer 活跃；本次进程继续使用该 peer',
        tag: 'Multiplayer',
      );
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _clearStoredSessionAfterServerRejection() async {
    forgetSession();
    _finishSessionTask();
    await stopProxy(announce: false);
    _accounts.clearMultiplayerSession();
    _set(
      _current.copyWith(
        clearSession: true,
        clearJoinCode: true,
        clearSelf: true,
        peers: const [],
        resuming: false,
        clearSentInvites: true,
      ),
    );
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
        await _clearStoredSessionAfterServerRejection();
        return;
      }
      final peers = await MdtbbsMultiplayerApi.peers(
        accessToken: token,
        sessionId: session.id,
      );
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
          peers: peers,
          resuming: false,
        ),
      );
      _beginSessionTask();
      _armHeartbeat();
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
      // 加入码服务端只给这一次，直接放进剪贴板，省掉「还得点一下复制」
      final joinCode = created.joinCode;
      if (joinCode != null) {
        try {
          await Clipboard.setData(ClipboardData(text: joinCode));
        } on Object {
          // 剪贴板不可用不影响建房
        }
      }
      _notify(
        joinCode == null
            ? '房间已创建（${created.session.id}）；这个可见范围不给加入码，只能靠邀请'
            : '房间已创建，加入码 $joinCode（已复制到剪贴板）',
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
          // 我发出的邀请都指向这个房间，房间不要了就一并清掉
          clearSentInvites: true,
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

  // ── 邀请 ────────────────────────────────────────────────────
  //
  // 服务端只提供「我收到的邀请」（`GET /multiplayer/invites`），**没有「我发出的」列表**
  // ⇒ 发出的那几条只能在创建响应里记进状态（内存态，重启即丢；它们本身 5 分钟就失效）

  Timer? _inviteTimer;

  /// 页面可见时开着：邀请 5 分钟过期、又没有实时通道（P3 realtime 那步做完再换成推送），
  /// 只能定时拉一下才看得见新邀请
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

  /// 刷一次「收到的邀请」
  Future<void> refreshInvites({bool announce = false}) async {
    final token = await _token();
    if (token == null) return;
    _set(_current.copyWith(loadingInvites: true));
    try {
      final invites = await MdtbbsMultiplayerApi.invites(
        accessToken: token,
      );
      _set(_current.copyWith(invites: invites, loadingInvites: false));
      if (announce) {
        _notify(invites.isEmpty ? '没有待处理的邀请' : '待处理邀请 ${invites.length} 条');
      }
    } on Object catch (error) {
      _set(_current.copyWith(loadingInvites: false));
      // 轮询失败很常见（切页 / 掉网），只在用户主动刷时说一句
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

  /// 邀请好友进当前会话；[targetUserId] 是论坛**整数**用户 ID
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
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }
    _set(_current.copyWith(inviting: true));
    try {
      final invite = await MdtbbsMultiplayerApi.createInvite(
        accessToken: token,
        sessionId: session.id,
        targetUserId: targetUserId,
      );
      _set(
        _current.copyWith(
          // 同一个目标重复邀请时，服务端可能给新的 invite_id ⇒ 按 id 去重后放最前
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
      _set(_current.copyWith(inviting: false));
      _notify('邀请失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  /// 撤销我发出的邀请
  Future<void> revokeInvite(String inviteId) =>
      _respondInvite(inviteId, revoke: true);

  /// 拒绝收到的邀请
  Future<void> declineInvite(String inviteId) =>
      _respondInvite(inviteId, revoke: false);

  Future<void> _respondInvite(String inviteId, {required bool revoke}) async {
    if (inviteId.isEmpty) {
      _notify('这条邀请没有 ID，无法处理', isError: true);
      return;
    }
    if (_current.busyInviteId != null) return;
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }
    _set(_current.copyWith(busyInviteId: inviteId));
    try {
      await MdtbbsMultiplayerApi.respondInvite(
        accessToken: token,
        inviteId: inviteId,
        revoke: revoke,
      );
      _set(
        _current.copyWith(
          clearBusyInvite: true,
          invites: revoke ? _current.invites : _withoutInvite(inviteId),
          sentInvites:
              revoke ? _withoutSentInvite(inviteId) : _current.sentInvites,
        ),
      );
      _notify(revoke ? '已撤销邀请' : '已拒绝邀请');
    } on Object catch (error) {
      _set(_current.copyWith(clearBusyInvite: true));
      _notify(
        '${revoke ? '撤销' : '拒绝'}邀请失败：${describeMdtbbsError(error)}',
        isError: true,
      );
    }
  }

  /// 接受收到的邀请：拿加入意图 → 消费 → 成为对端
  ///
  /// 收尾与「用加入码加入」共用同一套（落盘 / 心跳 / 任务卡片 / 刷成员），
  /// 只有一处不同：这条路**没有加入码**（邀请不需要码）
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
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }
    _set(_current.copyWith(busyInviteId: inviteId));
    try {
      final intent = await MdtbbsMultiplayerApi.acceptInvite(
        accessToken: token,
        inviteId: inviteId,
      );
      final joined = await MdtbbsMultiplayerApi.consumeJoinIntent(
        accessToken: token,
        intentId: intent.intentId,
      );
      final session = await MdtbbsMultiplayerApi.session(
        accessToken: token,
        sessionId: invite.sessionId,
      );
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
    } on Object catch (error) {
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
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_heartbeatInFlight) return;
      unawaited(_beat(sessionId, peerId));
    });
  }

  Future<void> _beat(String sessionId, String peerId) async {
    if (_heartbeatInFlight) return;
    _heartbeatInFlight = true;
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
      if (_heartbeatFailures >= 3 && !_heartbeatRecoveryInFlight) {
        unawaited(_recoverHeartbeatSession(sessionId, peerId));
      }
    } finally {
      _heartbeatInFlight = false;
    }
  }

  Future<void> _recoverHeartbeatSession(String sessionId, String peerId) async {
    if (_heartbeatRecoveryInFlight ||
        _heartbeatSessionId != sessionId ||
        _heartbeatPeerId != peerId) {
      return;
    }
    _heartbeatRecoveryInFlight = true;
    try {
      final stored = _accounts.multiplayerSession;
      final token = await _token();
      if (stored == null ||
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
          if (joined.resumed) {
            final session = await MdtbbsMultiplayerApi.session(
              accessToken: token,
              sessionId: sessionId,
            );
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
            addLogAndPrint(.info, '心跳异常后已恢复原联机 peer', tag: 'Multiplayer');
            return;
          }
        } on MdtbbsException catch (error) {
          if (!_isTerminalResumeError(error.code)) {
            addLogAndPrint(
              .warning,
              '心跳恢复请求失败，保留会话等待下一轮：${describeMdtbbsError(error)}',
              tag: 'Multiplayer',
            );
            return;
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

      if (await _adoptStillActiveStoredPeer(stored, token)) return;

      addLogAndPrint(.error, '心跳连续失败且服务端无法恢复原 peer，清理本地会话', tag: 'Multiplayer');
      await _clearStoredSessionAfterServerRejection();
    } finally {
      _heartbeatRecoveryInFlight = false;
    }
  }

  /// 会话结束才彻底忘掉心跳身份
  void forgetSession() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatPeerId = null;
    _heartbeatSessionId = null;
    _heartbeatFailures = 0;
    _heartbeatInFlight = false;
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
      allocateRelay: () async {
        final freshToken = await _token();
        if (freshToken == null) {
          throw const MdtbbsRelayException('登录状态已失效，无法续签中继凭证');
        }
        return MdtbbsMultiplayerApi.allocateRelay(
          accessToken: freshToken,
          sessionId: session.id,
        );
      },
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
        final peersToken = await _token();
        if (peersToken == null) {
          ports.tcpServer.close();
          ports.udpSocket.close();
          throw const MdtbbsRelayException('登录状态已失效，无法读取房间成员');
        }
        final peers = await MdtbbsMultiplayerApi.peers(
          accessToken: peersToken,
          sessionId: session.id,
        ).timeout(const Duration(seconds: 15));
        final owner = peers.where((p) => p.role == 'owner').toList();
        if (owner.isEmpty) {
          ports.tcpServer.close();
          ports.udpSocket.close();
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
      _notify('启动联机通道失败：${_describeProxyError(error)}', isError: true);
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

  Future<void> stopProxy({bool announce = true}) async {
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
    if (wasRunning && announce) _notify('联机通道已停止');
  }

  /// 把中继的两种典型失败翻成人话
  String _describeProxyError(Object error) {
    final text = '$error';
    if (text.contains('RELAY_LIMIT_REACHED') || text.contains('额度已满')) {
      return '官方中继并发额度已满：同一个房间的这个身份同时只能占 1 条中继连接。'
          '请等 1~2 分钟再试（或先离开房间重新进入）';
    }
    if (text.contains('AUTH_INVALID')) {
      return '中继认证被拒（AUTH_INVALID）：官方中继没认下这份凭证。'
          '日志里有一行「中继拒绝认证（诊断用）」，把它发给管理员即可定位';
    }
    return text;
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