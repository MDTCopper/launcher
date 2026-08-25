import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/ui/util/switcher_builder.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide NavigationRail;
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../components/colorful_background.dart';
import '../theme/app_colors.dart';
import '../components/overlay_layer/drag_file_field.dart';
import 'drawer/info_drawer.dart';
import '../page_framwork/sub_navigation_state.dart';
import 'drawer/task_drawer_opener.dart';
import '../util/widget/resource_importer.dart';
import '../vars.dart';
import 'navigation_rail.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _navigatorKey = PageKeyProvider.navigatorKey;

  String _currentRoute = '/';
  String _pageName = '';

  // ── 导航配置 ──

  bool get canPop => _navigatorKey.currentState?.canPop() == true;

  String _currentRootRoute = '/';
  static final _sections = [
    RailSection(
      label: '概览',
      items: [
        RailItem(label: '主页', icon: Icons.home_filled, route: '/'),
        RailItem(label: '账户', icon: Icons.person_outline, route: '/user'),
      ],
    ),

    RailSection(
      label: '发现',
      items: [
        RailItem(
          label: 'Mindustry',
          icon: Icons.view_in_ar,
          route: '/mindustry_download',
        ),
        RailItem(
          label: '社区资源',
          icon: Icons.local_fire_department_outlined,
          route: '/community_resources',
        ),
        RailItem(label: '神秘小工具', icon: Icons.build, route: '/tools'),
      ],
    ),
  ];

  static final _items = [
    RailItem(label: '设置', icon: Icons.settings, route: '/setting'),
    if (kDebugMode)
      RailItem(label: '测试页面', icon: Icons.terminal_outlined, route: '/test'),
  ];
  //导航栏根路由切换
  void _onRootNavigate(String route, Object? arg) {
    if (route == _currentRoute) return;

    _currentRootRoute = route;
    // 清空子路由栈，回到根页面
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      route,
      arguments: arg,
      (_) => false,
    );
  }

  late final routeWatcher = _RouteWatcher(_onRouteChanged);

  // ── 路由监听 更新导航栏高亮和面包屑 ──

  void _onRouteChanged(String? name, dynamic args) {
    if (name == null) return;

    _currentRoute = name;

    // 延迟到下一帧，避免在 build 阶段触发 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      String lead = name;
      String? title;
      if (args is Map) {
        lead = args['lead'] ?? lead;
        title = args['title'];
      }
      final display = title != null ? '$lead -> $title' : lead;

      _pageName = display;

      final isRoot = !_navigatorKey.currentState!.canPop();

      if (isRoot) {
        _currentRootRoute = name;
      }

      //无奈之举，在启动时，args肯定是空的，启动页的名字就会变成/
      if (name == '/' && args == null) {
        _pageName = '启动';
      }

      setState(() {});
    });
  }

  void _handleDragFile(DropDoneDetails d) async {
    await showResourceImporter(d.files.map((it) => it.path).toList());
  }

  // ── 构建 ──

  //面包屑
  Widget _buildTopbar() {
    final colors = AppColors.of(context);
    final navigationCollapse =
        config.setting.personalizationOptions.navigationCollapse;

    final isRoot = _currentRoute == _currentRootRoute;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        // 半透明背景，让背景光效透出，形成顶部光渗透效果
        color: colors.cardBackground.withAlpha(70),
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isDesktop)
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (_) => windowManager.startDragging(),
              ),
            ),
          Row(
            children: [
              const SizedBox(width: 4),
              _dockSidebarToggle(
                hint: !navigationCollapse ? '点击收纳主菜单' : '点击展开主菜单',
                icon: Symbols.dock_to_right,
                fillAlignment: Alignment(-0.56, -0.08),
                active: !navigationCollapse,
                onTap: () {
                  setState(() {
                    config.setting.personalizationOptions.navigationCollapse =
                        !navigationCollapse;
                    config.save();
                  });
                },
              ),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: SwitcherBuilders.fadeSlide(Offset(0.0, 1.0)),
                layoutBuilder: (child, children) {
                  return Stack(children: [?child, ...children]);
                },
                child: Padding(
                  key: ValueKey(_pageName),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _pageName,
                    style: Theme.of(context).textTheme.labelMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              Expanded(child: SizedBox()),

              ValueListenableBuilder<bool>(
                valueListenable: subNavigationCollapseNotifier,
                builder: (context, subNavigationCollapse, _) {
                  return _dockSidebarToggle(
                    hint: !subNavigationCollapse ? '点击收纳副菜单' : '点击展开副菜单',
                    icon: Symbols.dock_to_left,
                    fillAlignment: Alignment(0.60, -0.08),
                    active: !subNavigationCollapse,
                    onTap: () =>
                        setSubNavigationCollapse(!subNavigationCollapse),
                  );
                },
              ),

              const TaskDrawerOpener(),

              if (isDesktop) ...[
                const SizedBox(width: 4),
                ReboundButton(
                  backgroundColor: Colors.transparent,
                  onTap: () => windowManager.minimize(),
                  child: Icon(Icons.remove),
                ),
                const SizedBox(width: 2),

                ReboundButton(
                  backgroundColor: Colors.transparent,

                  highlightColor: colors.error.withAlpha(100),
                  hoverColor: colors.error.withAlpha(100),
                  onTap: () => windowManager.close(),
                  child: Icon(Icons.close),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _dockSidebarToggle({
    required IconData icon,
    required String hint,
    required Alignment fillAlignment,
    required bool active,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);

    return HintLayer(
      hint: hint,
      preferPosition: .bottom,
      child: ReboundButton(
        hoverElevation: 0.0,
        backgroundColor: Colors.transparent,
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            children: [
              // 面板半区填充色块（fade 过渡）；宽度/位置由用户微调
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
                        decoration: BoxDecoration(color: colors.interactive),
                      ),
                    ),
                  ),
                ),
              ),

              Positioned.fill(child: Icon(icon, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  //TODO: 安卓端退出程序

  DateTime? _lastPopTime;

  Widget _buildNavigator() {
    Widget child = Navigator(
      key: PageKeyProvider.navigatorKey,
      initialRoute: '/',
      observers: [routeWatcher],
      onGenerateRoute: _buildRoute,
    );
    return child;
  }

  Widget _buildColorfulBackground(Widget child) {
    return ColorfulBackground(child: child);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget shell = Scaffold(
      endDrawer: Drawer(
        backgroundColor: colors.pageBackground.withAlpha(230),
        width: MediaQuery.of(context).size.width * 0.45,
        elevation: 2,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InfoList(),
      ),
      body: Row(
        children: [
          // ── 左侧导航 ──
          NavigationRail(
            navigatorKey: _navigatorKey,
            currentRoute: _currentRoute,
            currentRootRoute: _currentRootRoute,
            sections: _sections,
            itemsAtBottom: _items,

            onNavigate: _onRootNavigate,
          ),

          VerticalDivider(width: 1, thickness: 1, color: colors.border),

          // ── 右侧内容区 ──
          Expanded(
            child: _buildColorfulBackground(
              Column(
                children: [
                  _buildTopbar(),
                  Expanded(child: _buildNavigator()),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isDesktop) {
      return DragFileField(onDragDone: _handleDragFile, child: shell);
    }
    return shell;
  }

  // ── 页面过渡 ──

  PageRouteBuilder _buildRoute(RouteSettings setting) {
    Widget page = routeMap[setting.name] ?? _NotFoundPage();

    return PageRouteBuilder(
      settings: setting,
      pageBuilder: (_, _, _) => page,
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curvedEnter = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.4, 1.0, curve: Curves.easeOutBack),
          reverseCurve: const Interval(0.4, 1.0, curve: Curves.easeIn),
        );

        final curvedExit = CurvedAnimation(
          parent: secondaryAnimation,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
          reverseCurve: const Interval(0.0, 0.6, curve: Curves.easeInBack),
        );
        child = FadeTransition(
          opacity: curvedEnter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.06),
              end: Offset.zero,
            ).animate(curvedEnter),
            child: child,
          ),
        );

        child = SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(0.0, 0.06),
          ).animate(curvedExit),
          child: child,
        );

        child = FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.0).animate(curvedExit),
          child: child,
        );

        return child;
      },
    );
  }
}

// ════════════════════════════════════════════
// 路由监听器
// ════════════════════════════════════════════

typedef _RouteCallback = void Function(String? name, dynamic args);

class _RouteWatcher extends RouteObserver {
  final _RouteCallback onChanged;

  _RouteWatcher(this.onChanged);

  @override
  void didPush(Route route, Route? previousRoute) {
    _notify(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (newRoute != null) _notify(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (previousRoute != null) _notify(previousRoute);
  }

  void _notify(Route route) {
    debugPrint('当前路由 [${route.settings.name} , ${route.settings.arguments}]');
    onChanged(route.settings.name, route.settings.arguments);
  }
}

/// 路由未匹配时的缺省页。
class _NotFoundPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('页面未找到', style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
