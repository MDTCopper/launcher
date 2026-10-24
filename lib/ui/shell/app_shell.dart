import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_notification_service.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/pages/cloud/version_cloud_save_page.dart';
import 'package:copper_launcher/ui/pages/friends/friends_page.dart';
import 'package:copper_launcher/ui/pages/notifications/notifications_page.dart';
import 'package:copper_launcher/ui/pages/online/online_page.dart';
import 'package:copper_launcher/ui/pages/design/design_system_page.dart';
import 'package:copper_launcher/ui/shell/parts/window_close_button.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/ui/util/animation/switcher_builder.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/android_host.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide NavigationRail;
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:window_manager/window_manager.dart';
import 'parts/colorful_background.dart';
import '../theme/app_colors.dart';
import '../theme/design_system.dart';
import '../components/overlay_layer/drag_file_field.dart';
import 'drawer/info_drawer.dart';
import '../page_framwork/sub_navigation_state.dart';
import 'parts/task_drawer_opener.dart';
import '../dialog/resource_importer.dart';
import '../vars.dart';
import 'navigation_rail.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _navigatorKey = PageKeyProvider.navigatorKey;

  /// 账户抽屉要从顶栏打开，拿 Scaffold 的 state
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String _currentRoute = '/';
  String _pageName = '';

  // ── 导航配置 ──

  bool get canPop => _navigatorKey.currentState?.canPop() == true;

  /// 返回键连按的判定窗口：两下之间超过它就算新的一轮（重新提醒）
  static const _backTwiceWindow = Duration(seconds: 2);

  /// 上一次按返回键的时刻；null = 还没按过
  DateTime? _lastBackPressedAt;

  String _currentRootRoute = '/';
  static final _sections = [
    RailSection(
      label: '概览',
      items: [
        RailItem(label: '主页', icon: Icons.home_filled, route: '/'),
        RailItem(
          label: '账户',
          icon: Icons.account_circle_outlined,
          route: accountPageRouteKey,
        ),
        RailItem(
          label: '联机',
          icon: Icons.public_outlined,
          route: onlinePageRouteKey,
        ),
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
        if (kDebugMode)
          RailItem(label: '神秘小工具', icon: Icons.auto_fix_high, route: '/tools'),
        if (kDebugMode)
          RailItem(
            label: '设计规范',
            icon: Icons.design_services_outlined,
            route: designSystemPageRouteKey,
          ),
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

  // ── 系统返回键 ──

  /// 安卓返回键与全面屏手势都走这里
  ///
  /// 子路由先返回一层；到了底层路由要**连按两下**：第一下只提醒，免得误触把启动器关掉。
  /// 第二下也不结束进程，只是退到后台（见 [AndroidHost.moveTaskToBack]）
  void _handleSystemBack(bool didPop, Object? result) {
    if (didPop) return;

    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      unawaited(navigator.maybePop());
      return;
    }

    final now = DateTime.now();
    final last = _lastBackPressedAt;
    if (last == null || now.difference(last) > _backTwiceWindow) {
      _lastBackPressedAt = now;
      addNotice(
        icon: Icons.exit_to_app,
        title: '再按一次',
        content: '再按一次返回键，启动器退到后台',
      );
      return;
    }

    _lastBackPressedAt = null;
    unawaited(AndroidHost.moveTaskToBack());
  }

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
    //拖入是全局入口，拿不到"正在看的版本"，目标跟随启动页当前选中的版本——
    //隔离版本会落到它自己的数据目录，未选版本才落默认数据目录
    await showResourceImporter(
      d.files.map((it) => it.path).toList(),
      mindustry: config.versionOptions.selectedVersion,
    );
  }

  // ── 构建 ──

  Widget _buildTopbar() {
    final colors = AppColors.of(context);
    final navigationCollapse =
        config.setting.personalizationOptions.navigationCollapse;

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
              _sidebarToggle(
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

              _buildAccountButton(),

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

              const TaskDrawerOpener(),
              const SizedBox(width: 4),

              ValueListenableBuilder<bool>(
                valueListenable: subNavigationCollapseNotifier,
                builder: (context, subNavigationCollapse, _) {
                  return _sidebarToggle(
                    hint: !subNavigationCollapse ? '点击收纳副菜单' : '点击展开副菜单',
                    icon: Symbols.dock_to_left,
                    fillAlignment: Alignment(0.60, -0.08),
                    active: !subNavigationCollapse,
                    onTap: () =>
                        setSubNavigationCollapse(!subNavigationCollapse),
                  );
                },
              ),

              if (isDesktop) ...[
                const SizedBox(width: 4),
                ReboundButton(
                  backgroundColor: Colors.transparent,
                  onTap: () => windowManager.minimize(),
                  child: Icon(Icons.remove),
                ),
                const SizedBox(width: 4),
                WindowCloseButton(),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _sidebarToggle({
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

  /// 顶栏的账户入口：点开左侧账户抽屉，有未读通知时右上角带红点
  Widget _buildAccountButton() {
    final colors = AppColors.of(context);
    return ValueListenableBuilder<List<MdtbbsNoticeItem>>(
      valueListenable: MdtbbsNotificationService.instance.items,
      builder: (context, _, _) {
        final unread = MdtbbsNotificationService.instance.unreadCount;
        return HintLayer(
          hint: '账户',
          preferPosition: .bottom,
          child: ReboundButton(
            backgroundColor: Colors.transparent,
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: Icon(Icons.account_circle_outlined, size: 22),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 0.5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
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

  /// 左侧账户抽屉：账户 / 好友 / 云存档 / 账户通知
  Widget _buildAccountDrawer() {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Drawer(
      backgroundColor: colors.pageBackground,
      width: 300,
      elevation: 2,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(side: BorderSide(color: colors.border)),
      child: SafeArea(
        child: ValueListenableBuilder<AccountSnapshot>(
          valueListenable: AccountManager.instance.snapshot,
          builder: (context, account, _) {
            return ValueListenableBuilder<List<MdtbbsNoticeItem>>(
              valueListenable: MdtbbsNotificationService.instance.items,
              builder: (context, _, _) {
                final unread = MdtbbsNotificationService.instance.unreadCount;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.block),
                      child: Row(
                        spacing: AppSpacing.related,
                        children: [
                          Icon(
                            Icons.account_circle,
                            size: 36,
                            color: colors.interactive,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account.loggedIn
                                      ? (account.username ?? '已登录')
                                      : '未登录',
                                  style: theme.textTheme.titleSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  account.loggedIn
                                      ? '社区账号'
                                      : '登录后可加好友、同步云存档',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.itemHint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.border),
                    _buildDrawerItem(
                      icon: Icons.person_outline,
                      label: '账户（游戏内身份）',
                      route: accountPageRouteKey,
                    ),
                    _buildDrawerItem(
                      icon: Icons.people_outline,
                      label: '好友',
                      route: friendsPageRouteKey,
                    ),
                    _buildDrawerItem(
                      icon: Icons.cloud_outlined,
                      label: '云存档',
                      route: versionCloudSavePageRouteKey,
                    ),
                    _buildDrawerItem(
                      icon: Icons.notifications_none,
                      label: '账户通知',
                      route: notificationsPageRouteKey,
                      badge: unread,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required String route,
    int badge = 0,
  }) {
    final colors = AppColors.of(context);
    return ReboundButton(
      backgroundColor: Colors.transparent,
      onTap: () {
        _scaffoldKey.currentState?.closeDrawer();
        _onRootNavigate(route, null);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.block,
          vertical: AppSpacing.related,
        ),
        child: Row(
          spacing: AppSpacing.related,
          children: [
            Icon(icon, size: 20, color: colors.itemSecondary),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: colors.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

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

    Widget shell = Scaffold(
      key: _scaffoldKey,
      // 键盘不改启动器尺寸：输入法内边距由辅助输入条承接，页面自己不跟着缩
      resizeToAvoidBottomInset: false,
      backgroundColor: colors.pageBackground,
      drawer: _buildAccountDrawer(),
      endDrawer: Drawer(
        backgroundColor: colors.pageBackground.withAlpha(230),
        width: MediaQuery.of(context).size.width * 0.45,
        elevation: 2,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(side: BorderSide(color: colors.border)),
        child: InfoList(),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: LauncherTray.instance.isWindowHidden,
        builder: (context, isHidden, _) =>
            TickerMode(enabled: !isHidden, child: _buildShellBody(colors)),
      ),
    );

    if (isDesktop) {
      return DragFileField(onDragDone: _handleDragFile, child: shell);
    }
    // 桌面端没有系统返回键；移动端把它接管过来
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleSystemBack,
      child: shell,
    );
  }

  Widget _buildShellBody(AppColors colors) {
    // 刘海 / 挖孔与系统栏：取 viewPadding（不随输入法变）让开安全区；
    // 让开的那几条由各自那块的底色继续铺满，别在外围围出一圈生硬的边
    final safe = MediaQuery.viewPaddingOf(context);

    return Row(
      children: [
        // ── 左侧导航 ──
        // 挖孔落在这一侧时，栏里的内容往里让，条子仍铺导航栏自己的底色
        ColoredBox(
          color: colors.cardBackground,
          child: Padding(
            padding: EdgeInsets.only(
              left: safe.left,
              top: safe.top,
              bottom: safe.bottom,
            ),
            child: NavigationRail(
              navigatorKey: _navigatorKey,
              currentRoute: _currentRoute,
              currentRootRoute: _currentRootRoute,
              sections: _sections,
              itemsAtBottom: _items,

              onNavigate: _onRootNavigate,
            ),
          ),
        ),

        VerticalDivider(width: 1, thickness: 1, color: colors.border),

        // ── 右侧内容区 ──
        Expanded(
          child: ColorfulBackground(
            colorful: config.setting.personalizationOptions.colorfulBackground,
            child: Padding(
              padding: EdgeInsets.only(
                top: safe.top,
                right: safe.right,
                bottom: safe.bottom,
              ),
              child: Column(
                children: [
                  _buildTopbar(),
                  Expanded(child: _buildNavigator()),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 页面过渡 ──

  PageRouteBuilder _buildRoute(RouteSettings setting) {
    Widget page = routeMap[setting.name] ?? _NotFoundPage();

    return PageRouteBuilder(
      settings: setting,
      pageBuilder: (_, _, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: page,
      ),
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
    final name = route.settings.name;
    final args = route.settings.arguments;
    debugPrint('当前路由 [$name , $args]');
    addLog(.debug, '路由切换：$name${_argsSummary(args)}', tag: 'Route');
    onChanged(name, args);
  }

  /// 路由参数摘要：只取面包屑用的 lead / title，别把整个对象（可能很大）塞进日志
  static String _argsSummary(dynamic args) {
    if (args is! Map) return '';
    final parts = [
      if (args['lead'] != null) 'lead=${args['lead']}',
      if (args['title'] != null) 'title=${args['title']}',
    ];
    return parts.isEmpty ? '' : '（${parts.join(', ')}）';
  }
}

/// 路由未匹配时的缺省页
class _NotFoundPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('页面未找到', style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
