import 'dart:io';

import 'package:copperlauncher_main/ui/feature/images.dart';
import 'package:copperlauncher_main/ui/util/animation/animated_opacity_size.dart';
import 'package:copperlauncher_main/ui/util/widget/desktop_scroll_view.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
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

/// 左侧导航栏。
///
/// 参考图风格的垂直导航：分组标题 + 带编号/图标的条目。
/// 选中态用 [AppColors.interactive] 做背景高亮。
class NavigationRail extends StatefulWidget {
  final String currentRoute;

  //主路由
  ///主要为了标记跟路由
  final String currentRootRoute;
  final List<RailSection> sections;
  final void Function(String route, Object arg) onNavigate;

  //子路由
  final List<SubRailSection> subSections;
  final void Function(String? route, Object? arg) onSubNavigate;

  final double width;
  final double collapseWidth;

  const NavigationRail({
    super.key,
    required this.currentRoute,

    required this.currentRootRoute,
    required this.sections,
    required this.onNavigate,

    required this.subSections,
    required this.onSubNavigate,

    this.width = 148,
    this.collapseWidth = 64,
  });

  @override
  State<StatefulWidget> createState() => NavigationRailState();
}

class NavigationRailState extends State<NavigationRail> {
  late final ScrollController controller;

  bool collapse = false;

  bool showTopFade = false;
  bool showBottomFade = true;

  @override
  void initState() {
    super.initState();
    controller =
        ScrollController()..addListener(() {
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
  void didUpdateWidget(covariant NavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subSections.isNotEmpty && oldWidget.subSections.isEmpty) {
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
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
      children: [
        Positioned.fill(
          child: GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
          alignment: Alignment.centerLeft,
          height: 40,
          margin:
              collapse
                  ? const EdgeInsets.only(left: 20)
                  : const EdgeInsets.only(left: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(Images.copper, width: 24, height: 24),
              SizedBox(width: 8),

              Expanded(
                child: Text(
                  'Copper',
                  style: textTheme.titleLarge?.copyWith(
                    color: colors.interactive,
                    fontWeight: FontWeight.w900,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 分组 + 条目（可滚动） ──
  Widget _buildMenuView() {
    final colors = Theme.of(context).extension<AppColors>()!;

    Widget child = ListView(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 0),
      shrinkWrap: true,
      controller: controller,
      children: [_buildSubRouteView(), _buildRootRouteView()],
    );
    //给view加边缘渐变
    child = Stack(
      children: [
        child,
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

    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    if (isDesktop) {
      child = DesktopScrollViewContainer(controller: controller, child: child);
    }

    return child;
  }

  Widget _buildRootRouteView() {
    final colors = AppColors.of(context);
    final sections = widget.sections;
    final currentRoute = widget.currentRootRoute;
    final onNavigate = widget.onNavigate;

    List<Widget> buildSection(RailSection section) {
      return [
        _SectionHeader(label: section.label, collapse: collapse),
        ...section.items.map<Widget>(
          (item) => _RailTile(
            item: item,
            selected: currentRoute == item.route,
            onTap: () {
              item.onTap?.call();
              onNavigate(item.route, {'lead': item.label});
            },
          ),
        ),
      ];
    }

    Widget child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final section in sections) ...buildSection(section)],
    );

    child = Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.ease,
              color:
                  widget.subSections.isEmpty
                      ? colors.cardBackground.withAlpha(0)
                      : colors.cardBackground.withAlpha(210),
            ),
          ),
        ),
      ],
    );

    return child;
  }

  Widget _buildSubRouteView() {
    final colors = AppColors.of(context);

    final sections = widget.subSections;

    final currentRoute = widget.currentRoute;

    final onNavigate = widget.onSubNavigate;

    List<Widget> buildSection(SubRailSection section) {
      return [
        _SectionHeader(label: section.label, collapse: collapse),
        ...section.items.map<Widget>(
          (item) => _SubRailTile(
            item: item,
            selected: item.selected(currentRoute),
            onTap: () {
              item.onTap?.call();
              onNavigate(item.route, {'lead': item.label});
            },
          ),
        ),
      ];
    }

    Widget child = Column(
      key: ValueKey(currentRoute),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...buildSection(section),
        SizedBox(height: 4),
        Divider(color: colors.border, indent: 12, endIndent: 12, thickness: 2),
      ],
    );

    child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        final opacity = CurvedAnimation(
          parent: animation,
          curve: Interval(0.4, 1.0),
        );

        final position = Tween<Offset>(
          begin:
              animation.isForwardOrCompleted
                  ? Offset(1.0, 0.0)
                  : Offset(-1.0, 0.0),
          end: Offset(0.0, 0.0),
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));

        return FadeTransition(
          opacity: opacity,
          child: SlideTransition(position: position, child: child),
        );
      },
      layoutBuilder: (c, ch) {
        return Stack(children: [...ch, if (c != null) c]);
      },
      child: child,
    );

