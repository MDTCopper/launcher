import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/ui/pages/bridge_install_page.dart';
import 'package:copper_launcher/ui/shell/app_shell.dart';
import 'package:copper_launcher/ui/shell/parts/auxiliary_input_bar.dart';
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
  ///
  /// **这里就要同步判一次**：交给安装页判的话，它必然先建一帧、再在 post-frame
  /// 回调里发现「其实早装好了」⇒ 每次启动都闪过那一页
  bool isRuntimeReady = !Platform.isAndroid || BridgeInstaller.isRuntimeReady();

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
        builder: _buildPlatformOverlay,
        home: isRuntimeReady
            ? AppShell(key: PageKeyProvider.shellKey)
            : BridgeInstallPage(
                onReady: () => setState(() => isRuntimeReady = true),
              ),
      ),
    );
  }

  /// 移动端的输入法处理：输入法不改启动器的尺寸，输入改由辅助输入条承接
  Widget _buildPlatformOverlay(BuildContext context, Widget? child) {
    if (child == null) return const SizedBox.shrink();
    if (!Platform.isAndroid) return child;

    // 底部输入法内边距从整棵应用子树摘掉：键盘弹起时页面不缩、不被顶起
    final content = MediaQuery(
      data: MediaQuery.of(context).removeViewInsets(removeBottom: true),
      child: child,
    );
    // 条挂在 navigator 之上，弹窗里的输入框聚焦时也接管得到
    return AuxiliaryInputBar(child: content);
  }
}
