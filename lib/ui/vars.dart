import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/ui/pages/overview/version_select.dart';
import 'package:copper_launcher/ui/pages/overview/version_setting.dart';
import 'package:copper_launcher/ui/pages/mindustry/mindustry_download_page.dart';
import 'package:copper_launcher/ui/pages/more/more.dart';
import 'package:copper_launcher/ui/pages/resource/mod_download_page.dart';
import 'package:copper_launcher/ui/pages/resource/resource.dart';
import 'package:copper_launcher/ui/pages/overview/launch.dart';
import 'package:copper_launcher/ui/pages/setting/setting.dart';
import 'package:flutter/cupertino.dart';

import '../core/app_config.dart';

///路由映射
///
///主要页面下跟随其分项路由（分项路由 key 重定向到对应的主要页面，
///由容器页根据路由名定位到具体分项），与主要页面强相关的独立页面也跟随其下。
const Map<String, Widget> routeMap = {
  '/test': Text('测试页'),

  //概览
  '/': LaunchPage(),
  '/version_select': VersionSelectPage(),
  '/version_setting': VersionSettingPage(),

  //发现 - Mindustry
  '/mindustry_download': MindustryDownloadPage(),

  //发现 - 社区资源
  '/community_resources': ResourcePage(),
  modViewPageRouteKey: ResourcePage(),
  packageViewPageRouteKey: ResourcePage(),
  blueprintViewPageRouteKey: ResourcePage(),
  mapViewPageRouteKey: ResourcePage(),

  '/mod_view/download': ModDownloadPage(),

  //设置
  '/setting': SettingPage(),
  launchSettingPageRouteKey: SettingPage(),
  gameSettingPageRouteKey: SettingPage(),
  personalizedSettingPageRouteKey: SettingPage(),
  otherSettingPageRouteKey: SettingPage(),

  //更多
  '/more': MorePage(),
  toolPageRouteKey: MorePage(),
  helpPageRouteKey: MorePage(),
  aboutPageRouteKey: MorePage(),
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

//动画倍率
double get animationMultiplier => 1.0;

Duration get animationSwitcherDuration =>
    kDefaultAnimationSwitcherDuration * animationMultiplier;

Duration get animationDuration =>
    kDefaultAnimationDuration * animationMultiplier;
