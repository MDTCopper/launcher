import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/navigation_collapse_button.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';

import 'blueprint_view_page.dart';
import 'map_view_page.dart';
import 'mod_view_page.dart';
import 'package_view_page.dart';

///资源分项路由
const modViewPageRouteKey = '/mod_view';
const packageViewPageRouteKey = '/package_view';
const blueprintViewPageRouteKey = '/blueprint_view';
const mapViewPageRouteKey = '/map_view';

class ResourcePage extends StatefulWidget {
  const ResourcePage({super.key});

  @override
  State<StatefulWidget> createState() => _ResourcePageState();
}

class _ResourcePageState extends State<ResourcePage> {
  static int _index = 0;

  bool get collapse =>
      config.setting.personalizationOptions.subNavigationCollapse;
  set collapse(bool value) {
    config.setting.personalizationOptions.subNavigationCollapse = value;
    config.save();
  }

  late final List<Widget> pages = const [
    ModViewPage(),
    PackageViewPage(),
    BlueprintViewPage(),
    MapViewPage(),
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
      case modViewPageRouteKey:
        _index = 0;
      case packageViewPageRouteKey:
        _index = 1;
      case blueprintViewPageRouteKey:
        _index = 2;
      case mapViewPageRouteKey:
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
            icon: Icon(LineIcons.puzzlePiece),
            content: '模组',
            onTap: () => moveTo(0),
            selected: _index == 0,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.token_outlined),
            content: '整合包',
            onTap: () => moveTo(1),
            selected: _index == 1,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.paste_outlined),
            content: '蓝图',
            onTap: () => moveTo(2),
            selected: _index == 2,
            collapse: collapse,
          ),
          NavigationTile(
            icon: Icon(Icons.map_outlined),
            content: '地图',
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
