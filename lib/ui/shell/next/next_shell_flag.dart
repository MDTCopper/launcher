import 'package:flutter/foundation.dart';

/// 「下一步外壳」试点开关（2026-11-08）
///
/// 规则：**只在 debug 构建 + 开关打开**时启用新外壳；Release 永远走旧外壳。
/// - 关掉：`flutter run --dart-define=NEXT_SHELL=false`
/// - 打开：默认就是开的（debug 下）
///
/// 分步推进：A 顶栏 → B 左侧导航 → C 右侧抽屉；每一步都可以单独回退。
const bool _nextShellRequested = bool.fromEnvironment(
  'NEXT_SHELL',
  defaultValue: true,
);

/// 是否使用新外壳（顶栏等）
bool get useNextShell => kDebugMode && _nextShellRequested;
