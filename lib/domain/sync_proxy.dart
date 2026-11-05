import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/ui/sync_proxy/sync_proxy_app.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

/// 启动前云同步的临时「代理窗口」：文件协议 + 服务端生命周期
///
/// 服务进程同步前把状态写进 `<数据根>/cloud-service/sync-status.json`；同步超过
/// [syncProxyShowDelay] 还没结束才拉起 `--sync-proxy` 进程读它显示进度；玩家点
/// 「取消同步」只写一个 `sync-cancel` 标记，服务在安全检查点读，**正在写存档时
/// 不硬停**，只提示「正在收尾」并在当前步骤结束后启动游戏

/// 同步超过这个时长才值得弹代理窗口；更短的同步弹出来只会闪一下
const Duration syncProxyShowDelay = Duration(seconds: 3);

/// 状态文件（服务端写、代理进程读）
const String syncStatusFileName = 'sync-status.json';

/// 取消标记（代理进程写、服务端在安全检查点读；存在即取消）
const String syncCancelFileName = 'sync-cancel';

/// 启动前同步的阶段；[needsUi] 表示冲突 / 缺东西，要主界面处理
enum SyncProxyPhase {
  checking('检查云端'),
  downloading('下载存档'),
  restoring('写入存档'),
  finishing('正在收尾'),
  launching('正在启动游戏'),
  needsUi('需要界面处理'),
  finished('同步结束');

  const SyncProxyPhase(this.label);

  /// 代理窗口直接显示的中文阶段名
  final String label;

  /// 这两个阶段还能在安全点跳过本次同步；一旦开始写存档就不能硬停
  bool get canSkipSync => this == checking || this == downloading;

  /// 已经不必再等：代理窗口看到这些阶段就自己关
  bool get isTerminal =>
      this == launching || this == needsUi || this == finished;

  static SyncProxyPhase? tryParse(String? raw) {
    for (final phase in values) {
      if (phase.name == raw) return phase;
    }
    return null;
  }
}

/// `sync-status.json` 的内容
class SyncProxyStatus {
  const SyncProxyStatus({
    required this.versionId,
    required this.phase,
    required this.startedAt,
    required this.updatedAt,
    this.cancelRequested = false,
    this.message,
    this.progress,
  });

  final String versionId;
  final SyncProxyPhase phase;

  /// 同步开始时刻：代理窗口的「已耗时」从这里算
  final DateTime startedAt;

  /// 最后一次刷新时刻：代理窗口据此判断服务进程是否还活着
  final DateTime updatedAt;

  final bool cancelRequested;
  final String? message;

  /// 0~1；下载有明确进度时才有
  final double? progress;

  Duration get elapsed => updatedAt.difference(startedAt);

  Map<String, dynamic> toJson() => {
    'versionId': versionId,
    'phase': phase.name,
    'startedAt': startedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'cancelRequested': cancelRequested,
    'message': message,
    'progress': progress,
  };

  /// 坏字段一律给默认值：代理窗口不该因为一个写坏的 JSON 崩掉
  factory SyncProxyStatus.fromJson(Map<String, dynamic> json) =>
      SyncProxyStatus(
        versionId: json['versionId'] as String? ?? '',
        phase:
            SyncProxyPhase.tryParse(json['phase'] as String?) ??
            SyncProxyPhase.checking,
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        cancelRequested: json['cancelRequested'] as bool? ?? false,
        message: json['message'] as String?,
        progress: (json['progress'] as num?)?.toDouble(),
      );
}

/// 状态文件与取消标记的读写：原子写，读坏了当作没有
abstract class SyncProxyStore {
  static String get statusPath =>
      p.join(AppPaths.cloudService, syncStatusFileName);

  static String get cancelPath =>
      p.join(AppPaths.cloudService, syncCancelFileName);

  /// 代理进程 pid：UI 启动时据此关掉可能还挂着的代理窗口
  static String get proxyPidPath =>
      p.join(AppPaths.cloudService, 'sync-proxy.json');

