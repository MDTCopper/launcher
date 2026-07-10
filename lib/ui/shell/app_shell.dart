import 'dart:io';

import 'package:copperlauncher_main/ui/util/animation/animated_opacity_size.dart';
import 'package:copperlauncher_main/ui/util/route/page_key_provider.dart';
import 'package:copperlauncher_main/ui/util/switcher_transition_builder.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart' hide NavigationRail;
import 'package:go_router/go_router.dart';
import 'package:line_icons/line_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';
import '../util/dialog/drag_file_field.dart';
import '../util/framework/info_drawer.dart';
import '../util/info/task_drawer_opener.dart';
import '../util/widget/feature_button.dart';
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
  static const _rootSections = [
    RailSection(
      label: '概览',
      items: [
        RailItem(label: '启动', icon: Icons.play_arrow_outlined, route: '/'),
      ],
    ),

    RailSection(
      label: '资源',
      items: [
        RailItem(
          label: 'Mindustry',
          icon: Icons.view_in_ar,
          route: '/mindustry_download',
        ),
        RailItem(label: '模组', icon: LineIcons.puzzlePiece, route: '/mod_view'),
        RailItem(
          label: '整合包',
          icon: Icons.token_outlined,
          route: '/package_view',
        ),
        RailItem(
          label: '蓝图',
          icon: Icons.paste_outlined,
          route: '/blueprint_view',
        ),
        RailItem(label: '地图', icon: Icons.map_outlined, route: '/map_view'),
      ],
    ),
    RailSection(
      label: '设置',
      items: [
        RailItem(
          label: '启动项',
          icon: Icons.rocket_launch_outlined,
          route: '/launch_setting',
        ),
        RailItem(label: '游戏内设置', icon: Icons.settings, route: '/game_setting'),
        RailItem(
          label: '个性化',
          icon: Icons.format_paint_outlined,
          route: '/personalized_setting',
        ),
        RailItem(label: '其他', icon: Icons.more_horiz, route: '/other_setting'),
      ],
    ),
    RailSection(
      label: '更多',
      items: [
        RailItem(label: '神秘小工具', icon: Icons.widgets_outlined, route: '/tool'),
        RailItem(label: '帮助', icon: Icons.help_outline, route: '/help'),
        RailItem(label: '关于', icon: Icons.info_outline, route: '/about'),
      ],
    ),
  ];

  //导航栏根路由切换
  void _onRootNavigate(String route, Object? arg) {
    if (route == _currentRootRoute) return;

    _currentRootRoute = route;
    // 清空子路由栈，回到根页面
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      route,
      arguments: arg,
      (_) => false,
    );
  }

  // ── 临时子路由配置 ──

  late final routeWatcher = _RouteWatcher(
    _onRouteChanged,
    onPop: () {},
    onPush: () {},
  );

  bool _showSubRoute = false;

  //用key将子路由绑定到一起，这样就不需要每个子页面的每个路由都注册一次
  //todo 到时候使用[currentSubNavigator]
  String _subRouteBindKey = '';

  //临时子路由列表，子路由切换页面用switcher
  //或进行路由，需要在路由前标记路由key
  static final Map<String, List<SubRailSection>> _subSections = {};

  static final List<String> _subNavigatorKeyStack = [];

  //显示最后的导航器的key
  static String get currentSubNavigatorKey =>
      _subNavigatorKeyStack.lastWhere((it) => it.isNotEmpty, orElse: () => '');

  static List<SubRailSection> get currentSubNavigator =>
      _subSections[currentSubNavigatorKey] ?? [];

  void registerNavigator(String key, List<SubRailSection> sections) {
    //将导航器压入栈内
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _subNavigatorKeyStack.add(key);
        _subSections[key] = sections;
      });
    });
  }

  void unregisterNavigator(String key) {
    if (currentSubNavigatorKey == key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _subNavigatorKeyStack.remove(currentSubNavigatorKey);
        });
      });
    }
  }

  ///////////////

  //如果子页面有路由选项,子路由注册后刷新一遍导航栏
  void registerSubRoute(String key, List<SubRailSection> sections) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _subRouteBindKey = key;
        _subSections[key] = sections;
      });
    });
  }

  void registerSubRouteKey(String key) {
    setState(() {
      _subRouteBindKey = key;
    });
  }

  //子页路由回调，主要用于子页路由更新时更新导航栏状态和进行子路由
  void _onSubNavigate(String? route, Object? arg) {
    if (route != null) {
      _navigatorKey.currentState?.pushReplacementNamed(route, arguments: arg);
    } else {
      setState(() {});
    }
  }

  // ── 路由监听（更新导航栏高亮和面包屑） ──

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
      final display = title != null ? '$lead › $title' : lead;

      _pageName = display;

      final isRoot = !_navigatorKey.currentState!.canPop();

      if (isRoot) {
        _currentRootRoute = name;
        _showSubRoute = false;
        _subNavigatorKeyStack.clear();
      } else {
        _showSubRoute = true;
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
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.cardBackground.withAlpha(120),
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
              SizedBox(width: 4),
              AnimatedOpacitySize(
                duration: const Duration(milliseconds: 300),
                child: canPop
                    ? ReboundButton(
                        child: Icon(Icons.keyboard_arrow_left),
                        onTap: () {
                          if (canPop) {
                            _navigatorKey.currentState?.pop();
                          }
                        },
                      )
                    : null,
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

              // Icon(Icons.person_outlined),
              // SizedBox(width: 4),
              // Text('rainfall'),
              // SizedBox(width: 8),
              // Container(
              //   width: 16,
              //   height: 16,
              //   decoration: BoxDecoration(
              //     color: Colors.green,
              //     border: Border.all(width: 1,color: colors.barrier),
              //   ),
              // ),
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

  //todo安卓端退出程序
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    Widget shell = Scaffold(
      endDrawer: Drawer(
        backgroundColor: colors.interactive,
        width: MediaQuery.of(context).size.width * 0.40,
        elevation: 2,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InfoList(),
      ),
      body: Row(
        children: [
          // ── 左侧导航（含 Logo + 拖拽） ──
          NavigationRail(
            currentRoute: _currentRoute,
            currentRootRoute: _currentRootRoute,

            sections: _rootSections,
            onNavigate: _onRootNavigate,

            subSections: _showSubRoute
                ? _subSections[_subRouteBindKey] ?? []
                : [],
            onSubNavigate: _onSubNavigate,
            subNavigator: SizedBox(),
          ),

          VerticalDivider(width: 1, thickness: 1, color: colors.border),

          // ── 右侧内容区 ──
          Expanded(
            child: Stack(
              fit: StackFit.loose,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.6, -1.8),
                      radius: 1.0,
                      colors: [
                        colors.interactive.withAlpha(60),
                        colors.success.withAlpha(0),
                      ],
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.0, -1.6),
                      radius: 0.8,
                      colors: [
                        colors.interactive.withAlpha(60),
                        colors.error.withAlpha(0),
                      ],
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.4, -1.4),
                      radius: 0.6,
                      colors: [
                        colors.interactive.withAlpha(60),
                        colors.warning.withAlpha(0),
                      ],
                    ),
                  ),
                ),
                Column(
                  children: [
                    _buildTopbar(),
                    Expanded(child: _buildNavigator()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isDesktop) {
      return DragFileField(onDragDone: _handleDragFile, child: shell);
    }
    // if (true || Platform.isAndroid) {
    //   shell = PopScope(
    //     canPop: false,
    //     onPopInvokedWithResult: (didPop, _) {
    //
    //       if (didPop) return;
    //       print('pop2');
    //
    //       final now = DateTime.now();
    //
    //       if (_lastPopTime == null ||
    //           _lastPopTime!.difference(now) > const Duration(seconds: 1)) {
    //         _lastPopTime = now;
    //         addNotice(content: '再按一次返回');
    //       } else {
    //         _navigatorKey.currentState?.pop();
    //       }
    //     },
    //     child: shell,
    //   );
    // }
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

  void buildGoRoute() {
    GoRouter(
      routes: [
        ShellRoute(
          builder: (_, state, child) {
            state.uri.pathSegments;
            return SizedBox();
          },
          routes: [
            //路由
            GoRoute(
              path: 'setting',

              builder: (context, state) {
                state.name;
                return SizedBox();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════
// 路由监听器
// ════════════════════════════════════════════

typedef _RouteCallback = void Function(String? name, dynamic args);

class _RouteWatcher extends RouteObserver {
  final _RouteCallback onChanged;
  final VoidCallback onPop;
  final VoidCallback onPush;

  _RouteWatcher(this.onChanged, {required this.onPop, required this.onPush});

  @override
  void didPush(Route route, Route? previousRoute) {
    onPush();
    _notify(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (newRoute != null) _notify(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    onPop();
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
