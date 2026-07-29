import 'package:copper_launcher/core/app_config.dart';
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
  final String label;
  final List<RailItem> items;

  const RailSection({required this.label, required this.items});
}

///与AppShell高度耦合，本质就是它的附属组件
class NavigationRail extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  final String currentRoute;

  final String currentRootRoute;
  final List<RailSection> sections;

  final void Function(String route, Object arg) onNavigate;

  final double width;
  final double collapseWidth;

  const NavigationRail({
    super.key,
    required this.navigatorKey,
    required this.currentRoute,

    required this.currentRootRoute,
    required this.sections,
    required this.onNavigate,

    this.width = 140,
    this.collapseWidth = 56,
  });

  @override
  State<StatefulWidget> createState() => NavigationRailState();
}

class NavigationRailState extends State<NavigationRail> {
  late final ScrollController controller;

  bool get canPop => widget.navigatorKey.currentState?.canPop() ?? false;

  bool collapse = false;

  bool showTopFade = false;
  bool showBottomFade = true;

  @override
  void initState() {
    super.initState();
    controller = ScrollController()
      ..addListener(() {
        if (controller.offset == 0.0) {
          if (showTopFade) {
            setState(() {
              showTopFade = false;
            });
          }
        } else {
          if (!showTopFade) {
            setState(() {
              showTopFade = true;
            });
          }
        }

        if (controller.offset == controller.position.maxScrollExtent) {
          if (showBottomFade) {
            setState(() {
              showBottomFade = false;
            });
          }
        } else {
          setState(() {
            if (!showBottomFade) {
              setState(() {
                showBottomFade = true;
              });
            }
          });
        }
      });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // ── Logo + 拖拽区 ──
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
          Icon(Icons.arrow_back, color: colors.textSecondary),
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

  // ── 分组 + 条目（可滚动） ──
  Widget _buildMenuView() {
    final colors = Theme.of(context).extension<AppColors>()!;

    Widget child = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 0),
      controller: controller,
      child: _buildRootRouteView(),
    );

    child = Stack(
      children: [
        child,
        //view边缘渐变
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: showTopFade ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentGeometry.topCenter,
                  end: AlignmentGeometry.bottomCenter,
                  colors: [
                    colors.cardBackground,
                    colors.cardBackground.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: showBottomFade ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentGeometry.bottomCenter,
                  end: AlignmentGeometry.topCenter,
                  colors: [
                    colors.cardBackground,
                    colors.cardBackground.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (isDesktop) {
      child = DesktopScrollViewContainer(controller: controller, child: child);
    }

    return child;
  }

  Widget _buildRootRouteView() {
    final sections = widget.sections;
    final currentRoute = widget.currentRootRoute;
    final onNavigate = widget.onNavigate;

    List<Widget> buildSection(RailSection section) {
      return [
        _SectionHeader(label: section.label, collapse: collapse),
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
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final section in sections) ...buildSection(section)],
    );

    return child;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
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
            Padding(
              padding: EdgeInsetsGeometry.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                crossAxisAlignment: .end,
                children: [
                  Expanded(
                    child: Text(
                      config.version,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  ReboundButton(
                    onTap: () => setState(() {
                      collapse = !collapse;
                    }),
                    child: AnimatedRotation(
                      turns: collapse ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.ease,
                      child: Icon(Icons.keyboard_arrow_right),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组标题
class _SectionHeader extends StatelessWidget {
  final String label;

  final bool collapse;

  const _SectionHeader({required this.label, required this.collapse});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
      padding: collapse
          ? const EdgeInsets.fromLTRB(6, 0, 0, 2)
          : const EdgeInsets.fromLTRB(2, 2, 0, 0),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colors.textHint,
          letterSpacing: 1.2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
