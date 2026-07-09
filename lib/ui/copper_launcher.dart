import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/ui/shell/app_shell.dart';
import 'package:copperlauncher_main/ui/theme/app_theme.dart';
import 'package:copperlauncher_main/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';

void runCopperLauncher() {
  runApp(CopperLauncher(key: PageKeyProvider.themeKey));
}

class CopperLauncher extends StatefulWidget {
  const CopperLauncher({super.key});

  @override
  State<StatefulWidget> createState() => CopperLauncherState();
}

class CopperLauncherState extends State<CopperLauncher> {
  void updateState() => setState(() {
    final setting = config.setting.personalizationOptions;
    themeMode = setting.themeMode;
    themeColor = setting.themeColor;
  });

  ThemeMode themeMode = config.setting.personalizationOptions.themeMode;
  ThemeColor themeColor = config.setting.personalizationOptions.themeColor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Copper',
      theme: buildTheme(Brightness.light, themeColor),
      //由MaterialApp控制亮暗
      darkTheme: buildTheme(Brightness.dark, themeColor),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: AppShell(key: PageKeyProvider.shellKey),
    );
  }

  // Widget buildGoRoute() {
  //   final router = GoRouter(
  //     initialLocation: '/launch',
  //     routes: [
  //       ShellRoute(
  //         routes: [
  //           GoRoute(
  //             path: '/launch',
  //             name: '启动',
  //             routes: [
  //               GoRoute(path: '/launch/version_selected'),
  //               GoRoute(path: '/launch/version_setting'),
  //             ],
  //           ),
  //           GoRoute(
  //             path: '/resources',
  //             name: '资源下载',
  //             redirect: (_, _) => '/resources/mindustry_download',
  //             routes: [
  //               GoRoute(
  //                 path: '/resources/mindustry_download',
  //                 name: 'Mindustry',
  //               ),
  //               GoRoute(
  //                 path: '/resources/mod',
  //                 name: '模组',
  //                 routes: [GoRoute(path: '/resources/mod/download')],
  //               ),
  //               GoRoute(
  //                 path: '/resources/package',
  //                 name: '整合包',
  //                 routes: [GoRoute(path: '/resources/package/download')],
  //               ),
  //               GoRoute(
  //                 path: '/resources/blueprint',
  //                 name: '蓝图',
  //                 routes: [GoRoute(path: '/resources/blueprint/download')],
  //               ),
  //               GoRoute(
  //                 path: '/resources/map',
  //                 name: '地图',
  //                 routes: [GoRoute(path: '/resources/map/download')],
  //               ),
  //             ],
  //           ),
  //           GoRoute(
  //             path: '/setting',
  //             name: '设置',
  //             redirect: (_, _) => '/setting/launch',
  //             routes: [
  //               GoRoute(path: '/setting/launch',name: '启动项'),
  //               GoRoute(path: '/setting/game',name: '游戏内设置'),
  //               GoRoute(path: '/setting/personalized',name: '个性化'),
  //               GoRoute(path: '/setting/other',name: '其他'),
  //             ],
  //           ),
  //           GoRoute(
  //             path: '/more',
  //             name: '更多',
  //             redirect: (_, _) => '/more/tool',
  //             routes: [
  //               GoRoute(path: '/more/tool',name: '神秘小工具'),
  //               GoRoute(path: '/more/help',name: '帮助'),
  //               GoRoute(path: '/more/about',name: '关于Copper'),
  //             ],
  //           ),
  //         ],
  //       ),
  //     ],
  //   );
  //
  //   return MaterialApp.router(
  //     title: 'Copper',
  //     theme: buildTheme(Brightness.light, themeColor),
  //     //由MaterialApp控制亮暗
  //     darkTheme: buildTheme(Brightness.dark, themeColor),
  //     themeMode: themeMode,
  //     debugShowCheckedModeBanner: false,
  //     routerConfig: router,
  //   );
  // }
}
