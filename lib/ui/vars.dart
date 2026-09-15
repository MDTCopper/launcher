import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/ui/pages/overview/game_user_page.dart';
import 'package:copper_launcher/ui/pages/overview/version_select.dart';
import 'package:copper_launcher/ui/pages/overview/version_setting.dart';
import 'package:copper_launcher/ui/pages/mindustry/mindustry_download_page.dart';

import 'package:copper_launcher/ui/pages/resource/mod_download_page.dart';
import 'package:copper_launcher/ui/pages/resource/resource.dart';
import 'package:copper_launcher/ui/pages/overview/launch.dart';
import 'package:copper_launcher/ui/pages/setting/setting.dart';
import 'package:copper_launcher/ui/pages/setting/license_page.dart';
import 'package:copper_launcher/ui/pages/test.dart';
import 'package:copper_launcher/ui/pages/tools.dart';
import 'package:flutter/cupertino.dart';

///路由映射
///
///主要页面下跟随其分项路由（分项路由 key 重定向到对应的主要页面，
///由容器页根据路由名定位到具体分项），与主要页面强相关的独立页面也跟随其下。
const Map<String, Widget> routeMap = {
  '/test': Test(),

  //概览
  '/': LaunchPage(),
  '/version_select': VersionSelectPage(),
  '/version_setting': VersionSettingPage(),
  gameUserPageRouteKey: GameUserPage(),

  //发现 - Mindustry
  '/mindustry_download': MindustryDownloadPage(),

  //发现 - 社区资源
  '/community_resources': ResourcePage(),
  modViewPageRouteKey: ResourcePage(),
  packageViewPageRouteKey: ResourcePage(),
  blueprintViewPageRouteKey: ResourcePage(),
  mapViewPageRouteKey: ResourcePage(),

  '/mod_view/download': ModDownloadPage(),

  '/tools': ToolsPage(),

  //设置
  '/setting': SettingPage(),
  launchSettingPageRouteKey: SettingPage(),
  gameSettingPageRouteKey: SettingPage(),
  personalizedSettingPageRouteKey: SettingPage(),
  otherSettingPageRouteKey: SettingPage(),
  helpPageRouteKey: SettingPage(),
  aboutPageRouteKey: SettingPage(),
  licensePageRouteKey: OpenSourceLicensePage(),
};

//token 注入统一由 cio 拦截器处理：仅 api.github.com、且 token 非空才附加，
//避免空 token 的 `Authorization: token ` 触发 GitHub 401，以及 token 泄露给镜像/raw
Map<String, String> get modDownloadHeaders => {
  'User-Agent': 'MindustryModDownloader',
};

Map<String, String> get gameDownloadHeaders => {
  'User-Agent': 'MindustryDownloader',
};

//动画倍率
double get animationMultiplier => 1.0;

Duration get animationSwitcherDuration =>
    kDefaultAnimationSwitcherDuration * animationMultiplier;

Duration get animationDuration =>
    kDefaultAnimationDuration * animationMultiplier;

Duration get fastAnimationDuration =>
    kDefaultFastAnimationSwitcherDuration * animationMultiplier;
