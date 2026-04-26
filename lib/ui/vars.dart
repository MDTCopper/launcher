
import 'package:copperlauncher_main/ui/pages/branch/download/mod_download.dart';
import 'package:copperlauncher_main/ui/pages/more.dart';
import 'package:copperlauncher_main/ui/pages/branch/launch/version_select.dart';
import 'package:copperlauncher_main/ui/pages/branch/launch/version_setting.dart';
import 'package:copperlauncher_main/ui/pages/download.dart';
import 'package:copperlauncher_main/ui/pages/launch.dart';
import 'package:copperlauncher_main/ui/pages/setting.dart';
import 'package:flutter/cupertino.dart';

abstract class Vars {
  static final Map<String, Widget> routeMap = {
    //配置路由
    '/': LaunchPage(),
    '/version_select':VersionSelectPage(),
    '/version_setting':VersionSettingPage(),
    '/download': DownloadPage(),
    '/download/mod_download':ModDownload(),
    '/setting': SettingPage(),
    '/about': MorePage(),
  };
}

