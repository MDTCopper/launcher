import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/navigation_collapse_button.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/util/switcher_builder.dart';
import 'package:copper_launcher/ui/util/widget/desktop_scroll_view.dart';
import 'package:copper_launcher/ui/util/widget/feature_button.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:copper_launcher/util/io/os.dart';
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
  final void Function(String route, Object arg) onNavigate;
  final String currentRoute;
  final String currentRootRoute;

  final List<RailSection> sections;
  final List<RailItem> itemsAtBottom;

  final double width;
  final double collapseWidth;

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
  Widget _buildLogo() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
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
            transitionBuilder: SwitcherBuilders.slideOver(),
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: .centerLeft,
                children: [...previousChildren, ?currentChild],
              );
            },
            child: canPop
                ? _buildBackButton()
                : Row(
                    children: [
                      AnimatedSize(
                        duration: animationDuration,
                        curve: Curves.ease,
                        child: SizedBox(width: collapse ? 4 : 0),
                      ),
                      Image.asset(Images.copper, width: 24, height: 24),
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
      pressedScale: collapse ? 0.8 : 0.9,
      borderRadius: BorderRadius.circular(4),
      backgroundColor: Colors.transparent,
      onTap: () {
        if (canPop) {
          widget.navigatorKey.currentState?.pop();
        }
      },
      child: Row(
        crossAxisAlignment: .start,
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
              onNavigate(item.route, {'lead': item.label});
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
      padding: EdgeInsets.fromLTRB(8, 0, 8, 0),
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
                onNavigate(item.route, {'lead': item.label});
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCollapseField() {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        crossAxisAlignment: .end,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                config.version,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          NavigationCollapseButton(
            collapse: collapse,
            onTap: () {
              setState(() {
                collapse = !collapse;
              });
            },
          ),
        ],
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
        color: colors.cardBackground,
        child: Column(
          children: [
            _buildLogo(),
            Expanded(child: _buildMenuView()),
            _buildCollapseField(),
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
