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
}
