import 'package:copper_launcher/domain/mdtbbs/mdtbbs_notification_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
import 'package:flutter/material.dart';

const notificationsPageRouteKey = '/notifications';

/// 账户通知页：好友请求、联机邀请与系统提示都堆在这里
///
/// 数据来自 [MdtbbsNotificationService]（30 秒轮询；之后换成实时事件流时页面不用改）
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  MdtbbsNotificationService get _notifications =>
      MdtbbsNotificationService.instance;

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
}
