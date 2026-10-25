import 'dart:async';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_api.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_notification_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

const notificationsPageRouteKey = '/notifications';

/// 账户通知页：好友请求、联机邀请与系统提示都堆在这里
///
/// 数据来自 [MdtbbsNotificationService]（实时事件优先、轮询兜底），
/// 每条都带「就地处理」的按钮：好友请求可以同意 / 拒绝，联机邀请可以直接接受
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  MdtbbsNotificationService get _notifications =>
      MdtbbsNotificationService.instance;

  /// 正在处理某条通知（按钮转圈、防重复点）
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return AnimatedBuilder(
      animation: _notifications.items,
      builder: (context, _) {
        final items = _notifications.items.value;
        return CopperSingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.block),
            child: ContentPanelModule(
              title: '账户通知',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.related,
                children: [
                  if (items.isEmpty)
                    Text(
                      '还没有通知。好友请求、联机邀请会出现在这里',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.itemHint,
                      ),
                    )
                  else
                    for (final item in items) _buildRow(context, item),
                  if (items.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '未读 ${_notifications.unreadCount} 条',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.itemHint,
                            ),
                          ),
                        ),
                        IconTextButton(
                          pressedScale: 0.96,
                          icon: Icons.mark_email_read_outlined,
                          content: '全部已读',
                          onTap: _notifications.markAllRead,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, MdtbbsNoticeItem item) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final busy = _busyId == item.id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.related,
      children: [
        Icon(
          item.icon,
          size: AppIconSize.item,
          color: item.read ? colors.itemHint : colors.interactive,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                item.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: item.read ? colors.itemSecondary : colors.itemPrimary,
                ),
              ),
              Text(
                item.body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.itemSecondary,
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _buildActions(context, item),
            ],
          ),
        ),
        Text(
          item.time.toTimeString(),
          style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
        ),
      ],
    );
  }

  /// 就地处理：好友请求能同意 / 拒绝，联机邀请能直接接受
  Widget _buildActions(BuildContext context, MdtbbsNoticeItem item) {
    final target = item.id.split(':');
    if (target.length != 2) return const SizedBox.shrink();
    final kind = target.first;
    final targetId = target.last;
    final actions = <Widget>[];
    if (kind == 'friend') {
      actions.add(
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.check,
          content: '同意',
          onTap: () => unawaited(_acceptFriend(targetId)),
        ),
      );
      actions.add(
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.close,
          content: '拒绝',
          onTap: () => unawaited(_rejectFriend(targetId)),
        ),
      );
    } else if (kind == 'invite') {
      actions.add(
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.login,
          content: '接受邀请',
          onTap: () => unawaited(_acceptInvite(targetId)),
        ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(spacing: AppSpacing.related, children: actions);
  }

  Future<void> _acceptFriend(String requestId) async {
    await _run(requestId, 'friend:$requestId', () async {
      final token = await AccountManager.instance.ensureAccessToken();
      if (token == null) throw const _NoticeActionError('还没登录');
      await MdtbbsFriendsApi.acceptRequest(
        accessToken: token,
        requestId: requestId,
      );
      return '已同意好友请求';
    });
  }

  Future<void> _rejectFriend(String requestId) async {
    await _run(requestId, 'friend:$requestId', () async {
      final token = await AccountManager.instance.ensureAccessToken();
      if (token == null) throw const _NoticeActionError('还没登录');
      await MdtbbsFriendsApi.rejectRequest(
        accessToken: token,
        requestId: requestId,
      );
      return '已拒绝好友请求';
    });
  }

  Future<void> _acceptInvite(String inviteId) async {
    await _run(inviteId, 'invite:$inviteId', () async {
      await MdtbbsMultiplayerService.instance.acceptInvite(inviteId);
      return '正在进入房间';
    });
  }

  /// 统一的执行壳：转圈 → 调接口 → 打日志 / 提示 → 标记已读
  Future<void> _run(
    String targetId,
    String noticeId,
    Future<String> Function() action,
  ) async {
    if (_busyId != null) return;
    setState(() => _busyId = noticeId);
    try {
      final message = await action();
      addNotice(icon: Icons.check, title: message);
      addLog(.info, '通知处理：$message（$targetId）', tag: 'Notify');
      _notifications.markRead(noticeId);
    } on Object catch (error) {
      final text = removeNewlines('$error');
      addNotice(icon: Icons.close, title: '没成功', content: text);
      addLog(.warning, '通知处理失败：$text', tag: 'Notify');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }
}

class _NoticeActionError implements Exception {
  const _NoticeActionError(this.message);

  final String message;

  @override
  String toString() => message;
}
