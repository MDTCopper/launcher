import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_presence_api.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_error_text.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';

/// 自己这条在线连接（`/api/v1/presence/connections`）
///
/// 服务端靠这条连接把「我」标成在线，并让好友看到我正在玩什么。
/// 不建连接 = 一直离线，好友列表里永远「在线 0」（2026-10-24 实测确认）。
///
/// 生命周期跟账号走：登录后建连接，退出登录删连接；
/// 应用直接被杀掉时连接会在 90 秒后自然过期，不用额外兜底
class MdtbbsPresenceService {
  MdtbbsPresenceService._() {
    _accounts.snapshot.addListener(_onAccountChanged);
    unawaited(_bootstrap());
  }

  static final MdtbbsPresenceService instance = MdtbbsPresenceService._();

  /// 启动时读一次账号态：只在页面上等「进了账户页才上报」会漏掉大半天
  Future<void> _bootstrap() async {
    await _accounts.ensureRestored();
    _wasLoggedIn = _accounts.isLoggedIn;
    if (_wasLoggedIn) unawaited(_connect());
  }

  /// 是否已经建好连接（界面上「在线」那一盏灯用）
  final ValueNotifier<bool> online = ValueNotifier(false);

  AccountManager get _accounts => AccountManager.instance;

  String? _connectionId;
  Timer? _heartbeatTimer;
  bool _connecting = false;

  /// 账号变更时 +1：之前发出的请求回来时直接丢弃
  int _epoch = 0;

  /// 上一帧的登录态：快照每次发布都会通知，这里只认登录 / 登出的跳变
  bool _wasLoggedIn = false;

  String? get connectionId => _connectionId;

  bool get isOnline => _connectionId != null;

  String get _platform => Platform.isAndroid ? 'android' : 'launcher';

  void _onAccountChanged() {
    final loggedIn = _accounts.isLoggedIn;
    if (loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = loggedIn;
    _epoch++;
    if (loggedIn) {
      unawaited(_connect());
    } else {
      unawaited(_disconnect());
    }
  }

  Future<void> _connect() async {
    if (_connecting || _connectionId != null) return;
    _connecting = true;
    final epoch = _epoch;
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) return;
      final connection = await MdtbbsPresenceApi.createConnection(
        accessToken: token,
        platform: _platform,
      );
      if (epoch != _epoch) {
        // 期间登出 / 换号了：这条连接已经不是当前账号的，收掉
        unawaited(_remove(connection.connectionId));
        return;
      }
      _connectionId = connection.connectionId;
      online.value = true;
      addLogAndPrint(
        .info,
        '在线状态已上报：连接 ${connection.connectionId}，'
        '心跳 ${connection.heartbeatInterval}s，${connection.expiresIn}s 过期',
        tag: 'Presence',
      );
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        Duration(seconds: connection.heartbeatInterval),
        (_) => unawaited(_beat(epoch)),
      );
    } on Object catch (error) {
      addLogAndPrint(
        .warning,
        '在线状态上报失败：${describeMdtbbsError(error)}',
        tag: 'Presence',
      );
    } finally {
      _connecting = false;
    }
  }

  Future<void> _beat(int epoch) async {
    final id = _connectionId;
    if (id == null || epoch != _epoch) return;
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null || epoch != _epoch) return;
      await MdtbbsPresenceApi.heartbeat(
        accessToken: token,
        connectionId: id,
      );
    } on Object catch (error) {
      if (epoch != _epoch) return;
      addLogAndPrint(
        .warning,
        '在线状态心跳失败，重建连接：${describeMdtbbsError(error)}',
        tag: 'Presence',
      );
      _connectionId = null;
      online.value = false;
      _heartbeatTimer?.cancel();
      unawaited(_connect());
    }
  }

  Future<void> _disconnect() async {
    final id = _connectionId;
    _connectionId = null;
    online.value = false;
    _heartbeatTimer?.cancel();
    if (id != null) await _remove(id);
  }

  /// 删连接只是「尽快下线」；失败无所谓，90 秒后服务端自己会清
  Future<void> _remove(String connectionId) async {
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) return;
      await MdtbbsPresenceApi.deleteConnection(
        accessToken: token,
        connectionId: connectionId,
      );
    } on Object {
      // 静默：退出登录 / 断网都很常见，不值得打扰用户
    }
  }
}
