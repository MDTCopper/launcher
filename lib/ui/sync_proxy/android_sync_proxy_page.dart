import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/sync_proxy.dart';
import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 安卓无界面快捷启动时的云同步代理页：和桌面代理窗口同一套阶段 / 取消语义。
/// 启动前云同步超过 3 秒才显示；同步结束或游戏界面起来后回黑。
class AndroidSyncProxyPage extends StatefulWidget {
  const AndroidSyncProxyPage({super.key});

  @override
  State<AndroidSyncProxyPage> createState() => _AndroidSyncProxyPageState();
}

class _AndroidSyncProxyPageState extends State<AndroidSyncProxyPage> {
  static const _pollInterval = Duration(milliseconds: 300);
  static const _showDelay = Duration(seconds: 3);

  SyncProxyStatus? _status;
  bool _cancelRequested = false;
  bool _overlayHidden = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final status = await SyncProxyStore.readStatus();
    if (!mounted) return;
    if (status == null) {
      if (_status != null) setState(() => _status = null);
      return;
    }
    setState(() {
      _status = status;
      _cancelRequested = _cancelRequested || status.cancelRequested;
    });
  }

  Future<void> _requestCancel() async {
    if (_cancelRequested) return;
    setState(() => _cancelRequested = true);
    await SyncProxyStore.requestCancel();
  }

  String _versionLabel(SyncProxyStatus? status) {
    final versionId = status?.versionId;
    if (versionId == null || versionId.isEmpty) return '云存档';
    try {
      final version = config.versionOptions.findVersionById(versionId);
      if (version != null) return version.tag;
    } catch (_) {}
    return versionId.length > 8 ? versionId.substring(0, 8) : versionId;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final visible =
        status != null &&
        !status.phase.isTerminal &&
        DateTime.now().difference(status.startedAt) >= _showDelay;
    if (!visible) {
      return const ColoredBox(color: Colors.black);
    }
    if (!_overlayHidden) {
      _overlayHidden = true;
      // 静默启动的黑幕是原生 View，盖在 Flutter 上；代理页要可见就得把它撤掉
      unawaited(AndroidCall.hide());
    }
    return MaterialApp(
      title: '云同步',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark, ThemeColor.copper),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 180,
              child: _buildPanel(context, status),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, SyncProxyStatus status) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.pageBackground,
      child: Column(
        children: [
          Container(
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
                ReboundButton(
                  onTap: _cancelRequested
                      ? null
                      : () => unawaited(_requestCancel()),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(_cancelRequested ? '正在取消…' : '取消同步'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        status.phase.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '已耗时 ${_elapsedLabel(status)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_versionLabel(status)} · ${_messageLabel(status)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: status.progress, minHeight: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _elapsedLabel(SyncProxyStatus status) {
    final seconds = DateTime.now().difference(status.startedAt).inSeconds;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return minutes == 0 ? '$rest 秒' : '$minutes 分 $rest 秒';
  }

  String _messageLabel(SyncProxyStatus status) {
    final message = status.message;
    return message == null || message.isEmpty ? '准备检查云端存档' : message;
  }
}
