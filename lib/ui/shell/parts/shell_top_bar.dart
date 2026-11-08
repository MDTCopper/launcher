import 'package:flutter/material.dart';

import 'package:copper_launcher/ui/components/avatar/user_avatar.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

import 'shell_breadcrumb.dart';

/// 外壳顶栏：40 高、可拖窗、账户 → 面包屑 → 任务入口 → 窗控
///
/// 行为全部由外部传入（点回调），外壳状态与路由跳转留在 `AppShell` 里；
/// 配色吃 [AppColors]，跟主题种子色一起变
class ShellTopBar extends StatelessWidget {
  const ShellTopBar({
    super.key,
    required this.crumbs,
    required this.accountName,
    required this.avatarUrl,
    required this.unread,
    required this.onAccountTap,
    required this.taskOpener,
    this.windowControls,
    this.onDragStart,
  });

  /// 面包屑（越靠右越当前）
  final List<ShellBreadcrumb> crumbs;

  final String accountName;
  final String? avatarUrl;
  final int unread;
  final VoidCallback onAccountTap;

  /// 右侧「任务 / 日志」抽屉入口
  final Widget taskOpener;

  /// 桌面端窗控（最小化 / 关闭），移动端传 null
  final Widget? windowControls;

  /// 拖动顶栏移动窗口（桌面端）
  final VoidCallback? onDragStart;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // 半透明卡面：让背景光效透出来
    final barColor = colors.cardBackground.withAlpha(70);

    return Container(
      height: 40,
      decoration: BoxDecoration(color: barColor),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (onDragStart != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => onDragStart!(),
              ),
            ),
          Row(
            children: [
              const SizedBox(width: 8),
              _AccountChip(
                name: accountName,
                avatarUrl: avatarUrl,
                unread: unread,
                onTap: onAccountTap,
              ),
              const SizedBox(width: 8),
              // 面包屑只占内容宽度，右侧空白留给拖窗；整段都能起手拖窗口
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: onDragStart == null
                      ? null
                      : (_) => onDragStart!(),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ShellBreadcrumbBar(
                      crumbs: crumbs,
                      fadeColor: barColor,
                    ),
                  ),
                ),
              ),
              taskOpener,
              const SizedBox(width: 4),
              if (windowControls != null) ...[windowControls!],
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }
}

/// 账户入口：头像 + 名字 + 未读角标（点开左抽屉）
class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.name,
    required this.avatarUrl,
    required this.unread,
    required this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Tooltip(
      message: '账户',
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 500),
      child: ReboundButton(
        backgroundColor: Colors.transparent,
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: colors.lowBackgroundOnCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              UserAvatar(
                url: avatarUrl,
                size: 16,
                fallbackIcon: Icons.account_circle_outlined,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.itemPrimary),
                ),
              ),
              if (unread > 0)
                Container(
                  height: 14,
                  constraints: const BoxConstraints(minWidth: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.error,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
