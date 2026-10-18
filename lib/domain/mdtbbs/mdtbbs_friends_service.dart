import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_error_text.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_friends_state.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 好友、待处理请求与在线状态的**唯一状态源**
///
/// 页面只做两件事：订阅 [state] 渲染、调下面的动作；网络调用不写在页面里
/// （散在页面里会切页就丢、每次进页面都得重拉一遍）
class MdtbbsFriendsService {
  MdtbbsFriendsService._();

  static final MdtbbsFriendsService instance = MdtbbsFriendsService._();

  final ValueNotifier<FriendsState> state = ValueNotifier(const FriendsState());

  AccountManager get _accounts => AccountManager.instance;

  /// 用例里替换令牌来源；生产代码不设置它
  @visibleForTesting
  static Future<String?> Function()? tokenOverride;

  Future<String?> _token() async => tokenOverride != null
      ? tokenOverride!()
      : _accounts.ensureAccessToken();

  FriendsState get _current => state.value;

  /// 服务端上限就是 50，一页拉满
  static const int _pageSize = 50;

  void _set(FriendsState next) => state.value = next;

  /// 统一出口：日志 + 右下角通知 + 存进状态
  void _notify(String text, {bool isError = false}) {
    if (isError) {
      addLogAndPrint(.warning, text, tag: 'Friends');
    } else {
      addLogAndPrint(.info, text, tag: 'Friends');
    }
    addNotice(
      icon: isError ? Icons.error_outline : Icons.check_circle_outline,
      title: isError ? '好友操作失败' : '好友',
      content: text,
      duration: const Duration(seconds: 8),
    );
    _set(_current.copyWith(lastMessage: text, lastMessageIsError: isError));
  }

  void clearMessage() => _set(_current.copyWith(clearMessage: true));

  /// 退出账号时清干净，别把上一个人的好友留在界面上
  void clear() => _set(const FriendsState());

  // ── 拉取 ────────────────────────────────────────────────────

  /// 拉第一页：好友（在线聚合）与待处理请求
  ///
  /// 两个接口**各自错误各自报** —— 一个失败时另一个照常显示，
  /// 不然「拉失败」和「真的一个好友都没有」在界面上长得一模一样
  Future<void> load({bool force = false}) async {
    if (_current.loading) return;
    if (!force && _current.loaded) return;
    final token = await _token();
    if (token == null) return;

    _set(_current.copyWith(loading: true));
    final failures = <String>[];
    List<MdtbbsFriendEntry>? friends;
    List<MdtbbsFriendRequest>? requests;

    try {
      final page = await MdtbbsFriendsApi.friendsPresence(
        accessToken: token,
        limit: _pageSize,
      );
      friends = page.entries;
      _set(
        _current.copyWith(
          friends: page.entries,
          page: page.page,
          totalPages: page.totalPages,
          total: page.total,
        ),
      );
    } on Object catch (error) {
      failures.add('好友列表：${describeMdtbbsError(error)}');
    }

    try {
      final page = await MdtbbsFriendsApi.requests(
        accessToken: token,
        limit: _pageSize,
      );
      requests = page.requests;
      _set(_current.copyWith(requests: page.requests));
    } on Object catch (error) {
      failures.add('好友请求：${describeMdtbbsError(error)}');
    }

    _set(_current.copyWith(loading: false, loaded: true));
    if (failures.isNotEmpty) {
      _notify('读取失败 —— ${failures.join('；')}', isError: true);
    } else {
      addLogAndPrint(
        .info,
        '好友 ${friends?.length ?? 0} 人（在线 ${_current.onlineCount}）、'
        '待处理请求 ${requests?.length ?? 0} 条',
        tag: 'Friends',
      );
    }
  }

  /// 再拉一页好友（服务端一页最多 50）
  Future<void> loadMore() async {
    if (_current.loadingMore || !_current.hasMore) return;
    final token = await _token();
    if (token == null) return;

    _set(_current.copyWith(loadingMore: true));
    try {
      final page = await MdtbbsFriendsApi.friendsPresence(
        accessToken: token,
        page: _current.page + 1,
        limit: _pageSize,
      );
      final known = {for (final entry in _current.friends) entry.user.userId};
      _set(
        _current.copyWith(
          friends: [
            ..._current.friends,
            ...page.entries.where((entry) => !known.contains(entry.user.userId)),
          ],
          page: page.page,
          totalPages: page.totalPages,
          total: page.total,
          loadingMore: false,
        ),
      );
    } on Object catch (error) {
      _set(_current.copyWith(loadingMore: false));
      _notify('加载更多好友失败：${describeMdtbbsError(error)}', isError: true);
    }
  }

