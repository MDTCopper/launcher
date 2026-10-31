import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_host.dart';
import 'package:copper_launcher/ui/pages/bridge_install_page.dart';
import 'package:copper_launcher/ui/shell/app_shell.dart';
import 'package:copper_launcher/ui/shell/parts/auxiliary_input_bar.dart';
import 'package:copper_launcher/ui/startup/startup_page.dart';
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

class CopperLauncherState extends State<CopperLauncher>
    with SingleTickerProviderStateMixin {
  /// 桥的运行环境装好了没：桌面端不需要这份载荷，Android 上要装完才进主页
  bool isRuntimeReady = !Platform.isAndroid;

  /// Android 启动页：先显示主题物品图标，初始化完再从左下到右上刷入主界面
  late final AnimationController _fadeController;
  bool _showStartup = Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startup());
      });
    } else {
      _fadeController.value = 1;
    }
    // 菜单的默认行为接到设置项上；设置页改了立刻生效，这里不用再监听
    ContextMenuHost.relocateOnReopenOf = () =>
        config.setting.personalizationOptions.menuRelocate;
  }

  Future<void> _startup() async {
    final started = DateTime.now();
    var ready = false;
    try {
      ready = await Future<bool>.microtask(BridgeInstaller.isRuntimeReady);
    } catch (_) {
      // 读失败按没装好处理，交给安装页
    }
    const minimum = Duration(milliseconds: 500);
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minimum) {
      await Future<void>.delayed(minimum - elapsed);
    }
    if (!mounted) return;
    setState(() => isRuntimeReady = ready);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _fadeController.forward();
    if (!mounted) return;
    setState(() => _showStartup = false);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void updateTheme() => setState(() {
    final setting = config.setting.personalizationOptions;
    themeMode = setting.themeMode;
    themeColor = setting.themeColor;
  });

  ThemeMode themeMode = config.setting.personalizationOptions.themeMode;
  ThemeColor themeColor = config.setting.personalizationOptions.themeColor;

  @override
  Widget build(BuildContext context) {
    final home = isRuntimeReady
        ? AppShell(key: PageKeyProvider.shellKey)
        : BridgeInstallPage(
            onReady: () => setState(() => isRuntimeReady = true),
          );

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
        home: Platform.isAndroid
            ? _StartupGate(
                showSplash: _showStartup,
                fade: _fadeController,
                themeColor: themeColor,
                child: home,
              )
            : home,
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

/// 初始化页 → 主界面的淡出：初始化页盖在上面，淡掉后露出主界面
class _StartupGate extends StatelessWidget {
  const _StartupGate({
    required this.showSplash,
    required this.fade,
    required this.themeColor,
    required this.child,
  });

  final bool showSplash;
  final Animation<double> fade;
  final ThemeColor themeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (showSplash)
          AnimatedBuilder(
            animation: fade,
            builder: (context, _) => IgnorePointer(
              child: Opacity(
                opacity: (1 - fade.value).clamp(0.0, 1.0),
                child: StartupPage(themeColor: themeColor),
              ),
            ),
          ),
      ],
    );
  }
}
