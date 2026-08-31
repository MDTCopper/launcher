import 'package:flutter/material.dart';

import '../../copper_launcher.dart';
import '../../shell/app_shell.dart';

class PageKeyProvider {
  PageKeyProvider._();

  ///CopperLauncherState用来更新最外层Widget，主要是更新主题
  static final themeKey = GlobalKey<CopperLauncherState>();

  ///AppShellState
  static final shellKey = GlobalKey<AppShellState>();

  ///NavigatorState子路由，主要用于根路由中控制子路由
  static final navigatorKey = GlobalKey<NavigatorState>();
}
