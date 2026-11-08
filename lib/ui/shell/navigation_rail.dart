import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/util/animation/switcher_builder.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';

/// 导航栏中的一个条目
class RailItem {
  final String label;
  final IconData icon;
  final String route;
  final VoidCallback? onTap;

  const RailItem({
    required this.label,
    required this.icon,
    required this.route,
    this.onTap,
  });
}

class RailSection {
  final String? label;
  final List<RailItem> items;
  const RailSection({this.label, required this.items});
}

///与AppShell高度耦合，本质就是它的附属组件
class NavigationRail extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final void Function(String route) onNavigate;
  final String currentRoute;
  final String currentRootRoute;

  final List<RailSection> sections;
  final List<RailItem> itemsAtBottom;

  final double width;
  final double collapseWidth;

  /// 新外壳试点：把「收纳菜单」按钮放进侧栏底部（顶部不再放）
  final bool showCollapseButton;

  /// 新外壳试点：侧栏底色（null = 沿用旧卡面色）
  final Color? backgroundColor;

  const NavigationRail({
    super.key,

    required this.navigatorKey,
    required this.currentRoute,
    required this.currentRootRoute,
    required this.onNavigate,

    required this.sections,
    this.itemsAtBottom = const [],

    this.width = 140,
    this.collapseWidth = 56,
    this.showCollapseButton = false,
    this.backgroundColor,
  });

  @override
  State<StatefulWidget> createState() => NavigationRailState();
}

class NavigationRailState extends State<NavigationRail> {
  bool get canPop => widget.navigatorKey.currentState?.canPop() ?? false;

  bool get collapse => config.setting.personalizationOptions.navigationCollapse;

  set collapse(bool value) {
    config.setting.personalizationOptions.navigationCollapse = value;
    config.save();
  }