  static Future<void> writeProxyPid() async {
    final file = File(proxyPidPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'pid': pid, 'at': DateTime.now().toIso8601String()}),
      flush: true,
    );
  }

  static Future<int?> readProxyPid() async {
    try {
      final json = jsonDecode(await File(proxyPidPath).readAsString());
      if (json is Map && json['pid'] is int) return json['pid'] as int;
    } catch (_) {}
    return null;
  }

  static Future<void> clearProxyPid() async {
    try {
      final file = File(proxyPidPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// UI 已经起来了：代理没有存在意义，直接关掉，别压在 UI 上
  static Future<void> closeIfRunning() async {
    final proxyPid = await readProxyPid();
    if (proxyPid != null &&
        proxyPid != pid &&
        GameProcessWatch.isAlive(proxyPid)) {
      Process.killPid(proxyPid);
      addLog(.info, '云同步代理：UI 已启动，关闭残留代理进程 $proxyPid', tag: 'CloudService');
    }
    await clearProxyPid();
  }

  static Future<SyncProxyStatus?> readStatus() async {
    try {
      final file = File(statusPath);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return SyncProxyStatus.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeStatus(SyncProxyStatus status) =>
      _atomicWrite(statusPath, status.toJson());

  static Future<bool> isCancelRequested() async {
    try {
      return await File(cancelPath).exists();
    } catch (_) {
      return false;
    }
  }

  /// 代理窗口点的「取消同步」：只落一个标记，由服务在安全检查点读
  static Future<void> requestCancel() async {
    final file = File(cancelPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(DateTime.now().toIso8601String(), flush: true);
  }

  static Future<void> clearCancel() async {
    try {
      final file = File(cancelPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 清掉状态与取消标记：上一次进程崩溃留下的脏文件会让下次同步秒取消
  static Future<void> clear() async {
    for (final path in [statusPath, cancelPath]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// 先写临时文件再改名：代理进程随时在读，不能让它读到写了一半的 JSON
  static Future<void> _atomicWrite(
    String path,
    Map<String, dynamic> json,
  ) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(path);
  }
}

/// 同步已经跑了 [elapsed]，是否值得为它拉起代理窗口
bool shouldShowSyncProxy(Duration elapsed) => elapsed >= syncProxyShowDelay;

/// 取消标记在某个阶段被读到时的处理决定
enum SyncProxyCancelAction {
  /// 没有取消请求，继续同步
  continueSync,

  /// 还在检查 / 下载：跳过本次同步，直接启动游戏
  skipSyncAndLaunch,

  /// 已经进入写存档：不能硬停，等当前步骤结束再启动
  finishThenLaunch,
}

SyncProxyCancelAction decideOnCancelRequest({
  required SyncProxyPhase phase,
  required bool cancelRequested,
}) {
  if (!cancelRequested) return SyncProxyCancelAction.continueSync;
  if (phase.canSkipSync) return SyncProxyCancelAction.skipSyncAndLaunch;
  if (phase == SyncProxyPhase.restoring) {
    return SyncProxyCancelAction.finishThenLaunch;
  }
  return SyncProxyCancelAction.continueSync;
}

/// 把恢复流程的阶段文字（`CloudSaveService.restore` 的 `onStatus`）映射成代理阶段
///
/// 恢复内部先备份 / 读清单 / 下载文件，最后覆盖本机；只有「覆盖」之后才算真正的
/// 写存档阶段，之前都还能在下一个安全点放弃
SyncProxyPhase? syncProxyPhaseOfRestoreStatus(String statusText) {
  if (statusText.contains('覆盖') || statusText.contains('写入')) {
    return SyncProxyPhase.restoring;
  }
  if (statusText.contains('备份') ||
      statusText.contains('下载') ||
      statusText.contains('清单') ||
      statusText.contains('地址')) {
    return SyncProxyPhase.downloading;
  }
  return null;
}

/// 把代理窗口作为**独立进程**拉起：服务 / UI 都不用为它建完整 shell
abstract class SyncProxyLauncher {
  static Future<bool> spawn({required String versionId}) async {
    // 安卓由同一进程里的 AndroidSyncProxyPage 显示，不拉起桌面代理进程
    if (Platform.isAndroid) return false;
    try {
      await Process.start(
        Platform.resolvedExecutable,
        ['--sync-proxy', '--launch-version', versionId],
        mode: ProcessStartMode.detached,
        workingDirectory: File(Platform.resolvedExecutable).parent.path,
      );
      addLog(
        .info,
        '云同步代理：同步超过 ${syncProxyShowDelay.inSeconds} 秒，已拉起代理窗口',
        tag: 'CloudService',
      );
      return true;
    } catch (error) {
      addLog(
        .warning,
        '云同步代理：拉起代理窗口失败 ${error.toString()}',
        tag: 'CloudService',
      );
      return false;
    }
  }
}

/// 服务端那一半：写状态、超过 3 秒拉代理、在安全检查点消费取消标记
///
/// 生命周期跟着一次「启动前同步」走：`CloudAutoSync.beforeLaunch` 在无界面服务里
/// 创建它，同步结束（成功 / 取消 / 出错）时收尾；UI 进程不建 gate，也不写文件
class SyncProxyGate {
  SyncProxyGate._({required this.versionId, required this.tag})
    : _startedAt = DateTime.now();

  /// 心跳：刷新 updatedAt，代理窗口靠它判断服务是否还活着，也在这里发现取消
  static const heartbeatInterval = Duration(milliseconds: 800);

  /// 状态文件在收尾后再留一会儿，让代理窗口来得及读到终态
  static const statusRetention = Duration(seconds: 5);

  /// 拉主界面要时间：needsUi 状态多留一会儿
  static const needsUiRetention = Duration(seconds: 10);

  final String versionId;
  final String tag;
  final DateTime _startedAt;

  SyncProxyPhase _phase = SyncProxyPhase.checking;
  String? _message = '检查云端存档';
  double? _progress;
  bool _cancelRequested = false;
  bool _closed = false;
  bool _proxySpawned = false;

  Timer? _heartbeatTimer;
  Timer? _spawnTimer;
  Timer? _clearTimer;

  /// 心跳 / 阶段更新 / 收尾可能同时写盘：排成一条链，后写的不会被先写的盖掉
  Future<void> _writeChain = Future<void>.value();

  static SyncProxyGate? _active;

  /// 当前服务端 gate（诊断用）
  static SyncProxyGate? get active => _active;

  static bool get isActive {
    final gate = _active;
    return gate != null && !gate._closed;
  }

  /// 无界面服务的启动前同步开始时调用；UI 进程返回 null（不写状态文件）
  ///
  /// 写状态失败一律吞掉：代理窗口是可选的，绝不能因为它拦住游戏启动
  static Future<SyncProxyGate?> startForHeadlessService({
    required String versionId,
    required String tag,
  }) async {
    if (!AppRuntime.headless) return null;
    await _active?.disposeQuietly();
    try {
      // 安卓代理页在进程内，提前点的取消不能被服务端 reset 掉
      if (!Platform.isAndroid) {
        await SyncProxyStore.clearCancel();
      }
      final gate = SyncProxyGate._(versionId: versionId, tag: tag);
      _active = gate;
      gate._startTimers();
      await gate._flushStatus();
      addLog(.info, '云同步代理：开始计时 [$tag]', tag: 'CloudService');
      return gate;
    } catch (error) {
      addLog(
        .warning,
        '云同步代理：状态文件写不出来 ${error.toString()}',
        tag: 'CloudService',
      );
      return null;
    }
  }

  /// 服务启动 / 退出时清掉上一次进程留下的状态与取消标记
  static Future<void> resetStale() async {
    final previous = _active;
    _active = null;
    await previous?.disposeQuietly();
    await SyncProxyStore.clear();
  }

  void _startTimers() {
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => unawaited(_beat()),
    );
    _spawnTimer = Timer(
      syncProxyShowDelay,
      () => unawaited(_spawnProxyWindow()),
    );
  }

  Future<void> _beat() async {
    if (_closed) return;
    await _flushStatus();
    if (!await SyncProxyStore.isCancelRequested()) return;
    _cancelRequested = true;
    // 写存档阶段收到取消：不能硬停，先把界面切到「正在收尾」，等 restore 自己结束
    if (_phase == SyncProxyPhase.restoring) {
      await _reportFinishing();
    }
  }

  Future<void> _spawnProxyWindow() async {
    if (_closed || _proxySpawned) return;
    _proxySpawned = true;
    // UI 已经在线就没必要再弹代理；服务继续把这次同步跑完
    if (await GameSessionStore.isUiRunning()) {
      addLog(.info, '云同步代理：UI 已在线，跳过代理窗口', tag: 'CloudService');
      return;
    }
    await SyncProxyLauncher.spawn(versionId: versionId);
  }

  /// 推进阶段；代理窗口据 [message] 显示当前在干什么
  Future<void> reportPhase(
    SyncProxyPhase phase, {
    String? message,
    double? progress,
  }) async {
    if (_closed) return;
    _phase = phase;
    _message = message ?? phase.label;
    _progress = progress;
    await _flushStatus();
  }

  /// 恢复流程的阶段文字（`onStatus` 回调）直接转过来，不认识就只更新说明
  void reportRestoreStatus(String statusText) {
    if (_closed) return;
    _phase = syncProxyPhaseOfRestoreStatus(statusText) ?? _phase;
    _message = statusText;
    unawaited(_flushStatus());
  }

  /// 给 `CloudAutoSync` 的安全检查点用：true = 停下本次同步，直接启动游戏
  ///
  /// 检查 / 下载阶段返回 true；已进入写存档阶段返回 false，只把状态改成
  /// 「正在收尾」——恢复必须完整落盘，硬停会留下半套存档
  Future<bool> shouldStopSyncing() async {
    if (_closed) return false;
    if (!await SyncProxyStore.isCancelRequested()) return false;
    _cancelRequested = true;
    switch (decideOnCancelRequest(phase: _phase, cancelRequested: true)) {
      case SyncProxyCancelAction.continueSync:
        return false;
      case SyncProxyCancelAction.skipSyncAndLaunch:
        addLog(
          .info,
          '云同步代理：${_phase.label}时收到取消，跳过本次同步直接启动 [$tag]',
          tag: 'CloudService',
        );
        _phase = SyncProxyPhase.launching;
        _message = '已取消同步，直接启动游戏';
        await _flushStatus();
        return true;
      case SyncProxyCancelAction.finishThenLaunch:
        await _reportFinishing();
        return false;
    }
  }

  Future<void> _reportFinishing() async {
    if (_closed || _phase == SyncProxyPhase.finishing) return;
    _phase = SyncProxyPhase.finishing;
    _message = '取消已收到，正在收尾；收尾结束就启动游戏';
    addLog(
      .info,
      '云同步代理：恢复已在写存档，取消推迟到当前步骤结束 [$tag]',
      tag: 'CloudService',
    );
    await _flushStatus();
  }

  /// 同步结束、游戏马上启动：代理窗口看到 launching 后自己退出
  Future<void> finishLaunching({String? message}) async {
    if (_closed) return;
    _closed = true;
    _heartbeatTimer?.cancel();
    _spawnTimer?.cancel();
    if (_phase != SyncProxyPhase.launching) {
      _phase = SyncProxyPhase.launching;
      _message = message ?? '同步完成，正在启动游戏';
    } else if (message != null) {
      _message = message;
    }
    await _flushStatus();
    _scheduleClear(statusRetention);
  }

  /// 冲突 / 缺东西：交给主界面处理，代理窗口看到 needsUi 后自己退出
  Future<void> markNeedsUi({String? message}) async {
    if (_closed) return;
    _closed = true;
    _heartbeatTimer?.cancel();
    _spawnTimer?.cancel();
    _phase = SyncProxyPhase.needsUi;
    _message = message ?? '需要主界面处理，正在打开启动器';
    await _flushStatus();
    _scheduleClear(needsUiRetention);
  }

  Future<void> _flushStatus() {
    _writeChain = _writeChain.then((_) async {
      try {
        await SyncProxyStore.writeStatus(
          SyncProxyStatus(
            versionId: versionId,
            phase: _phase,
            startedAt: _startedAt,
            updatedAt: DateTime.now(),
            cancelRequested: _cancelRequested,
            message: _message,
            progress: _progress,
          ),
        );
      } catch (error) {
        addLog(
          .warning,
          '云同步代理：状态写盘失败 ${error.toString()}',
          tag: 'CloudService',
        );
      }
    });
    return _writeChain;
  }

  void _scheduleClear(Duration delay) {
    _clearTimer?.cancel();
    _clearTimer = Timer(delay, () {
      if (!identical(_active, this)) return;
      _active = null;
      unawaited(SyncProxyStore.clear());
    });
  }

  /// 放下计时器但不写终态：被下一次同步替换时用
  Future<void> disposeQuietly() async {
    _closed = true;
    _heartbeatTimer?.cancel();
    _spawnTimer?.cancel();
    _clearTimer?.cancel();
    if (identical(_active, this)) _active = null;
  }
}

/// 代理窗口进程（`--sync-proxy`）的入口：由 `main` 分流调用
///
/// 调用前基础层要就绪（`AppPaths.init` / `Log.init` / `initAppConfig`）；这里只建
/// 一个固定大小的小窗口，**不建 shell / 托盘 / 在线服务**
Future<void> runSyncProxy({String? versionId}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: syncProxyWindowSize,
    minimumSize: syncProxyWindowSize,
    maximumSize: syncProxyWindowSize,
    center: true,
    alwaysOnTop: true,
    title: '云同步',
    titleBarStyle: TitleBarStyle.hidden,
  );
  // 这里不显示窗口：先 show 会露出窗口默认底色，要等首帧画完再显示；
  // 代理进程带 --launch-version，Windows runner 已压制首次自动显示，只能由这里补
  await windowManager.waitUntilReadyToShow(options, null);
  // WindowOptions 的 size 在 Windows 上按物理像素落，而 Flutter 布局用的是
  // 逻辑像素；125% 缩放下 420x180 会变成 336x144，底部/右侧内容被裁。
  // 按 DPR 反算一次物理尺寸，保证逻辑区域仍是 420x180。
  final dpr = WidgetsBinding
      .instance
      .platformDispatcher
      .views
      .first
      .devicePixelRatio;
  final logicalSize = syncProxyWindowSize;
  final physicalSize = Size(
    (logicalSize.width * dpr).roundToDouble(),
    (logicalSize.height * dpr).roundToDouble(),
  );
  try {
    await windowManager.setMinimumSize(physicalSize);
    await windowManager.setMaximumSize(physicalSize);
    await windowManager.setSize(physicalSize);
    await windowManager.center();
  } catch (_) {}
  addLog(
    .info,
    '云同步代理：窗口就绪${versionId == null ? '' : '（$versionId）'}'
        ' dpr=$dpr 物理=${physicalSize.width.toInt()}x${physicalSize.height.toInt()}',
    tag: 'CloudService',
  );
  await SyncProxyStore.writeProxyPid();
  runApp(SyncProxyApp(versionId: versionId));
  // 与主窗口同一口径：首帧渲染完再显示，避免先露出一块空白小窗
  await WidgetsBinding.instance.endOfFrame;
  await windowManager.show();
  await windowManager.focus();
}
