/// 启动器进程的形态（用户口径的「两种形态」+ 两种短命进程）
enum AppForm {
  /// 完整启动器界面：shell / 托盘 / 在线服务 / 任务抽屉
  launcherUi('启动器 UI'),

  /// 无界面云存档服务：不 runApp、不建窗口，跟游戏 / 上传活到底
  cloudService('无界面云服务'),

  /// 桌面快捷方式触发进程：只判分流、投递请求后退出
  quickTrigger('快捷启动触发进程'),

  /// 云同步代理：只在启动前同步过久时短暂出现
  syncProxy('云同步代理');

  const AppForm(this.label);

  final String label;
}

/// 本次进程的运行角色与跨层标记
///
/// 服务模式（`--cloud-service`）没有 UI / 窗口 / 托盘，任务链里凡是「要弹窗 / 要窗口」
/// 的地方都得先问这里，不能直接调 `showDialog` / `windowManager`
class AppRuntime {
  AppRuntime._();

  /// 当前形态：日志头与排障时一眼能看出这是哪种进程
  static AppForm form = AppForm.launcherUi;

  /// 本次进程启动时刻：冷启动时间线统一从它算
  static DateTime startedAt = DateTime.now();

  /// 距进程入口的毫秒数
  static int get elapsedMs => DateTime.now().difference(startedAt).inMilliseconds;

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
