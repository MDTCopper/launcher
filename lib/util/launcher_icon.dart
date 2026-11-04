import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/generated/android_call.g.dart';

/// 桌面图标跟随 App 内主题：安卓上切到对应 activity-alias，其他平台没有这层
Future<void> applyLauncherIcon(ThemeColor color) async {
  if (!Platform.isAndroid) return;
  await AndroidCall.setLauncherIcon(color.name);
}
