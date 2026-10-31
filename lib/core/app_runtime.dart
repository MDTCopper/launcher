/// 本次进程的运行角色与跨层标记
///
/// 服务模式（`--cloud-service`）没有 UI / 窗口 / 托盘，任务链里凡是「要弹窗 / 要窗口」
/// 的地方都得先问这里，不能直接调 `showDialog` / `windowManager`
class AppRuntime {
  AppRuntime._();

  /// 无界面服务进程：不 `runApp`、不建窗口、不建托盘、不放在线服务
  static bool headless = false;

  /// 服务模式里这次启动需要人处理（冲突 / 缺 Java / 版本没了 / 启动失败）
  ///
  /// 置位后任务链中止，服务进程把请求写进 pending 并拉起 UI
  static bool needsUi = false;
  static String needsUiReason = '';

  static void markNeedsUi(String reason) {
    needsUi = true;
    needsUiReason = reason;
  }

  static void clearNeedsUi() {
    needsUi = false;
    needsUiReason = '';
  }
}
