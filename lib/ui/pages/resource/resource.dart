import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/page_framwork/list_view_page.dart';
import 'package:copper_launcher/ui/page_framwork/page_navigation_rail.dart';
import 'package:copper_launcher/ui/page_framwork/sub_navigation_state.dart';
import 'package:copper_launcher/ui/util/route/route_trail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';

import 'blueprint_view_page.dart';
import 'map_view_page.dart';
import 'mod_view_page.dart';
import 'package_view_page.dart';

///资源分项路由
const modViewPageRouteKey = '/community_resources/mod_view';
const packageViewPageRouteKey = '/community_resources/package_view';
const blueprintViewPageRouteKey = '/community_resources/blueprint_view';
const mapViewPageRouteKey = '/community_resources/map_view';

class ResourcePage extends StatefulWidget {
  const ResourcePage({super.key});

  @override
  State<StatefulWidget> createState() => _ResourcePageState();
}

class _ResourcePageState extends State<ResourcePage>
    with SubNavigationCollapseListener {
  static int _index = 0;

  static const _sectionLabels = ['模组', '整合包', '蓝图', '地图'];

  late final List<Widget> pages = const [
    ModViewPage(),
    PackageViewPage(),
    BlueprintViewPage(),
    MapViewPage(),
  ];

  void moveTo(int i) {
    if (!mounted) return;
    setState(() => _index = i);
    _reportSection();
  }

  /// 当前分项作为页内段显示在顶栏「社区资源」之后
  void _reportSection() {
    if (!mounted) return;
    final index = _index.clamp(0, _sectionLabels.length - 1);
    PageTopBar.of(context).setSections([_sectionLabels[index]]);
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
    _reportSection();
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
          //TODO 标准待定
          if (kDebugMode)
            NavigationTile(
              icon: Icon(Icons.token_outlined),
              content: '整合包',
              onTap: () => moveTo(1),
              selected: _index == 1,
              collapse: collapse,
            ),
          //TODO 蓝图站还没接，预览版先隐藏
          if (kDebugMode)
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
      ),
      page: pages[_index],
    );
  }
}
