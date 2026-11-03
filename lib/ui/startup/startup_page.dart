import 'package:flutter/material.dart';

/// Android 启动初始化页：空白白底，等初始化完再淡入主界面
class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  /// 普通启动的系统 splash 是白底，这里保持一致，避免原生 → Flutter 时背景闪一下
  static const _background = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: _background);
  }
}
