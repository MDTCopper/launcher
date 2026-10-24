import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_api.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
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

/// 账户通知的中心：轮询好友请求与联机邀请，新的就记一条并弹一次提示
///
/// 先做轮询版（30 秒一次）。官方文档里有 `/realtime/v1` 的事件流
/// （`friend.request.created`、`multiplayer.invite.created`…），
/// 下一轮把那套接上就能改成实时，这里的 [items] 不用动
class MdtbbsNotificationService {
  MdtbbsNotificationService._() {
    _accounts.snapshot.addListener(_onAccountChanged);
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

  Future<void> _poll({required bool announce}) async {
    if (_polling) return;
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
