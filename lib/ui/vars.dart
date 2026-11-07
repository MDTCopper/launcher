import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/pages/cloud/version_cloud_save_page.dart';
import 'package:copper_launcher/ui/pages/design/seed_lab_page.dart';
import 'package:copper_launcher/ui/pages/design/template_catalog_screen.dart';
import 'package:copper_launcher/ui/pages/design/template_mod_download_screen.dart';
import 'package:copper_launcher/ui/pages/design/template_mod_view_screen.dart';
import 'package:copper_launcher/ui/pages/friends/friends_page.dart';
import 'package:copper_launcher/ui/pages/notifications/notifications_page.dart';
import 'package:copper_launcher/ui/pages/overview/version_select.dart';
import 'package:copper_launcher/ui/pages/overview/version_setting.dart';
import 'package:copper_launcher/ui/pages/mindustry/mindustry_download_page.dart';
import 'package:copper_launcher/ui/pages/online/online_page.dart';

import 'package:copper_launcher/ui/pages/resource/mod_download_page.dart';
import 'package:copper_launcher/ui/pages/resource/resource.dart';
import 'package:copper_launcher/ui/pages/overview/launch.dart';
import 'package:copper_launcher/ui/pages/setting/setting.dart';
import 'package:copper_launcher/ui/pages/setting/license_page.dart';
import 'package:copper_launcher/ui/pages/setting/mobile_runtime_page.dart';
import 'package:copper_launcher/ui/pages/test.dart';
import 'package:copper_launcher/ui/pages/tools.dart';
import 'package:flutter/cupertino.dart';

///路由映射
///
///主要页面下跟随其分项路由（分项路由 key 重定向到对应的主要页面，
///由容器页根据路由名定位到具体分项），与主要页面强相关的独立页面也跟随其下
const Map<String, Widget> routeMap = {
  '/test': Test(),
  '/seed_lab': SeedLabPage(),
  //设计层预览页（仅 debug 出现在导航里）：组件目录 / 模组下载新页面
  '/template_catalog': TemplateCatalogScreen(),
  '/template_mod_download': TemplateModDownloadScreen(),
  '/template_mod_view': TemplateModViewScreen(),

  //概览
  '/': LaunchPage(),
  '/version_select': VersionSelectPage(),
  '/version_setting': VersionSettingPage(),
  accountPageRouteKey: AccountPage(),
  onlinePageRouteKey: OnlinePage(),
  friendsPageRouteKey: FriendsPage(),
  notificationsPageRouteKey: NotificationsPage(),

  //发现 - Mindustry
  '/mindustry_download': MindustryDownloadPage(),

  //发现 - 社区资源
  '/community_resources': ResourcePage(),
  modViewPageRouteKey: ResourcePage(),
  packageViewPageRouteKey: ResourcePage(),
  blueprintViewPageRouteKey: ResourcePage(),
  mapViewPageRouteKey: ResourcePage(),
  versionCloudSavePageRouteKey: VersionCloudSavePage(),

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
  mobileRuntimePageRouteKey: MobileRuntimePage(),
};

/// 顶栏面包屑用的子路由段名
///
/// 根路由段名取自主导航项，不在这里登记；容器页的分项别名归并到容器页自己的名字
/// （页内哪个分项由页面自己回写），未登记的路由会回退到路由 key
const Map<String, String> routeLabels = {
  versionSelectPageRouteKey: '版本选择',
  versionSettingPageRouteKey: '版本设置',
  accountPageRouteKey: '账户',
  friendsPageRouteKey: '好友',
  notificationsPageRouteKey: '通知',
  versionCloudSavePageRouteKey: '版本云存档',
  '/mod_view/download': '模组下载',

  // 容器页的分项别名：只作为进入容器页的入口，段名用容器页自己的
  modViewPageRouteKey: '社区资源',
  packageViewPageRouteKey: '社区资源',
  blueprintViewPageRouteKey: '社区资源',
  mapViewPageRouteKey: '社区资源',
  launchSettingPageRouteKey: '设置',
  gameSettingPageRouteKey: '设置',
  personalizedSettingPageRouteKey: '设置',
  otherSettingPageRouteKey: '设置',
  helpPageRouteKey: '设置',
  aboutPageRouteKey: '设置',
  licensePageRouteKey: '开源许可',
  mobileRuntimePageRouteKey: '移动端运行环境',
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
