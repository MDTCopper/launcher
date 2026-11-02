import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/launch_request.dart';

/// 一次快捷启动从哪里来
///
/// 桌面快捷方式只投 `--launch-version <id>`，来源本身不改变桌面路由；
/// 留这个枚举是为了日志与平台分流——只有 [androidShortcut] 走宿主通道。
enum LaunchSource {
  /// Windows 桌面 `.lnk`
  desktopShortcut,

  /// Android 桌面快捷方式（宿主持有 versionId，经 `ShortcutLaunch` 取回）
  androidShortcut,

  /// 直接敲命令行的 `--launch-version`
  cli;

  /// Android 没有独立服务进程，只能交给宿主通道
  bool get isAndroid => this == LaunchSource.androidShortcut;

  bool get isDesktop => !isAndroid;
}

/// 这次快捷启动该交给谁
enum LaunchRoute {
  /// UI 在线：把请求交给 UI（单实例 focus / pending 文件）
  uiOnline,

  /// UI 不在、云服务在线：把请求交给服务（requests 文件）
  serviceOnline,

  /// 两个都不在：本进程进入无界面云服务模式，由它拉起游戏
  startService,

  /// Android：走宿主通道，由 `ShortcutLaunch` 等 shell / 校验桥后启动游戏
  android;

  /// 桌面来源的路由（[android] 之外）
  bool get isDesktop => this != LaunchRoute.android;

  /// 需要本进程直接进服务模式
  bool get runsServiceHere => this == LaunchRoute.startService;

  /// 请求已经交给别的进程 / 宿主，本进程退出即可
  bool get isHandedOff => !runsServiceHere;
}

/// 写一张启动票据：`pending/` 与 `requests/` 形状相同，由另一侧读走
typedef LaunchTicketWriter =
    Future<void> Function({required String versionId, required String reason});

/// 探测某个角色是否在线：返回 true 表示那个进程还活着
typedef LaunchProbe = Future<bool> Function();

/// Android 真正启动游戏的执行器：由 `ShortcutLaunch` 传入，入口只负责路由与调用
typedef AndroidLauncher = Future<void> Function(String versionId);

/// 统一快速启动入口：**唯一**决定「这次快捷启动交给谁」的地方
///
/// 分两层，都是为了能直接替换 `main` 里那段 if 分流：
/// - [routeFor] 是纯函数，不碰 IO，来源 + 两个在线探针就能算出路由；
/// - [dispatch] 在桌面来源上读 [GameSessionStore] 的 pid 探针，并把请求写进
///   `pending/`（给 UI）或 `requests/`（给服务）。Android 来源只返回
///   [LaunchRoute.android] 并调用 [AndroidLauncher] 回调：宿主通道、等 shell、校验桥、
///   `ShortcutSession.mark`、`GameInstance.launch` 都还留在现有 `ShortcutLaunch`，
///   入口只做路由与调用，不把 UI 依赖搬进来。
///
/// 本类不弹 UI、不退出进程、不启动服务进程，这三件事由 `main` 按返回值做。
class QuickLaunchEntry {
  QuickLaunchEntry._();

  /// UI 在线时写进 `pending/` 的原因（沿用改造前 `main` 的字符串，日志还能对上）
  static const String reasonUiOnline = 'ui_online';

  /// UI 不在、服务在线时写进 `requests/` 的原因
  static const String reasonUiOffline = 'ui_offline';

  /// 纯分流决策：同一个纯函数覆盖桌面与 Android，不读文件、不看平台
  ///
  /// - Android → [LaunchRoute.android]（不看探针：安卓没有独立服务进程）
  /// - 桌面来源一律同构：UI 在线优先于服务，两个都不在才本进程进服务模式
  static LaunchRoute routeFor({
    required LaunchSource source,
    required bool uiRunning,
    required bool serviceRunning,
  }) {
    if (source.isAndroid) return LaunchRoute.android;
    if (uiRunning) return LaunchRoute.uiOnline;
    if (serviceRunning) return LaunchRoute.serviceOnline;
    return LaunchRoute.startService;
  }

  /// 分流并落票据，返回 [LaunchRoute] 供 `main` 决定退出 / 进服务 / 交给宿主
  ///
  /// 桌面来源：
  /// - [LaunchRoute.uiOnline] → 写 `pending/`（reason [reasonUiOnline]），本进程退出；
  /// - [LaunchRoute.serviceOnline] → 写 `requests/`（reason [reasonUiOffline]），本进程退出；
  /// - [LaunchRoute.startService] → **不写文件**，调用方自己进服务模式。
  ///
  /// Android 来源：直接返回 [LaunchRoute.android]，探针与写入器都不会被调用
  /// （游戏启动由 `ShortcutLaunch` 走宿主通道完成）。
  ///
  /// Android 来源：返回 [LaunchRoute.android] 并调用 [androidLauncher] 执行真正的启动
  /// （宿主通道、等 shell、校验桥、`ShortcutSession.mark`、`GameInstance.launch` 仍在
  /// `ShortcutLaunch` 里；入口只做路由与调用，不把 UI 依赖搬进来）。
  ///
  /// 探针与写入器都可注入，单测不必碰真实文件系统；不传就用 [GameSessionStore]。
  static Future<LaunchRoute> dispatch(
    LaunchRequest request, {
    LaunchSource source = LaunchSource.cli,
    LaunchProbe? uiProbe,
    LaunchProbe? serviceProbe,
    LaunchTicketWriter? pendingWriter,
    LaunchTicketWriter? requestWriter,
    AndroidLauncher? androidLauncher,
  }) async {
    if (source.isAndroid) {
      await androidLauncher?.call(request.versionId);
      return LaunchRoute.android;
    }

    final route = routeFor(
      source: source,
      uiRunning: await (uiProbe ?? GameSessionStore.isUiRunning)(),
      serviceRunning: await (serviceProbe ?? GameSessionStore.isServiceRunning)(),
    );

    switch (route) {
      case LaunchRoute.uiOnline:
        await (pendingWriter ?? GameSessionStore.writePending)(
          versionId: request.versionId,
          reason: reasonUiOnline,
        );
        break;
      case LaunchRoute.serviceOnline:
        await (requestWriter ?? GameSessionStore.writeRequest)(
          versionId: request.versionId,
          reason: reasonUiOffline,
        );
        break;
      case LaunchRoute.startService:
      case LaunchRoute.android:
        // 两者都不写票据：前者本进程接手，后者归宿主
        break;
    }
    return route;
  }
}
