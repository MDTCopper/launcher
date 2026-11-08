import 'package:flutter/foundation.dart';

/// 「下一步外壳」开关（2026-11-08，用户：算了，直接让 debug 跑新 UI 即可）
///
/// - **debug 构建一律走新外壳**（顶栏 + 左侧导航），方便直接看效果
/// - Release 仍走旧外壳，等试点验收后再整体切换
///
/// 想临时回旧外壳：把这里改成 `false` 重新跑。
bool get useNextShell => kDebugMode;
