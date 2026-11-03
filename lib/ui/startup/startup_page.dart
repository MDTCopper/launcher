import 'package:flutter/material.dart';

/// Android 启动初始化页：空白底，系统深色给深底、浅色给白底，跟原生 splash 对齐
class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  static const _lightBackground = Color(0xFFFFFFFF);
  static const _darkBackground = Color(0xFF121212);

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return ColoredBox(color: dark ? _darkBackground : _lightBackground);
  }
}
