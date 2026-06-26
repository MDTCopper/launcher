import 'package:copperlauncher_main/ui/route_pages/branch/launch/version_select.dart';
import 'package:copperlauncher_main/ui/route_pages/branch/launch/version_setting.dart';
import 'package:copperlauncher_main/ui/route_pages/download/mindustry_download_page.dart';
import 'package:copperlauncher_main/ui/route_pages/download/mod_download_page.dart';
import 'package:copperlauncher_main/ui/route_pages/download/mod_view_page.dart';
import 'package:copperlauncher_main/ui/route_pages/overview/launch.dart';
import 'package:copperlauncher_main/ui/route_pages/setting/game_setting_page.dart';
import 'package:copperlauncher_main/ui/route_pages/setting/launch_setting_page.dart';
import 'package:copperlauncher_main/ui/route_pages/setting/other_setting_page.dart';
import 'package:copperlauncher_main/ui/route_pages/setting/personalization_setting_page.dart';
import 'package:flutter/cupertino.dart';

import '../core/app_config.dart';

///路由映射
const Map<String, Widget> routeMap = {
  '/test': Text('测试页'),

  '/': LaunchPage(),
  //标记key以注册子路由map
  versionSelectPageRouteKey: VersionSelectPage(),
  versionSettingPageRouteKey: VersionSettingPage(),

  //下载分项
  '/mindustry_download': MindustryDownloadPage(),
  '/mod_view': ModViewPage(),
  '/mod_view/download': ModDownloadPage(),
  '/package_view': Text('todo 整合包浏览'),
  '/blueprint_view': Text('todo 蓝图浏览'),
  '/map_view': Text('todo 地图浏览'),

  //设置分项
  '/launch_setting': LaunchSettingPage(),
  '/game_setting': GameSettingPage(),
  '/personalized_setting': PersonalizationSettingPage(),
  '/other_setting': OtherSettingPage(),

  //更多选项
  '/tool': Text('todo 神秘工具'),
  '/help': Text('todo 帮助'),
  '/about': Text('todo 关于'),
};

String get githubToken => config.setting.githubToken;

Map<String, String> get modDownloadHeaders => {
  'User-Agent': 'MindustryModDownloader',
  'Authorization': 'token $githubToken',
};

Map<String, String> get gameDownloadHeaders => {
  'User-Agent': 'MindustryDownloader',
  'Authorization': 'token $githubToken',
};