  // ── Logo , 拖拽区 , 返回按钮 ──
  Widget _buildTop() {
    return Stack(
      alignment: .centerLeft,
      children: [
        Positioned.fill(
          child: GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
          ),
        ),
        Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: 12),
          alignment: .centerLeft,
          child: AnimatedSwitcher(
            duration: animationDuration,
            transitionBuilder: SwitcherBuilders.slideOver(fix: true),
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: .centerLeft,
                children: [...previousChildren, ?currentChild],
              );
            },
            child: canPop ? _buildBackButton() : _buildLogo(),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final theme = config.setting.personalizationOptions.themeColor;
    final icon = switch (theme) {
      ThemeColor.copper => Images.copper,
      ThemeColor.titanium => Images.titanium,
      ThemeColor.thorium => Images.thorium,
      ThemeColor.plastanium => Images.plastanium,
    };
    return Row(
      key: ValueKey('logo'),
      children: [
        AnimatedSize(
          duration: animationDuration,
          curve: Curves.ease,
          child: SizedBox(width: collapse ? 4 : 0),
        ),
        AnimatedSwitcher(
          duration: animationDuration,
          transitionBuilder: SwitcherBuilders.slideOver(),
          child: Image.asset(icon, key: ValueKey(icon), width: 24, height: 24),
        ),
        Expanded(
          child: AnimatedOpacity(
            duration: animationDuration,
            curve: Curves.ease,
            opacity: collapse ? 0.0 : 1.0,
            child: Padding(
              padding: EdgeInsetsGeometry.only(left: 8),
              child: Text(
                'Copper',
                style: textTheme.titleLarge?.copyWith(
                  color: colors.interactive,
                  fontWeight: FontWeight.w900,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackButton() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ReboundButton(
      key: ValueKey('backButton'),
      pressedScale: collapse ? 0.8 : 0.9,
      borderRadius: BorderRadius.circular(4),
      backgroundColor: Colors.transparent,
      onTap: () {
        if (canPop) {
          widget.navigatorKey.currentState?.pop();
        }
      },
      child: Row(
        children: [
          Icon(Icons.arrow_back, color: colors.itemSecondary),
          Expanded(
            child: AnimatedOpacity(
              duration: animationDuration,
              curve: Curves.ease,
              opacity: collapse ? 0.0 : 1.0,
              child: Padding(
                padding: EdgeInsetsGeometry.only(left: 8),
                child: Text(
                  '返回',
                  style: textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 导航视图  ──
  Widget _buildMenuView() {
    final colors = Theme.of(context).extension<AppColors>()!;

    Widget child = Stack(
      children: [
        Column(
          mainAxisAlignment: .end,
          children: [
            Expanded(child: _buildRouteView()),
            Divider(color: colors.border, indent: 16, endIndent: 16),
            _buildBottomItems(),
          ],
        ),
        //禁用遮罩，点击可返回主页
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !canPop,
            child: GestureDetector(
              onTap: () {
                if (canPop) {
                  widget.navigatorKey.currentState?.popUntil(
                    (route) => route.isFirst,
                  );
                }
              },
              child: AnimatedContainer(
                duration: animationDuration,
                color: canPop
                    ? colors.cardBackground.withAlpha(185)
                    : colors.cardBackground.withAlpha(0),
              ),
            ),
          ),
        ),
      ],
    );

    return child;
  }

  Widget _buildRouteView() {
    final sections = widget.sections;
    final currentRoute = widget.currentRootRoute;
    final onNavigate = widget.onNavigate;

    List<Widget> buildSection(RailSection section) {
      return [
        _SectionHeader(section: section, collapse: collapse),
        ...section.items.map<Widget>(
          (item) => NavigationTile(
            icon: Icon(item.icon),
            content: item.label,
            collapse: collapse,
            selected: currentRoute == item.route,
            hintPosition: .right,
            onTap: () {
              item.onTap?.call();
              onNavigate(item.route);
            },
          ),
        ),
      ];
    }

    Widget child = Column(
      spacing: 4,
      crossAxisAlignment: .start,
      children: [for (final section in sections) ...buildSection(section)],
    );

    child = CopperSingleChildScrollView(
      showScrollbar: false,
      padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: child,
    );

    return child;
  }

  Widget _buildBottomItems() {
    final currentRoute = widget.currentRootRoute;
    final onNavigate = widget.onNavigate;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        spacing: 4,
        crossAxisAlignment: .start,
        children: [
          for (final item in widget.itemsAtBottom)
            NavigationTile(
              icon: Icon(item.icon),
              content: item.label,
              collapse: collapse,
              selected: currentRoute == item.route,
              hintPosition: .right,
              onTap: () {
                item.onTap?.call();
                onNavigate(item.route);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildVersionTile() {
    final theme = Theme.of(context);

    return Container(
      alignment: .centerLeft,
      padding: EdgeInsets.only(left: 4, bottom: 3),
      child: HintLayer(
        hint: 'build $appBuildNumber at $appBuildTime',
        child: Text(
          appVersion,
          maxLines: 1,
          overflow: .ellipsis,
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }

  /// 新外壳：收纳 / 展开主菜单（放在侧栏底部，替代原来顶栏里那颗）
  Widget _buildCollapseRow() {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: HintLayer(
        hint: collapse ? '展开主菜单' : '收纳主菜单',
        preferPosition: .right,
        child: ReboundButton(
          backgroundColor: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => collapse = !collapse),
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisAlignment: collapse
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: collapse ? 0 : 4),
                  child: Icon(
                    collapse ? Icons.chevron_right : Icons.chevron_left,
                    size: 18,
                    color: colors.itemSecondary,
                  ),
                ),
                if (!collapse)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '收纳菜单',
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.itemSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
      width: collapse ? widget.collapseWidth : widget.width,
      child: ColoredBox(
        color: widget.backgroundColor ?? colors.cardBackground,
        child: Column(
          children: [
            _buildTop(),
            Expanded(child: _buildMenuView()),
            if (widget.showCollapseButton) _buildCollapseRow(),
            _buildVersionTile(),
          ],
        ),
      ),
    );
  }
}

/// 分组标题
class _SectionHeader extends StatelessWidget {
  final RailSection section;
  final bool collapse;

  const _SectionHeader({required this.section, required this.collapse});

  @override
  Widget build(BuildContext context) {
    if (section.label == null) {
      return Divider(
        height: 8,
        color: AppColors.of(context).border,
        indent: 8,
        endIndent: 8,
      );
    } else {
      final colors = AppColors.of(context);
      return AnimatedPadding(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
        padding: collapse
            ? const EdgeInsets.fromLTRB(7, 0, 0, 4)
            : const EdgeInsets.fromLTRB(2, 4, 0, 0),
        child: Text(
          section.label!,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.itemHint,
            letterSpacing: 1.2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
  }
}
