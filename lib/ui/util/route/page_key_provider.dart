import 'package:flutter/material.dart';

import '../../copper_launcher.dart';
import '../../shell/app_shell.dart';

class PageKeyProvider {
  PageKeyProvider._();

  static final _themeKey = GlobalKey<CopperLauncherState>();

  static GlobalKey<CopperLauncherState> get themeKey => _themeKey;

  static final _shellKey = GlobalKey<AppShellState>();

  static GlobalKey<AppShellState> get shellKey => _shellKey;

  static final _navigatorKey = GlobalKey<NavigatorState>();

  static GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;
}