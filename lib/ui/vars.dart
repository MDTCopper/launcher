import 'package:copperlauncher_main/ui/pages/branch/download/mod_download.dart';
import 'package:copperlauncher_main/ui/pages/branch/launch/version_select.dart';
import 'package:copperlauncher_main/ui/pages/branch/launch/version_setting.dart';
import 'package:copperlauncher_main/ui/pages/download.dart';
import 'package:copperlauncher_main/ui/pages/launch.dart';
import 'package:copperlauncher_main/ui/pages/more.dart';
import 'package:copperlauncher_main/ui/pages/setting.dart';
import 'package:flutter/cupertino.dart';

import '../core/app_config.dart';

///路由映射
const Map<String, Widget> routeMap = {
  '/': LaunchPage(),
  '/version_select': VersionSelectPage(),
  '/version_setting': VersionSettingPage(),
  '/download': DownloadPage(),
  '/download/mod_download': ModDownload(),
  '/setting': SettingPage(),
  '/about': MorePage(),
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
