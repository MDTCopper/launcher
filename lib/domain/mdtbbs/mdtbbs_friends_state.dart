import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';

/// 好友与在线状态在界面上的唯一状态源
///
/// 与联机会话的状态（`MultiplayerState`）分开：好友是**账号级**的、跟房间无关，
/// 而联机会话是临时的；混在一个 notifier 里会让「换房间」连带把好友列表也刷一遍
class FriendsState {
  const FriendsState({
    this.friends = const [],
    this.requests = const [],
    this.loaded = false,
    this.loading = false,
    this.loadingMore = false,
    this.page = 0,
    this.totalPages = 1,
    this.total = 0,
    this.busyUserIds = const {},
    this.busyRequestIds = const {},
    this.lastMessage,
    this.lastMessageIsError = false,
  });

  /// 好友（含在线状态、正在玩什么、服务端算好的按钮门禁）
  final List<MdtbbsFriendEntry> friends;

  /// 待处理的好友请求（别人发给我的）
  final List<MdtbbsFriendRequest> requests;

  /// 至少成功拉过一次（界面用它区分「空列表」与「还没拉」）
  final bool loaded;
  final bool loading;
  final bool loadingMore;
  final int page;
  final int totalPages;
  final int total;

  /// 正在加 / 删的好友（按操作粒度禁用，不整页锁死）
  final Set<int> busyUserIds;

  /// 正在接受 / 拒绝的请求
  final Set<String> busyRequestIds;

  final String? lastMessage;
  final bool lastMessageIsError;

  bool get hasMore => page < totalPages;
  int get onlineCount => friends.where((entry) => entry.isOnline).length;

  /// 在线优先、其次按名字 —— 列表就按这个顺序画
  List<MdtbbsFriendEntry> get sortedFriends {
    final sorted = [...friends];
    sorted.sort((left, right) {
      if (left.isOnline != right.isOnline) return left.isOnline ? -1 : 1;
      return left.user.username.toLowerCase().compareTo(
        right.user.username.toLowerCase(),
      );
    });
    return sorted;
  }

  MdtbbsFriendEntry? entryOf(int userId) {
    for (final entry in friends) {
      if (entry.user.userId == userId) return entry;
    }
    return null;
  }

  /// 我发出的邀请里记着的用户 ID 拿不到名字 ⇒ 用好友列表补一个显示名
  String displayNameOf(int userId) {
    final entry = entryOf(userId);
    if (entry != null && entry.user.username.isNotEmpty) {
      return entry.user.username;
    }
    return '用户 $userId';
  }

  FriendsState copyWith({
    List<MdtbbsFriendEntry>? friends,
    List<MdtbbsFriendRequest>? requests,
    bool? loaded,
    bool? loading,
    bool? loadingMore,
    int? page,
    int? totalPages,
    int? total,
    Set<int>? busyUserIds,
    Set<String>? busyRequestIds,
    String? lastMessage,
    bool? lastMessageIsError,
    bool clearMessage = false,
  }) => FriendsState(
    friends: friends ?? this.friends,
    requests: requests ?? this.requests,
    loaded: loaded ?? this.loaded,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    total: total ?? this.total,
    busyUserIds: busyUserIds ?? this.busyUserIds,
    busyRequestIds: busyRequestIds ?? this.busyRequestIds,
    lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
    lastMessageIsError: lastMessageIsError ?? this.lastMessageIsError,
  );
}
