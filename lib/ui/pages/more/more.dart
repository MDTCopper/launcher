import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/navigation_collapse_button.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';
import 'package:flutter/material.dart';

import 'about_page.dart';
import 'help_page.dart';
import 'tool_page.dart';

///更多分项路由
const toolPageRouteKey = '/tool';
const helpPageRouteKey = '/help';
const aboutPageRouteKey = '/about';

class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<StatefulWidget> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  static int _index = 0;

  bool get collapse =>
      config.setting.personalizationOptions.subNavigationCollapse;
  set collapse(bool value) {
    config.setting.personalizationOptions.subNavigationCollapse = value;
    config.save();
  }

  late final List<Widget> pages = const [
    ToolPage(),
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
      case toolPageRouteKey:
        _index = 0;
      case helpPageRouteKey:
        _index = 1;
      case aboutPageRouteKey:
        _index = 2;
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
            icon: Icon(Icons.widgets_outlined),
            content: '神秘小工具',
            onTap: () => moveTo(0),
            selected: _index == 0,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.help_outline),
            content: '帮助',
            onTap: () => moveTo(1),
            selected: _index == 1,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.info_outline),
            content: '关于',
            onTap: () => moveTo(2),
            selected: _index == 2,
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