  // ── 好友请求 ────────────────────────────────────────────────

  /// 按**用户 ID** 加好友
  ///
  /// 第三方接口没有「按用户名搜人」（论坛那套没进公开白名单）⇒ 只能让用户填 ID，
  /// 或者从会话成员列表里点着加
  Future<void> addFriend(int userId) async {
    if (userId <= 0) {
      _notify('用户 ID 不对', isError: true);
      return;
    }
    if (_current.busyUserIds.contains(userId)) return;
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }

    _set(
      _current.copyWith(busyUserIds: {..._current.busyUserIds, userId}),
    );
    try {
      await MdtbbsFriendsApi.sendRequest(
        accessToken: token,
        targetUserId: userId,
      );
      _notify('已向 ${_current.displayNameOf(userId)} 发出好友请求');
      // 反向请求可能被服务端直接合并成已接受关系 ⇒ 重新拉一次才看得到
      await load(force: true);
    } on Object catch (error) {
      _notify('加好友失败：${describeMdtbbsError(error)}', isError: true);
    } finally {
      _set(
        _current.copyWith(
          busyUserIds: {..._current.busyUserIds}..remove(userId),
        ),
      );
    }
  }

  /// 接受别人发来的好友请求（[requestId] 是**请求 ID**）
  Future<void> acceptRequest(String requestId) async {
    if (requestId.isEmpty) {
      _notify('这条请求没有 ID，无法处理', isError: true);
      return;
    }
    if (_current.busyRequestIds.contains(requestId)) return;
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }

    _set(
      _current.copyWith(
        busyRequestIds: {..._current.busyRequestIds, requestId},
      ),
    );
    try {
      await MdtbbsFriendsApi.acceptRequest(
        accessToken: token,
        requestId: requestId,
      );
      _removeRequestLocally(requestId);
      _notify('已接受好友请求');
      await load(force: true);
    } on Object catch (error) {
      _notify('接受失败：${describeMdtbbsError(error)}', isError: true);
    } finally {
      _set(
        _current.copyWith(
          busyRequestIds: {..._current.busyRequestIds}..remove(requestId),
        ),
      );
    }
  }

  /// 拒绝好友请求（[requestId] 是**请求 ID**）
  Future<void> rejectRequest(String requestId) async {
    if (requestId.isEmpty) {
      _notify('这条请求没有 ID，无法处理', isError: true);
      return;
    }
    if (_current.busyRequestIds.contains(requestId)) return;
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }

    _set(
      _current.copyWith(
        busyRequestIds: {..._current.busyRequestIds, requestId},
      ),
    );
    try {
      await MdtbbsFriendsApi.rejectRequest(
        accessToken: token,
        requestId: requestId,
      );
      _removeRequestLocally(requestId);
      _notify('已拒绝好友请求');
    } on Object catch (error) {
      _notify('拒绝失败：${describeMdtbbsError(error)}', isError: true);
    } finally {
      _set(
        _current.copyWith(
          busyRequestIds: {..._current.busyRequestIds}..remove(requestId),
        ),
      );
    }
  }

  /// 删好友（[userId] 是**整数用户 ID**）
  Future<void> removeFriend(int userId) async {
    if (_current.busyUserIds.contains(userId)) return;
    final token = await _token();
    if (token == null) {
      _notify('请先登录社区账号', isError: true);
      return;
    }

    _set(
      _current.copyWith(busyUserIds: {..._current.busyUserIds, userId}),
    );
    try {
      await MdtbbsFriendsApi.removeFriend(
        accessToken: token,
        userId: userId,
      );
      _set(
        _current.copyWith(
          friends: [
            for (final entry in _current.friends)
              if (entry.user.userId != userId) entry,
          ],
        ),
      );
      _notify('已删除好友');
    } on Object catch (error) {
      _notify('删除失败：${describeMdtbbsError(error)}', isError: true);
    } finally {
      _set(
        _current.copyWith(
          busyUserIds: {..._current.busyUserIds}..remove(userId),
        ),
      );
    }
  }

  void _removeRequestLocally(String requestId) {
    _set(
      _current.copyWith(
        requests: [
          for (final request in _current.requests)
            if (request.requestId != requestId) request,
        ],
      ),
    );
  }
}
