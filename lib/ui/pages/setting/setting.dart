import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/navigation_collapse_button.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';
import 'package:copper_launcher/ui/util/info/sub_navigation_state.dart';
import 'package:copper_launcher/ui/pages/setting/about_page.dart';
import 'package:copper_launcher/ui/pages/setting/help_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'game_setting_page.dart';
import 'launch_setting_page.dart';
import 'other_setting_page.dart';
import 'personalization_setting_page.dart';

//设置分项路由
const launchSettingPageRouteKey = '/setting/launch_setting';
const gameSettingPageRouteKey = '/setting/game_setting';
const personalizedSettingPageRouteKey = '/setting/personalized_setting';
const otherSettingPageRouteKey = '/setting/other_setting';
const helpPageRouteKey = '/setting/help';
const aboutPageRouteKey = '/setting/about';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  static int _index = 0;

  bool get collapse => subNavCollapseNotifier.value;
  set collapse(bool value) => setSubNavCollapse(value);

  /// 顶栏（app_shell）改收起态时，页面在 Navigator 里不会自动重建；
  /// 监听共享 notifier 主动 setState，让本页的二级导航同步收起/展开。
  @override
  void initState() {
    super.initState();
    subNavCollapseNotifier.addListener(_onSubNavChanged);
  }

  @override
  void dispose() {
    subNavCollapseNotifier.removeListener(_onSubNavChanged);
    super.dispose();
  }

  void _onSubNavChanged() {
    if (mounted) setState(() {});
  }

  late final List<Widget> pages = const [
    LaunchSettingPage(),
    GameSettingPage(),
    PersonalizationSettingPage(),
    OtherSettingPage(),
    HelpPage(),
    AboutPage(),
  ];

  void moveTo(int i) {
    if (mounted) setState(() => _index = i);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    //根据进入时的路由决定初始分项
    final name = ModalRoute.of(context)?.settings.name;
    switch (name) {
      case launchSettingPageRouteKey:
        _index = 0;
      case gameSettingPageRouteKey:
        _index = 1;
      case personalizedSettingPageRouteKey:
        _index = 2;
      case otherSettingPageRouteKey:
        _index = 3;
      case helpPageRouteKey:
        _index = 4;
      case aboutPageRouteKey:
        _index = 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return MainPageLayout(
      navigationRail: PageNavigationRail(
        collapse: collapse,
        width: 137,
        items: [
          NavigationTile(
            icon: Icon(Icons.rocket_launch_outlined),
            content: '启动项',
            onTap: () => moveTo(0),
            selected: _index == 0,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.gamepad_outlined),
            content: '游戏内设置',
            onTap: () => moveTo(1),
            selected: _index == 1,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.palette_outlined),
            content: '个性化',
            onTap: () => moveTo(2),
            selected: _index == 2,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.more_horiz_outlined),
            content: '其他',
            onTap: () => moveTo(3),
            selected: _index == 3,
            collapse: collapse,
          ),
          Divider(color: colors.border, indent: 4, endIndent: 4),
          NavigationTile(
            icon: Icon(Icons.help_center_outlined),
            content: '帮助',
            onTap: () => moveTo(4),
            selected: _index == 4,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.info_outline),
            content: '关于',
            onTap: () => moveTo(5),
            selected: _index == 5,
            collapse: collapse,
          ),
        ],
        itemsAtBottom: [
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
      page: pages[_index],
    );
  }
}
