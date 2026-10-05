import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';
import 'package:copper_launcher/ui/page_framwork/sub_navigation_state.dart';
import 'package:flutter/material.dart';

import 'design_about_rework_page.dart';
import 'design_experiments_page.dart';
import 'design_mods_rework_page.dart';
import 'design_setting_rework_page.dart';
import 'design_structure_page.dart';

const designExamplePageRouteKey = '/design/example';

/// 设计规范 · 实例页（容器）
///
/// 两个分项：「结构样板」讲一个页面怎么搭起来、「试验对照」放反例与正例的对照；
/// 与 ResourcePage / SettingPage 同一套容器做法，副菜单在右侧
class DesignExamplePage extends StatefulWidget {
  const DesignExamplePage({super.key});

  @override
  State<DesignExamplePage> createState() => _DesignExamplePageState();
}

class _DesignExamplePageState extends State<DesignExamplePage>
    with SubNavigationCollapseListener {
  static int _index = 0;

  late final List<Widget> pages = const [
    DesignStructurePage(),
    DesignExperimentsPage(),
    DesignAboutReworkPage(),
    DesignSettingReworkPage(),
    DesignModsReworkPage(),
  ];

  void moveTo(int i) {
    if (mounted) setState(() => _index = i);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 按进入时的路由决定初始分项
    switch (ModalRoute.of(context)?.settings.name) {
      case designExperimentsPageRouteKey:
        _index = 1;
      case designAboutReworkPageRouteKey:
        _index = 2;
      case designSettingReworkPageRouteKey:
        _index = 3;
      case designModsReworkPageRouteKey:
        _index = 4;
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
            icon: const Icon(Icons.view_agenda_outlined),
            content: '结构样板',
            onTap: () => moveTo(0),
            selected: _index == 0,
            collapse: collapse,
          ),
          NavigationTile(
            icon: const Icon(Icons.science_outlined),
            content: '试验对照',
            onTap: () => moveTo(1),
            selected: _index == 1,
            collapse: collapse,
          ),
          NavigationTile(
            icon: const Icon(Icons.restart_alt),
            content: '关于页重做',
            onTap: () => moveTo(2),
            selected: _index == 2,
            collapse: collapse,
          ),
          NavigationTile(
            icon: const Icon(Icons.tune),
            content: '设置页重做',
            onTap: () => moveTo(3),
            selected: _index == 3,
            collapse: collapse,
          ),
          NavigationTile(
            icon: const Icon(Icons.extension_outlined),
            content: '模组页重做',
            onTap: () => moveTo(4),
            selected: _index == 4,
            collapse: collapse,
          ),
        ],
      ),
      page: pages[_index],
    );
  }
}
