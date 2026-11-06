import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_notification_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/avatar/user_avatar.dart';
import 'package:copper_launcher/ui/shell/app_navigation.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/components/scroll/scroll_fade_mask.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/pages/cloud/cloud_overview_page.dart';
import 'package:copper_launcher/ui/pages/friends/friends_page.dart';
import 'package:copper_launcher/ui/pages/notifications/notifications_page.dart';
import 'package:copper_launcher/ui/pages/online/online_page.dart';
import 'package:copper_launcher/ui/shell/parts/window_close_button.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/ui/util/route/route_trail.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

/// 账户抽屉里的四个页签
enum _AccountTab { profile, friends, cloud, notices }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _navigatorKey = PageKeyProvider.navigatorKey;

  /// 账户抽屉要从顶栏打开，拿 Scaffold 的 state
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 抽屉里当前选中的页签
  _AccountTab _accountTab = _AccountTab.profile;

  /// 顶栏面包屑的横向滚动：长了可以滚动查看整条路由栈
  final _trailScrollController = ScrollController();

  // ── 导航配置 ──

  bool get canPop => _navigatorKey.currentState?.canPop() == true;

  /// 栈顶路由，导航栏高亮用；首帧栈还没建立时按主页算
  String get _currentRoute => routeWatcher.stack.isEmpty
      ? '/'
      : routeWatcher.stack.last.settings.name ?? '/';

  /// 栈底路由 = 这个栈的正式入口
  String get _currentRootRoute => routeWatcher.stack.isEmpty
      ? '/'
      : routeWatcher.stack.first.settings.name ?? '/';

  /// 返回键连按的判定窗口：两下之间超过它就算新的一轮（重新提醒）
  static const _backTwiceWindow = Duration(seconds: 2);

  /// 上一次按返回键的时刻；null = 还没按过
  DateTime? _lastBackPressedAt;

  static final _sections = [
    RailSection(
      label: '概览',
      items: [
        RailItem(label: '主页', icon: Icons.home_filled, route: '/'),
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
            label: '种子配色',
            icon: Icons.palette_outlined,
            route: '/seed_lab',
          ),
        // 设计层预览页：新模组下载页 + 组件目录（用户在这两页上做微调）
        if (kDebugMode)
          RailItem(
            label: '模组下载（新）',
            icon: Icons.extension_outlined,
            route: '/template_mod_download',
          ),
        if (kDebugMode)
          RailItem(
            label: '组件目录',
            icon: Icons.widgets_outlined,
            route: '/template_catalog',
          ),
      ],
    ),
  ];

  static final _items = [
    RailItem(label: '设置', icon: Icons.settings, route: '/setting'),
    if (kDebugMode)
      RailItem(label: '测试页面', icon: Icons.terminal_outlined, route: '/test'),
  ];

  /// 根路由段名：就是主导航项的名字，不另存一份
  static final Map<String, String> _rootRouteLabels = {
    for (final section in _sections)
      for (final item in section.items) item.route: item.label,
    for (final item in _items) item.route: item.label,
  };

  /// 面包屑里的段名：根段取主导航名字，其余取路由表；没登记的回退成路由 key
  String _labelOfRoute(String route) {
    final label = _rootRouteLabels[route] ?? routeLabels[route];
    if (label == null) {
      debugPrint('顶栏没登记路由段名：$route');
    }
    return label ?? route;
  }

  //导航栏根路由切换
  void _onRootNavigate(String route) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    // 同一入口下只是压了子页：回根页，保留根页状态
    final stack = routeWatcher.stack;
    if (stack.isNotEmpty && stack.first.settings.name == route) {
      navigator.popUntil((page) => page.isFirst);
      return;
    }

    // 换入口：清空子路由栈，从新入口重新开始
    navigator.pushNamedAndRemoveUntil(route, (_) => false);
  }

  /// 点面包屑里的中间段：直接退回那一层
  void _jumpToRoute(PageRoute<dynamic> route) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !routeWatcher.stack.contains(route)) return;
    navigator.popUntil((page) => page == route);
  }

  late final routeWatcher = _RouteWatcher(_scheduleTrailRebuild);

  // ── 系统返回键 ──

  /// 安卓返回键与全面屏手势都走这里
  ///
  /// 子路由先返回一层；到了底层路由要**连按两下**：第一下只提醒，免得误触把启动器关掉。
  /// 第二下也不结束进程，只是退到后台（宿主通道的 `moveTaskToBack`）
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
    unawaited(_moveTaskToBack());
  }

  static Future<void> _moveTaskToBack() async {
    try {
      await AndroidCall.moveTaskToBack();
    } on Object catch (error) {
      addLog(.warning, '退到后台失败：$error', tag: 'Host');
    }
  }

  // ── 路由监听 更新导航栏高亮与顶栏面包屑 ──

  /// 栈或页面回写变化后重建：统一延迟到帧后，避免在 build 里 setState
  void _scheduleTrailRebuild() {
    if (_trailRebuildScheduled) return;
    _trailRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trailRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  bool _trailRebuildScheduled = false;

  /// 把当前路由栈展开成顶栏段：每条路由一段，页面回写的页内分项跟在它后面
  List<BreadcrumbSegment> _buildTrailSegments() {
    final entries = <RouteTrailEntry>[];
    for (final route in routeWatcher.stack) {
      final trail = route is CopperPageRoute
          ? route.trailController.value
          : const PageTopBarTrail();
      final args = route.settings.arguments;
      final title = args is Map && args['title'] is String
          ? args['title'] as String
          : null;
      entries.add(
        RouteTrailEntry(
          route: route,
          label: _labelOfRoute(route.settings.name ?? ''),
          suffix: trail.suffix ?? title,
          sections: trail.sections,
        ),
      );
    }
    return buildBreadcrumb(entries);
  }

  Widget _buildBreadcrumb() {
    final segments = _buildTrailSegments();
    if (segments.isEmpty) {
      return Text('主页', style: Theme.of(context).textTheme.labelMedium);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Listener(
        onPointerSignal: _handleTrailPointerSignal,
        child: ScrollFadeMask(
          controller: _trailScrollController,
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            controller: _trailScrollController,
            scrollDirection: Axis.horizontal,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Row(
                key: ValueKey(_trailSignature(segments)),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < segments.length; index++) ...[
                    if (index > 0) _buildTrailSeparator(),
                    _buildTrailSegment(segments[index]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _trailSignature(List<BreadcrumbSegment> segments) => segments
      .map(
        (segment) =>
            '${segment is InPageBreadcrumb ? '[' : ''}${segment.label}',
      )
      .join('>');

  /// 顶栏放不下时用滚轮横向看完整条栈
  void _handleTrailPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_trailScrollController.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    final position = _trailScrollController.position;
    _trailScrollController.jumpTo(
      (_trailScrollController.offset + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Widget _buildTrailSeparator() {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(Icons.chevron_right, size: 14, color: colors.itemHint),
    );
  }

  Widget _buildTrailSegment(BreadcrumbSegment segment) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    switch (segment) {
      case RouteBreadcrumb(:final label, :final route, :final isCurrent):
        final text = Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isCurrent ? colors.itemPrimary : colors.itemSecondary,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          ),
        );
        if (isCurrent) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: text,
          );
        }
        return ReboundContainer(
          onTap: () => _jumpToRoute(route),
          pressedScale: 0.96,
          duration: const Duration(milliseconds: 120),
          borderRadius: BorderRadius.circular(4),
          hoverColor: colors.highBackgroundOnCard,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: text,
        );
      case InPageBreadcrumb(:final label):
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
          ),
        );
    }
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

              const SizedBox(width: 8),

              Expanded(child: _buildBreadcrumb()),

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

  /// 顶栏的账户入口：一张小卡片（头像 + 用户名），点开左侧账户抽屉
  Widget _buildAccountButton() {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        AccountManager.instance.snapshot,
        MdtbbsNotificationService.instance.items,
      ]),
      builder: (context, _) {
        final unread = MdtbbsNotificationService.instance.unreadCount;
        final account = AccountManager.instance.snapshot.value;
        final name = account.loggedIn ? (account.username ?? '已登录') : '未登录';
        return HintLayer(
          hint: '账户',
          preferPosition: .bottom,
          child: ReboundButton(
            backgroundColor: Colors.transparent,
            onTap: () {
              _scaffoldKey.currentState?.openDrawer();
              // 头像在 /me 里，还没读过资料就先补一次
              final accounts = AccountManager.instance;
              if (accounts.isLoggedIn && accounts.account == null) {
                unawaited(accounts.loadAccount());
              }
            },
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: colors.highBackgroundOnCard,
                borderRadius: BorderRadius.circular(AppRadius.item),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  UserAvatar(
                    url: account.avatarUrl,
                    size: 18,
                    fallbackIcon: Icons.account_circle_outlined,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  if (unread > 0)
                    // 固定高度 + 圆角一半：不加尺寸约束的话会被行高挤成椭圆
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
      },
    );
  }

  /// 左侧账户抽屉：顶部是抽屉内的导航，四个页签的内容直接渲染在抽屉里
  Widget _buildAccountDrawer() {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    // 账户抽屉按窗口比例取宽：窄屏仍铺满，桌面端不固定 360
    final drawerWidth = width < 420
        ? width
        : (width * 0.36).clamp(360.0, 620.0).toDouble();
    return Drawer(
      backgroundColor: colors.pageBackground,
      width: drawerWidth,
      elevation: 2,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(side: BorderSide(color: colors.border)),
      child: SafeArea(
        child: ValueListenableBuilder<AccountSnapshot>(
          valueListenable: AccountManager.instance.snapshot,
          builder: (context, account, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.block,
                    AppSpacing.related,
                    AppSpacing.block,
                    AppSpacing.related,
                  ),
                  child: Row(
                    spacing: AppSpacing.related,
                    children: [
                      UserAvatar(
                        url: account.avatarUrl,
                        size: 36,
                        fallbackIcon: Icons.account_circle,
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
                              account.loggedIn ? '社区账号' : '登录后可加好友、同步云存档',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.itemHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (account.loggedIn)
                        IconTextButton(
                          pressedScale: 0.96,
                          icon: Icons.logout,
                          content: '退出',
                          onTap: _logoutAccount,
                        ),
                    ],
                  ),
                ),
                _buildAccountNav(),
                Divider(height: 1, color: colors.border),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: KeyedSubtree(
                      key: ValueKey(_accountTab),
                      child: _buildAccountTabContent(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 抽屉顶部的退出登录：二次确认后清掉账号态
  void _logoutAccount() {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '退出 BBS 账号？',
      content: '会撤销这个启动器的登录凭证并清掉本地账号信息；云端存档不受影响',
      action: () => unawaited(AccountManager.instance.logout()),
    );
  }

  /// 抽屉顶栏的四个入口：账户 / 好友 / 云存档 / 通知
  Widget _buildAccountNav() {
    return ValueListenableBuilder<List<MdtbbsNoticeItem>>(
      valueListenable: MdtbbsNotificationService.instance.items,
      builder: (context, _, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _buildAccountNavItem(
                _AccountTab.profile,
                Icons.person_outline,
                '账户',
              ),
              _buildAccountNavItem(
                _AccountTab.friends,
                Icons.people_outline,
                '好友',
              ),
              _buildAccountNavItem(
                _AccountTab.cloud,
                Icons.cloud_outlined,
                '云存档',
              ),
              _buildAccountNavItem(
                _AccountTab.notices,
                Icons.notifications_none,
                '通知',
                badge: MdtbbsNotificationService.instance.unreadCount,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountNavItem(
    _AccountTab tab,
    IconData icon,
    String label, {
    int badge = 0,
  }) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final selected = _accountTab == tab;
    return Expanded(
      child: ReboundButton(
        backgroundColor: selected
            ? colors.highBackgroundOnCard
            : Colors.transparent,
        onTap: () => setState(() => _accountTab = tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 4,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? colors.interactive : colors.itemHint,
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -5,
                      top: -3,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: colors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? colors.interactive : colors.itemSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 抽屉里那一块内容：四个页签各自就是一个现成的页面
  Widget _buildAccountTabContent() => switch (_accountTab) {
    _AccountTab.profile => const AccountPage(),
    _AccountTab.friends => const FriendsPage(),
    _AccountTab.cloud => const CloudOverviewPage(),
    _AccountTab.notices => const NotificationsPage(),
  };

  Widget _buildNavigator() {
    Widget child = Navigator(
      key: PageKeyProvider.navigatorKey,
      initialRoute: '/',
      observers: [routeWatcher],
      onGenerateRoute: _buildRoute,
    );
    return child;
  }

  /// 抽屉里的内容想「跳到某页并收起抽屉」时走 [AppNavigation]（避免和页面互相 import）
  @override
  void initState() {
    super.initState();
    AppNavigation.handler = (route) {
      _scaffoldKey.currentState?.closeDrawer();
      _onRootNavigate(route);
    };
    AppNavigation.pushHandler = (route, arguments) {
      _scaffoldKey.currentState?.closeDrawer();
      _navigatorKey.currentState?.pushNamed(route, arguments: arguments);
    };
  }

  @override
  void dispose() {
    _trailScrollController.dispose();
    super.dispose();
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

  Route<dynamic> _buildRoute(RouteSettings setting) {
    final page = routeMap[setting.name] ?? _NotFoundPage();
    final trailController = PageTopBarController();

    return CopperPageRoute(
      settings: setting,
      trailController: trailController,
      pageBuilder: (_, _, _) => PageTopBarScope(
        controller: trailController,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: page,
        ),
      ),
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

/// 维护内层导航的实际路由栈，并把页面回写的顶栏变化转成重建
///
/// Navigator 没有公开的栈读取接口，这里按 push / pop / replace / remove 自己记账；
/// [pushNamedAndRemoveUntil] 是「先 push 新的，再 remove 旧的」，同一条记账规则就能处理
class _RouteWatcher extends RouteObserver {
  _RouteWatcher(this.onChanged);

  final VoidCallback onChanged;

  /// 当前内层导航栈，顺序就是路由层级
  final List<PageRoute<dynamic>> stack = [];

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PageRoute<dynamic>) {
      stack.add(route);
      _listenTrail(route);
      _logStack();
    }
    onChanged();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (route is PageRoute<dynamic>) {
      _drop(route);
      _logStack();
    }
    onChanged();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (oldRoute is PageRoute<dynamic>) _drop(oldRoute);
    if (newRoute is PageRoute<dynamic>) {
      stack.add(newRoute);
      _listenTrail(newRoute);
      _logStack();
    }
    onChanged();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (route is PageRoute<dynamic>) {
      _drop(route);
      _logStack();
    }
    onChanged();
  }

  void _listenTrail(PageRoute<dynamic> route) {
    if (route is CopperPageRoute) {
      route.trailController.addListener(_onTrailChanged);
    }
  }

  void _drop(PageRoute<dynamic> route) {
    stack.remove(route);
    if (route is CopperPageRoute) {
      route.trailController.removeListener(_onTrailChanged);
    }
  }

  /// 页面改后缀 / 页内分项：不重记日志，只通知重建
  void _onTrailChanged() => onChanged();

  void _logStack() {
    final path = stack.map((route) => route.settings.name ?? '?').join(' > ');
    addLog(.debug, '路由栈：$path', tag: 'Route');
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
