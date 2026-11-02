import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/sync_proxy.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 代理窗口的固定尺寸：标题 36 + 阶段/说明/进度，取消按钮放在标题栏右侧，不会被裁
const Size syncProxyWindowSize = Size(420, 180);

/// 临时云同步代理窗口：启动前同步超过 3 秒时由服务拉起，同步收尾就自己关
///
/// 进程里只有这一棵树：不建 shell、托盘、在线服务（见 `main` 的 `--sync-proxy` 分流）
class SyncProxyApp extends StatefulWidget {
  const SyncProxyApp({super.key, this.versionId});

  /// 拉起时带的版本 id；状态文件还没写出来时先用它显示
  final String? versionId;

  @override
  State<SyncProxyApp> createState() => _SyncProxyAppState();
}

class _SyncProxyAppState extends State<SyncProxyApp> {
  /// 状态文件的轮询间隔
  static const pollInterval = Duration(milliseconds: 300);

  /// 状态这么久没刷新就认为服务进程已经没了，窗口自己关
  static const statusStaleAfter = Duration(seconds: 20);

  /// 状态文件读不到时空转几次再关窗（服务可能正在写临时文件）
  static const missingTolerance = 3;

  SyncProxyStatus? _status;
  bool _cancelRequested = false;
  bool _quitting = false;
  int _missingTicks = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_quitting) return;
    final status = await SyncProxyStore.readStatus();
    if (!mounted || _quitting) return;
    if (status == null) {
      _missingTicks++;
      if (_missingTicks >= missingTolerance) await _quit();
      return;
    }
    _missingTicks = 0;
    setState(() {
      _status = status;
      _cancelRequested = _cancelRequested || status.cancelRequested;
    });
    // 服务卡死 / 崩溃时别让这个窗口一直挂着
    if (!status.phase.isTerminal &&
        DateTime.now().difference(status.updatedAt) > statusStaleAfter) {
      await _quit();
      return;
    }
    if (status.phase.isTerminal) {
      // 让「正在启动游戏」这一句闪一下再关
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await _quit();
    }
  }

  Future<void> _requestCancel() async {
    if (_cancelRequested) return;
    setState(() => _cancelRequested = true);
    await SyncProxyStore.requestCancel();
  }

  /// 关窗退进程：服务已经不需要这个窗口了
  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    _pollTimer?.cancel();
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<void> _startDragging() async {
    try {
      await windowManager.startDragging();
    } catch (_) {}
  }

  ThemeColor get _themeColor {
    try {
      return config.setting.personalizationOptions.themeColor;
    } catch (_) {
      // 配置还没就绪也不该让代理窗口起不来
      return ThemeColor.copper;
    }
  }

  ThemeMode get _themeMode {
    try {
      return config.setting.personalizationOptions.themeMode;
    } catch (_) {
      return ThemeMode.system;
    }
  }

  /// 版本名：优先查配置里的 tag，查不到就退回 id 前几位
  String _versionLabel(SyncProxyStatus? status) {
    final versionId = status?.versionId ?? widget.versionId;
    if (versionId == null || versionId.isEmpty) return '云存档';
    try {
      final version = config.versionOptions.findVersionById(versionId);
      if (version != null) return version.tag;
    } catch (_) {}
    return versionId.length > 8 ? versionId.substring(0, 8) : versionId;
  }

  String _elapsedLabel(SyncProxyStatus? status) {
    final elapsed =
        status?.elapsed ?? const Duration(seconds: 0);
    final seconds = elapsed.inSeconds;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return minutes == 0 ? '$rest 秒' : '$minutes 分 $rest 秒';
  }

  String _messageLabel(SyncProxyStatus? status) {
    final message = status?.message;
    return message == null || message.isEmpty ? '准备检查云端存档' : message;
  }

  String _cancelLabel(SyncProxyStatus? status) {
    if (!_cancelRequested) return '取消同步';
    if (status?.phase == SyncProxyPhase.finishing) return '正在收尾…';
    return '正在取消…';
  }

  @override
  Widget build(BuildContext context) {
    // 启动器本身排除语义树；这里同样处理，避免 Windows UIA 客户端触发引擎问题
    return ExcludeSemantics(
      child: MaterialApp(
        title: '云同步',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, _themeColor),
        darkTheme: buildTheme(Brightness.dark, _themeColor),
        themeMode: _themeMode,
        // 必须用 MaterialApp 下面的 Builder context：直接用外层 context 取
        // Theme.of(context).extension<AppColors>() 会拿到 null（MaterialApp 之上没有主题）
        home: Builder(
          builder: (context) => Scaffold(body: _buildPanel(context)),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.pageBackground,
      child: Column(
        children: [
          _buildTitleBar(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  /// 无边框窗口的自绘标题栏：整条都能拖动
  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => unawaited(_startDragging()),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_sync_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '云同步代理',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            // 取消按钮放标题栏左侧：不依赖右对齐，窗口再窄也不会被裁掉
            ReboundButton(
              onTap: _cancelRequested
                  ? null
                  : () => unawaited(_requestCancel()),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(_cancelLabel(_status)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final phase = _status?.phase ?? SyncProxyPhase.checking;
    final progress = _status?.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                phase.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '已耗时 ${_elapsedLabel(_status)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_versionLabel(_status)} · ${_messageLabel(_status)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress, minHeight: 4),
        ],
      ),
    );
  }
}
