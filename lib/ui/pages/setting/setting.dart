import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/navigation_collapse_button.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';
import 'package:flutter/material.dart';

import 'game_setting_page.dart';
import 'launch_setting_page.dart';
import 'other_setting_page.dart';
import 'personalization_setting_page.dart';

//设置分项路由
const launchSettingPageRouteKey = '/launch_setting';
const gameSettingPageRouteKey = '/game_setting';
const personalizedSettingPageRouteKey = '/personalized_setting';
const otherSettingPageRouteKey = '/other_setting';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  static int _index = 0;

  bool get collapse =>
      config.setting.personalizationOptions.subNavigationCollapse;
  set collapse(bool value) {
    config.setting.personalizationOptions.subNavigationCollapse = value;
    config.save();
  }

  late final List<Widget> pages = const [
    LaunchSettingPage(),
    GameSettingPage(),
    PersonalizationSettingPage(),
    OtherSettingPage(),
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
    }
  }

  @override
  Widget build(BuildContext context) {
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
