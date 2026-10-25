import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_api.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_realtime_service.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

enum MdtbbsNoticeKind { friendRequest, invite, system }

/// 一条账户通知（好友请求 / 联机邀请 / 系统提示）
class MdtbbsNoticeItem {
  MdtbbsNoticeItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    DateTime? time,
    this.read = false,
  }) : time = time ?? DateTime.now();

  /// 去重键：同一份请求 / 邀请只记一条
  final String id;
  final MdtbbsNoticeKind kind;
  final String title;
  final String body;
  final DateTime time;
  bool read;

  IconData get icon => switch (kind) {
    MdtbbsNoticeKind.friendRequest => Icons.person_add_alt,
    MdtbbsNoticeKind.invite => Icons.mail_outline,
    MdtbbsNoticeKind.system => Icons.info_outline,
  };
}

/// 账户通知的中心：实时事件优先，轮询兜底
///
/// 主路径是 `/realtime/v1`（[MdtbbsRealtimeService]）：好友请求 / 联机邀请一到达就记一条并弹提示。
/// 轮询留作兜底：实时通道没连上（没网、票据失败、服务端开关关着）时每 30 秒拉一次，
/// 两者用同一套去重键，不会重复弹。
class MdtbbsNotificationService {
  MdtbbsNotificationService._() {
    _accounts.snapshot.addListener(_onAccountChanged);
    // 实时通道把事件抛过来，直接进同一个列表
    final realtime = MdtbbsRealtimeService.instance;
    realtime.onEvent = handleRealtimeEvent;
    realtime.onNeedSnapshot = () => unawaited(_poll(announce: true));
    if (_accounts.isLoggedIn) unawaited(_start());
  }

  static final MdtbbsNotificationService instance =
      MdtbbsNotificationService._();

  final ValueNotifier<List<MdtbbsNoticeItem>> items = ValueNotifier(const []);

  AccountManager get _accounts => AccountManager.instance;

  Timer? _timer;
  bool _polling = false;
  bool _wasLoggedIn = false;

  /// 已经处理过的键：第一次轮询只登记、不弹，免得每次启动把旧请求全弹一遍
  final Set<String> _seen = {};
  bool _seeded = false;

  int get unreadCount => items.value.where((item) => !item.read).length;

  void _onAccountChanged() {
    final loggedIn = _accounts.isLoggedIn;
    if (loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = loggedIn;
    if (loggedIn) {
      unawaited(_start());
    } else {
      _stop();
      clear();
    }
  }

  Future<void> _start() async {
    _timer?.cancel();
    await _poll(announce: false);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_poll(announce: true));
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void markAllRead() {
    var changed = false;
    for (final item in items.value) {
      if (!item.read) {
        item.read = true;
        changed = true;
      }
    }
    if (changed) items.value = List.of(items.value);
  }

  void clear() {
    _seen.clear();
    _seeded = false;
    items.value = const [];
  }

  /// 实时通道来事件：与轮询用同一套去重键，谁先到算谁
  void handleRealtimeEvent(MdtbbsRealtimeEvent event) {
    final data = event.data;
    MdtbbsNoticeItem? item;
    switch (event.event) {
      case 'friend.request.created':
        final id = '${data['request_id'] ?? data['id'] ?? ''}';
        if (id.isEmpty) break;
        final user = data['user'];
        final name = (user is Map ? '${user['username'] ?? ''}' : '');
        item = MdtbbsNoticeItem(
          id: 'friend:$id',
          kind: MdtbbsNoticeKind.friendRequest,
          title: '好友请求',
          body: name.isEmpty ? '有人想加你为好友' : '$name 想加你为好友',
        );
      case 'multiplayer.invite.created':
        final id = '${data['invite_id'] ?? data['id'] ?? ''}';
        if (id.isEmpty) break;
        final session = data['session'];
        final room = (session is Map ? '${session['activity_name'] ?? ''}' : '');
        item = MdtbbsNoticeItem(
          id: 'invite:$id',
          kind: MdtbbsNoticeKind.invite,
          title: '联机邀请',
          body: room.isEmpty ? '有人邀请你进入房间' : '邀请你进入「$room」',
        );
      default:
        return;
    }
    final notice = item;
    if (notice == null) return;
    if (!_seen.add(notice.id)) return;
    _seeded = true;
    items.value = [notice, ...items.value];
    addNotice(
      icon: notice.icon,
      title: notice.title,
      content: notice.body,
      duration: const Duration(seconds: 6),
    );
    addLogAndPrint(.info, '实时通知：${notice.title}（${notice.body}）', tag: 'Notify');
  }

  Future<void> _poll({required bool announce}) async {
    if (_polling) return;
    // 实时通道连着就不轮询了；没连上时它仍然是兜底
    if (_seeded && MdtbbsRealtimeService.instance.connected.value) return;
    _polling = true;
    final fresh = <MdtbbsNoticeItem>[];
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) return;

      final requests = await MdtbbsFriendsApi.requests(accessToken: token);
      for (final request in requests.requests) {
        final key = 'friend:${request.requestId}';
        if (!_seen.add(key)) continue;
        if (!_seeded) continue;
        fresh.add(
          MdtbbsNoticeItem(
            id: key,
            kind: MdtbbsNoticeKind.friendRequest,
            title: '好友请求',
            body: '${_nameOfRequest(request)} 想加你为好友',
          ),
        );
      }

      final invites = await MdtbbsMultiplayerApi.invites(accessToken: token);
      for (final invite in invites) {
        final key = 'invite:${invite.inviteId}';
        if (!_seen.add(key)) continue;
        if (!_seeded) continue;
        final room = invite.session?.activityName;
        fresh.add(
          MdtbbsNoticeItem(
            id: key,
            kind: MdtbbsNoticeKind.invite,
            title: '联机邀请',
            body: room == null || room.isEmpty ? '有人邀请你进入房间' : '邀请你进入「$room」',
          ),
        );
      }

      _seeded = true;
    } on Object catch (error) {
      // 轮询失败不打扰：下一次还会再拉
      addLog(.debug, '账户通知轮询失败：$error', tag: 'Notify');
      return;
    } finally {
      _polling = false;
    }

    if (fresh.isEmpty) return;
    items.value = [...fresh, ...items.value];
    if (announce) {
      for (final item in fresh) {
        addNotice(
          icon: item.icon,
          title: item.title,
          content: item.body,
          duration: const Duration(seconds: 6),
        );
      }
    }
    addLogAndPrint(.info, '账户通知：新增 ${fresh.length} 条', tag: 'Notify');
  }

  String _nameOfRequest(MdtbbsFriendRequest request) {
    final name = request.user?.username ?? '';
    return name.isEmpty ? '有人' : name;
  }
}
