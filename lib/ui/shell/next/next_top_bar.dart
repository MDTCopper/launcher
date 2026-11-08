import 'package:copper_launcher/ui/components/avatar/user_avatar.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

/// 新外壳 · 顶栏（试点 A，2026-11-08）
///
/// 布局照现有 App 顶栏（40 高、可拖窗、账户 → 面包屑 → 任务 → 副菜单 → 窗控），
/// 皮肤换成设计层：半透明卡面 + 底边线、面包屑用 `TemplateBreadcrumbBar`、
/// 折叠按钮与账户卡片用 `TemplateSkin` 的中性色 / 强调色。
///
/// 行为全部由外部传入（点回调），外壳状态、路由跳转仍留在 `AppShell` 里。
class NextTopBar extends StatelessWidget {
  const NextTopBar({
    super.key,
    required this.crumbs,
    required this.subNavigationCollapsed,
    required this.onToggleSubNavigation,
    required this.accountName,
    required this.avatarUrl,
    required this.unread,
    required this.onAccountTap,
    required this.taskOpener,
    this.windowControls,
    this.onDragStart,
  });

  /// 面包屑（越靠右越当前）
  final List<TemplateBreadcrumb> crumbs;

  final bool subNavigationCollapsed;
  final VoidCallback onToggleSubNavigation;

  final String accountName;
  final String? avatarUrl;
  final int unread;
  final VoidCallback onAccountTap;

  /// 右侧「任务 / 日志」抽屉入口（复用现有组件）
  final Widget taskOpener;

  /// 桌面端窗控（最小化 / 关闭），移动端传 null
  final Widget? windowControls;

  /// 拖动顶栏移动窗口（桌面端）
  final VoidCallback? onDragStart;

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);
    // 半透明卡面：让背景光效透出来，和旧外壳一致
    final barColor = skin.surface.withAlpha(70);

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
                skin: skin,
                name: accountName,
                avatarUrl: avatarUrl,
                unread: unread,
                onTap: onAccountTap,
              ),
              const SizedBox(width: 8),
              // 面包屑只占内容宽度，右侧空白留给拖窗；同时整段都能起手拖窗口
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: onDragStart == null
                      ? null
                      : (_) => onDragStart!(),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TemplateBreadcrumbBar(
                      skin: skin,
                      crumbs: crumbs,
                      fadeColor: barColor,
                    ),
                  ),
                ),
              ),
              taskOpener,
              const SizedBox(width: 4),
              _TopIconButton(
                skin: skin,
                icon: Symbols.dock_to_left,
                hint: subNavigationCollapsed ? '点击展开副菜单' : '点击收纳副菜单',
                active: !subNavigationCollapsed,
                fillAlignment: const Alignment(0.60, -0.08),
                onTap: onToggleSubNavigation,
              ),
              if (windowControls != null) ...[
                const SizedBox(width: 4),
                windowControls!,
              ],
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }
}

/// 顶栏的小图标按钮：24×24，悬停出底，激活时右侧（或左侧）亮一条提示块
class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.skin,
    required this.icon,
    required this.hint,
    required this.active,
    required this.fillAlignment,
    required this.onTap,
  });

  final TemplateSkin skin;
  final IconData icon;
  final String hint;
  final bool active;
  final Alignment fillAlignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hint,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 500),
      child: ReboundButton(
        backgroundColor: Colors.transparent,
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            children: [
              // 激活提示块（面板半区）：颜色换成皮肤的强调色
              Positioned.fill(
                child: Align(
                  alignment: fillAlignment,
                  child: FractionallySizedBox(
                    widthFactor: 0.2,
                    heightFactor: 0.72,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: active ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: skin.accent),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Icon(
                  icon,
                  size: 18,
                  color: active ? skin.textPrimary : skin.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 账户入口：头像 + 名字 + 未读角标（点开左抽屉）
class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.skin,
    required this.name,
    required this.avatarUrl,
    required this.unread,
    required this.onTap,
  });

  final TemplateSkin skin;
  final String name;
  final String? avatarUrl;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            color: skin.sunken,
            borderRadius: BorderRadius.circular(TemplateRadius.control),
            border: Border.all(color: skin.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              UserAvatar(
                url: avatarUrl,
                size: 18,
                fallbackIcon: Icons.account_circle_outlined,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TemplateType.caption.copyWith(color: skin.textPrimary),
                ),
              ),
              if (unread > 0)
                TemplateCountBadge(
                  skin: skin,
                  count: unread,
                  tone: TemplateBadgeTone.danger,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