    return AnimatedOpacitySize(
      duration: const Duration(milliseconds: 300),
      alignment: Alignment.topCenter,
      child: widget.subSections.isEmpty ? null : child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
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
            SizedBox(height: 4),
            Row(
              children: [
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'v0.0.1a',
                    style: textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                  ),
                ),
                AnimatedRotation(
                  turns: collapse ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.ease,
                  child: ReboundButton(
                    padding: const EdgeInsets.all(4),
                    margin: const EdgeInsets.all(0),
                    child: Icon(Icons.keyboard_arrow_right),
                    onTap:
                        () => setState(() {
                          collapse = !collapse;
                        }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组标题（不可点击）。
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
      padding:
          collapse
              ? const EdgeInsets.fromLTRB(10, 8, 0, 8)
              : const EdgeInsets.fromLTRB(4, 12, 0, 4),
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

/// 单个导航条目（可点击，有选中态）。
class _RailTile extends StatefulWidget {
  final RailItem item;
  final bool selected;
  final VoidCallback onTap;

  const _RailTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_RailTile> createState() => _RailTileState();
}

class _RailTileState extends State<_RailTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    if (widget.selected) {
      _controller.animateTo(1.0);
    }
  }

  @override
  void didUpdateWidget(covariant _RailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      widget.selected ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final bgColor = ColorTween(
          begin: Colors.transparent,
          end: c.interactive.withAlpha(30),
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

        final textColor = ColorTween(
          begin: c.textPrimary,
          end: c.interactive,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

        final indicatorColor = ColorTween(
          begin: Colors.transparent,
          end: c.interactive,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              height: 40,
              duration: const Duration(milliseconds: 300),
              curve: Curves.ease,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color:
                    _hovering && !widget.selected
                        ? c.interactive.withAlpha(15)
                        : bgColor.value,
              ),

              child: Row(
                children: [
                  // 选中指示条
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    curve: Curves.ease,
                    width: 3,
                    height: widget.selected ? 20 : 0,
                    margin: const EdgeInsets.only(left: 0),
                    decoration: BoxDecoration(
                      color: indicatorColor.value,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 图标
                  Icon(widget.item.icon, color: textColor.value),
                  const SizedBox(width: 8),
                  // 标签
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: t.titleMedium?.copyWith(
                        color: textColor.value,
                        fontWeight:
                            widget.selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

//todo 这里用ReboundButton替代，但整体不变
//子路由，赋予更多自由度，但是总体保持一致

/// 子路由有两种形式
/// - [route]纯粹的路由转换
/// - [onTap]控制页面内的参数变化来改变页面内容
class SubRailItem<T> {
  final String label;
  final IconData icon;
  final String? route;
  final VoidCallback? onTap;

  ///决定触发选择效果的条件，由对应的路由页提供
  final bool Function(String? route) selected;

  const SubRailItem({
    required this.label,
    required this.icon,
    this.route,
    required this.selected,
    this.onTap,
  });
}

class SubRailSection<T> {
  final String label;
  final List<SubRailItem<T>> items;

  const SubRailSection({required this.label, required this.items});
}

class _SubRailTile extends StatefulWidget {
  final SubRailItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SubRailTile({
    required this.item,
    required this.onTap,
    required this.selected,
  });

  @override
  State<StatefulWidget> createState() => _SubRailTileState();
}

class _SubRailTileState extends State<_SubRailTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    if (widget.selected) {
      _controller.animateTo(1.0);
    }
  }

  @override
  void didUpdateWidget(covariant _SubRailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      widget.selected ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final bgColor = ColorTween(
          begin: Colors.transparent,
          end: c.interactive.withAlpha(30),
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

        final textColor = ColorTween(
          begin: c.textPrimary,
          end: c.interactive,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

        final indicatorColor = ColorTween(
          begin: Colors.transparent,
          end: c.interactive,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              height: 40,
              duration: const Duration(milliseconds: 300),
              curve: Curves.ease,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color:
                    _hovering && !widget.selected
                        ? c.interactive.withAlpha(15)
                        : bgColor.value,
              ),

              child: Row(
                children: [
                  // 选中指示条
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    curve: Curves.ease,
                    width: 3,
                    height: widget.selected ? 20 : 0,
                    margin: const EdgeInsets.only(left: 0),
                    decoration: BoxDecoration(
                      color: indicatorColor.value,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 图标
                  Icon(widget.item.icon, color: textColor.value),
                  const SizedBox(width: 8),
                  // 标签
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: t.titleMedium?.copyWith(
                        color: textColor.value,
                        fontWeight:
                            widget.selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
