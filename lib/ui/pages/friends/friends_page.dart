import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_friends_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_friends_state.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/avatar/user_avatar.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

const friendsPageRouteKey = '/friends';

/// 好友页（账户抽屉里的一项）
///
/// 顶栏是搜索 + 加号：搜索在本地过滤（第三方接口没有按用户名搜人），
/// 加号弹框填数字用户 ID；好友列表里在房间里时可以直接邀请
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  MdtbbsFriendsService get _friends => MdtbbsFriendsService.instance;
  MdtbbsMultiplayerService get _mp => MdtbbsMultiplayerService.instance;
  AccountManager get _accounts => AccountManager.instance;

  /// 邀请冷却的倒计时：有冷却时才每秒重建（没冷却就白跑）
  Timer? _coolTick;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_accounts.isLoggedIn) unawaited(_friends.load());
    });
    _coolTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_mp.state.value.inSession) return;
      for (final entry in _friends.state.value.friends) {
        if (_mp.inviteCooldownLeft(entry.user.userId) > 0) {
          setState(() {});
          return;
        }
      }
    });
  }

  @override
  void dispose() {
    _coolTick?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _query) return;
    setState(() => _query = query);
  }

  Future<void> _showAddFriend() async {
    final userId = await showAnimatedDialog<int>(
      context: context,
      pageBuilder: (context, _, _) => const _AddFriendDialog(),
    );
    if (userId == null || !mounted) return;
    await _friends.addFriend(userId);
  }

  Future<void> _removeFriend(MdtbbsFriendEntry entry) async {
    final name = entry.user.username.isEmpty
        ? '用户 ${entry.user.userId}'
        : entry.user.username;
    await showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '删除好友',
      content: '确定把 $name 从好友列表删掉？',
      action: () => unawaited(_friends.removeFriend(entry.user.userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _friends.state,
        _accounts.snapshot,
        _mp.state,
      ]),
      builder: (context, _) {
        final friends = _friends.state.value;
        final loggedIn = _accounts.isLoggedIn;
        return Column(
          children: [
            _buildTopBar(loggedIn),
            Expanded(
              child: CopperSingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.block,
                    0,
                    AppSpacing.block,
                    AppSpacing.block,
                  ),
                  child: loggedIn
                      ? _buildFriendsPanel(friends)
                      : _buildLoginHint(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 顶栏：搜索 + 加号
  Widget _buildTopBar(bool loggedIn) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.block),
      child: Row(
        spacing: AppSpacing.related,
        children: [
          Expanded(
            child: OutlinedTextField(
              controller: _searchController,
              label: '搜索好友',
              enable: loggedIn,
            ),
          ),
          ReboundButton(
            backgroundColor: AppColors.of(context).highBackgroundOnCard,
            borderRadius: BorderRadius.circular(AppRadius.item),
            onTap: loggedIn ? _showAddFriend : null,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.add, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHint() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '好友',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          Text(
            '登录社区账号后才能加好友、看到谁在线',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.account_circle_outlined,
              content: '去登录',
              onTap: () => Navigator.pushNamed(context, accountPageRouteKey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsPanel(FriendsState friends) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final visible = _query.isEmpty
        ? friends.sortedFriends
        : friends.sortedFriends
              .where(
                (entry) =>
                    entry.user.username.toLowerCase().contains(
                      _query.toLowerCase(),
                    ) ||
                    '${entry.user.userId}' == _query,
              )
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.group,
      children: [
        if (friends.requests.isNotEmpty)
          ContentPanelModule(
            title: '好友请求',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.related,
              children: [
                for (final request in friends.requests)
                  _buildRequestRow(request),
              ],
            ),
          ),
        ContentPanelModule(
          title: '好友',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.related,
            children: [
              if (visible.isEmpty)
                Text(
                  friends.loading
                      ? '正在读取好友…'
                      : (_query.isEmpty ? '还没有好友' : '没有匹配的好友'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemHint,
                  ),
                )
              else
                for (final entry in visible) _buildFriendRow(entry),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '在线 ${friends.onlineCount} / 共 ${friends.friends.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.itemHint,
                      ),
                    ),
                  ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.refresh,
                    content: friends.loading ? '正在刷新…' : '刷新',
                    onTap: friends.loading
                        ? null
                        : () => _friends.load(force: true),
                  ),
                ],
              ),
              Text(
                '加好友要填数字用户 ID：第三方接口没有按用户名搜人',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRequestRow(MdtbbsFriendRequest request) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final busy = _friends.state.value.busyRequestIds.contains(
      request.requestId,
    );
    final name = request.user?.username ?? '有玩家';
    return Row(
      spacing: AppSpacing.related,
      children: [
        UserAvatar(url: request.user?.avatarUrl, size: 24),
        Expanded(
          child: Text(
            '$name 想加你为好友',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.check,
          content: '接受',
          onTap: busy ? null : () => _friends.acceptRequest(request.requestId),
        ),
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.close,
          content: '拒绝',
          onTap: busy ? null : () => _friends.rejectRequest(request.requestId),
        ),
      ],
    );
  }

  Widget _buildFriendRow(MdtbbsFriendEntry entry) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final userId = entry.user.userId;
    final busy = _friends.state.value.busyUserIds.contains(userId);
    final activity = entry.activity?.name;
    final status = entry.isOnline
        ? (activity == null || activity.isEmpty ? '在线' : '正在玩 $activity')
        : '离线';
    final multiplayer = _mp.state.value;
    final inRoom = multiplayer.peers.any((peer) => peer.userId == '$userId');
    final invited = multiplayer.sentInvites.any(
      (invite) => invite.targetUserId == '$userId',
    );
    // 冷却剩余秒数：界面上直接写出来，不然用户以为点了没反应
    final cooldown = _mp.inviteCooldownLeft(userId);
    final coolingDown = cooldown > 0;
    final inviteLabel = inRoom
        ? '已在房间'
        : invited
        ? '已邀请'
        : coolingDown
        ? '冷却 ${cooldown}s'
        : '邀请';
    return Row(
      spacing: AppSpacing.related,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(url: entry.user.avatarUrl, size: 28),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: entry.isOnline ? colors.success : colors.itemHint,
                  border: Border.all(color: colors.cardBackground, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.user.username.isEmpty
                    ? '用户 $userId'
                    : entry.user.username,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                status,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
            ],
          ),
        ),
        if (multiplayer.inSession)
          IconTextButton(
            pressedScale: 0.96,
            icon: Icons.send,
            content: inviteLabel,
            onTap: (busy || invited || inRoom || coolingDown)
                ? null
                : () => _mp.inviteFriend(userId),
          ),
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.person_remove_outlined,
          content: '删除',
          onTap: busy ? null : () => _removeFriend(entry),
        ),
      ],
    );
  }
}

/// 加好友：第三方接口只能按数字用户 ID 加，所以这里就一个输入框
class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog();

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final userId = int.tryParse(_controller.text.trim());
    if (userId == null || userId <= 0) {
      setState(() => _error = '填对方的数字用户 ID');
      return;
    }
    Navigator.of(context).pop(userId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Material(
          color: Colors.transparent,
          elevation: 6,
          child: Container(
            width: (MediaQuery.sizeOf(context).width - 32).clamp(0, 380),
            padding: const EdgeInsets.all(AppSpacing.block),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.panel),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.related,
              children: [
                Text('添加好友', style: theme.textTheme.titleMedium),
                Text(
                  '第三方接口没有按用户名搜人，只能填对方的数字用户 ID',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
                OutlinedTextField(
                  controller: _controller,
                  label: '用户 ID',
                  onEditingComplete: _submit,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                Row(
                  children: [
                    const Spacer(),
                    IconTextButton(
                      pressedScale: 0.96,
                      icon: Icons.close,
                      content: '取消',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    IconTextButton(
                      pressedScale: 0.96,
                      icon: Icons.person_add_alt_1,
                      content: '添加',
                      onTap: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
