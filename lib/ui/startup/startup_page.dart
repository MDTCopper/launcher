import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:flutter/material.dart';

/// 当前主题对应的物品图标
String startupItemAsset(ThemeColor themeColor) => switch (themeColor) {
  ThemeColor.copper => 'assets/images/copper.png',
  ThemeColor.titanium => 'assets/images/titanium.png',
  ThemeColor.thorium => 'assets/images/thorium.png',
  ThemeColor.plastanium => 'assets/images/plastanium.png',
};

/// 预解码启动图标：Flutter 第一帧就带上图标，避免首帧空白后再补出来
Future<void> precacheStartupItem(ThemeColor themeColor) async {
  final completer = Completer<void>();
  final stream = AssetImage(
    startupItemAsset(themeColor),
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
    onError: (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
  );
  stream.addListener(listener);
  await completer.future;
}

/// Android 启动初始化页：当前主题对应的物品图标，等初始化完再淡入主界面
class StartupPage extends StatelessWidget {
  const StartupPage({super.key, required this.themeColor});

  final ThemeColor themeColor;

  /// 普通启动的系统 splash 是白底，这里保持一致，避免原生 → Flutter 时背景闪一下
  static const _background = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: Center(
        child: Image.asset(
          startupItemAsset(themeColor),
          width: 64,
          height: 64,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        ),
      ),
    );
  }
}
