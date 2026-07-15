import 'dart:async';
import 'dart:ffi';

import 'package:copper_launcher/ui/route_pages/branch/launch/version_select.dart';
import 'package:copper_launcher/ui/route_pages/branch/launch/version_setting.dart';
import 'package:copper_launcher/ui/route_pages/download/mindustry_download_page.dart';
import 'package:copper_launcher/ui/route_pages/download/mod_download_page.dart';
import 'package:copper_launcher/ui/route_pages/download/mod_view_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:line_icons/line_icons.dart';

import '../../route_pages/overview/launch.dart';

class RouteSection {
  RouteSection({required this.title, required this.items});
  final String title;
  final List<RouteItem> items;
}

class RouteItem {
  RouteItem({
    required this.route,
    required this.name,
    this.hide = false,
    this.icon,
    this.children,
    this.builder,
    this.redirect,
  });
  final String route;
  final String name;
  final IconData? icon;
  final bool hide;
  final Widget Function(BuildContext)? builder;
  final FutureOr<String?> Function(BuildContext, GoRouterState)? redirect;
  final List<RouteItem>? children;
}

final List<RouteSection> appRoutes = [
  RouteSection(
    title: '概览',
    items: [
      RouteItem(
        route: '/',
        name: '',
        icon: Icons.play_arrow_outlined,
        builder: (_) => LaunchPage(),
        children: [
          RouteItem(
            route: '/launch/version_selected',
            name: '版本选择',
            hide: true,
            redirect: (_, _) => '/launch/version_selected/:fold',
            children: [

            ]
          ),
          RouteItem(
            route: '/launch/version_setting',
            name: '版本设置',
            hide: true,
            builder: (_) => VersionSettingPage(),
          ),
        ],
      ),
      RouteItem(
        route: '/user',
        name: '游戏用户',
        icon: Icons.person_2_outlined,
        builder: (_) => LaunchPage(),
      ),
    ],
  ),
  RouteSection(
    title: '资源',
    items: [
      RouteItem(
        route: '/mindustry',
        name: 'Mindustry',
        icon: Icons.view_in_ar,
        redirect: (_, _) => '/mindustry/github',
        children: [
          RouteItem(
            route: '/mindustry/github',
            name: 'Mindustry',
            icon: LineIcons.github,
            builder: (_) => MindustryDownloadPage(),
          ),
          //
        ],
      ),
      RouteItem(
        route: '/resources',
        name: '社区资源',
        icon: Icons.download,
        redirect: (_, _) => '/resources/mod',
        children: [
          RouteItem(
            route: '/resources/mod',
            name: '模组',
            icon: LineIcons.puzzlePiece,
            builder: (_) => ModViewPage(),
            children: [
              RouteItem(
                route: '/resources/mod/download',
                name: '模组下载',
                builder: (_) => ModDownloadPage(),
              ),
            ],
          ),
          RouteItem(
            route: '/resources/package',
            name: '整合包',
            icon: Icons.token_outlined,
            builder: (_) => Text('整合包下载'),
            children: [
              RouteItem(
                route: '/resources/package/download',
                name: '整合包下载',
                builder: (_) => Text('todo'),
              ),
            ],
          ),
          RouteItem(
            route: '/resources/blueprint',
            name: '蓝图',
            icon: Icons.paste,
            builder: (_) => Text('todo'),
            children: [
              RouteItem(
                route: '/resources/blueprint/download',
                name: '蓝图下载',
                builder: (_) => Text('todo'),
              ),
            ],
          ),
          RouteItem(
            route: '/resources/map',
            name: '地图',
            icon: Icons.map_outlined,
            builder: (_) => Text('todo'),
            children: [
              RouteItem(
                route: '/resources/map/download',
                name: '地图下载',
                builder: (_) => Text('todo'),
              ),
            ],
          ),
        ],
      ),
    ],
  ),

  RouteSection(
    title: '设置',
    items: [
      RouteItem(
        route: '/setting',
        name: '设置',
        icon: Icons.settings,
        redirect: (_, _) => '/setting/launch',
        children: [
          RouteItem(route: '/setting/launch', name: '启动项'),
          RouteItem(route: '/setting/game', name: '游戏内设置'),
          RouteItem(route: '/setting/personalized', name: '个性化'),
          RouteItem(route: '/setting/other', name: '其他'),
        ],
      ),
      RouteItem(
        route: '/setting',
        name: '设置',
        icon: Icons.settings,
        redirect: (_, _) => '/setting/launch',
        children: [
          RouteItem(route: '/setting/launch', name: '启动项'),
          RouteItem(route: '/setting/game', name: '游戏内设置'),
          RouteItem(route: '/setting/personalized', name: '个性化'),
          RouteItem(route: '/setting/other', name: '其他'),
        ],
      ),
    ],
  ),
  RouteSection(title: '', items: []),
];
