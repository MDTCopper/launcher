import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/pages/bridge_install_page.dart';
import 'package:copper_launcher/ui/shell/app_shell.dart';
import 'package:copper_launcher/ui/theme/app_theme.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
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
  /// 桥的运行环境装好了没：桌面端不需要这份载荷，Android 上要装完才进主页
  bool isRuntimeReady = !Platform.isAndroid;

  void updateTheme() => setState(() {
    final setting = config.setting.personalizationOptions;
    themeMode = setting.themeMode;
    themeColor = setting.themeColor;
  });

  ThemeMode themeMode = config.setting.personalizationOptions.themeMode;
  ThemeColor themeColor = config.setting.personalizationOptions.themeColor;

  @override
  Widget build(BuildContext context) {
    // 启动器不需要无障碍：整棵语义树排除，规避 Windows UIA 客户端在线时
    // engine 序列化 AXTree 的框架级 bug
    return ExcludeSemantics(
      child: MaterialApp(
        title: 'Copper',
        theme: buildTheme(Brightness.light, themeColor),
        //由MaterialApp控制亮暗
        darkTheme: buildTheme(Brightness.dark, themeColor),
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        home: isRuntimeReady
            ? AppShell(key: PageKeyProvider.shellKey)
            : BridgeInstallPage(
                onReady: () => setState(() => isRuntimeReady = true),
              ),
      ),
    );
  }
}
