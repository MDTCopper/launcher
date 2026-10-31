import 'package:copper_launcher/core/app_config.dart';
import 'package:flutter/material.dart';

/// Android 启动初始化页：当前主题对应的物品图标，等初始化完再刷入主界面
class StartupPage extends StatelessWidget {
  const StartupPage({super.key, required this.themeColor});

  final ThemeColor themeColor;

  String get _itemAsset => switch (themeColor) {
    ThemeColor.copper => 'assets/images/copper.png',
    ThemeColor.titanium => 'assets/images/titanium.png',
    ThemeColor.thorium => 'assets/images/thorium.png',
    ThemeColor.plastanium => 'assets/images/plastanium.png',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Image.asset(
          _itemAsset,
          width: 64,
          height: 64,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        ),
      ),
    );
  }
}
