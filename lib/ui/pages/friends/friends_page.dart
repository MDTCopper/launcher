import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_friends_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_friends_state.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:flutter/material.dart';

const friendsPageRouteKey = '/friends';

/// 好友页（账户抽屉里的一项）
///
/// 从联机页搬出来的：好友是账号级的东西，跟开没开房没关系。
/// 状态仍然只在 [MdtbbsFriendsService] 里，这里只负责画和点
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _friendIdController = TextEditingController();

  MdtbbsFriendsService get _friends => MdtbbsFriendsService.instance;
  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_accounts.isLoggedIn) unawaited(_friends.load());
    });
  }

  @override
  void dispose() {
    _friendIdController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _friends.load(force: true);
  }

  Future<void> _addFriend() async {
    final userId = int.tryParse(_friendIdController.text.trim());
    if (userId == null || userId <= 0) {
      addNotice(
        icon: Icons.info_outline,
        title: '用户 ID 不对',
        content: '填对方的数字用户 ID',
      );
      return;
    }
    await _friends.addFriend(userId);
    if (!mounted) return;
    _friendIdController.clear();
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
      animation: Listenable.merge([_friends.state, _accounts.snapshot]),
      builder: (context, _) {
        final friends = _friends.state.value;
        final loggedIn = _accounts.isLoggedIn;
        return CopperSingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.block),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.group,
              children: [
                if (!loggedIn)
                  _buildLoginHint(context)
                else
                  _buildFriendsPanel(context, friends),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginHint(BuildContext context) {
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

  Widget _buildFriendsPanel(BuildContext context, FriendsState friends) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '好友',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          for (final request in friends.requests) _buildRequestRow(request),
          if (friends.friends.isEmpty)
            Text(
              friends.loading ? '正在读取好友…' : '还没有好友，下面填用户 ID 添加',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
            )
          else
            for (final entry in friends.sortedFriends) _buildFriendRow(entry),
          _buildAddFriendRow(),
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
                onTap: friends.loading ? null : _refresh,
              ),
            ],
          ),
          Text(
            '好友只能按数字用户 ID 添加：第三方接口没有按用户名搜人',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.itemHint,
            ),
          ),
        ],
      ),
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
        Icon(
          Icons.person_add_alt,
          size: AppIconSize.item,
          color: colors.interactive,
        ),
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
    return Row(
      spacing: AppSpacing.related,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: entry.isOnline ? colors.success : colors.itemHint,
          ),
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
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.person_remove_outlined,
          content: '删除',
          onTap: busy ? null : () => _removeFriend(entry),
        ),
      ],
    );
  }

  Widget _buildAddFriendRow() {
    return Row(
      spacing: AppSpacing.related,
      children: [
        Expanded(
          child: OutlinedTextField(
            controller: _friendIdController,
            label: '好友用户 ID（数字）',
            onEditingComplete: _addFriend,
          ),
        ),
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.person_add_alt_1,
          content: '加好友',
          onTap: _addFriend,
        ),
      ],
    );
  }
}
