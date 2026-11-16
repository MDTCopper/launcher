import 'package:copper_launcher/domain/preview/blueprint_library.dart';
import 'package:copper_launcher/domain/preview/blueprint_preview_service.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 「渲染蓝图」任务：把一批蓝图预览串行渲染进缓存
///
/// 单例：同一时刻只有一个实例，重复请求并入同一批；游戏运行中暂停出队，
/// 避免和游戏抢 IO 与 CPU；取消会清空队列，已渲染的结果保留在缓存里
class BlueprintRenderTask extends Task {
  BlueprintRenderTask._();

  static const Duration _gamePollInterval = Duration(seconds: 1);

  static final List<_BlueprintRenderRequest> _queue = [];
  static final Set<String> _queuedKeys = {};
  static BlueprintRenderTask? _active;
  static int _completedCount = 0;

  /// 当前批次，没有在跑时为 null
  static BlueprintRenderTask? get active => _active;

  /// 当前状态行（渲染中 / 等待游戏结束 / 已完成）
  String? statusText;

  bool _cancelled = false;
  bool _rendering = false;

  /// 请求渲染一张蓝图；[size] 为期望的最长边像素，>= 2048 走导出
  static void request(BlueprintLibraryEntry entry, {int size = 160}) {
    final key = '${entry.path}@$size';
    if (!_queuedKeys.add(key)) return;
    _queue.add(_BlueprintRenderRequest(entry, size));
    final active = _active;
    if (active == null) {
      _start();
    } else {
      active._refreshProgress();
    }
  }

  static void _start() {
    _completedCount = 0;
    final task = BlueprintRenderTask._();
    _active = task;
    addTask(task);
  }

  @override
  String get displayTitle => '渲染蓝图';

  @override
  IconData get displayIcon => Icons.image_outlined;

  @override
  void cancel() {
    _cancelled = true;
    _queue.clear();
    _queuedKeys.clear();
    super.cancel();
  }

  @override
  Future<void> runTask() async {
    addLog(.info, '开始渲染蓝图预览：${_queue.length} 张', tag: 'BlueprintPreview');
    _refreshProgress();
    try {
      while (!_cancelled && _queue.isNotEmpty) {
        await _pauseWhileGameRunning();
        if (_cancelled) break;
        final request = _queue.removeAt(0);
        _rendering = true;
        await _render(request);
        _rendering = false;
        if (_cancelled) break;
        _completedCount += 1;
        _refreshProgress();
      }
      if (_cancelled) return;
      progress = 1;
      statusText = '已完成 $_completedCount 张';
      status = TaskStatus.completed;
      addLog(.info, '蓝图预览渲染完成：$_completedCount 张', tag: 'BlueprintPreview');
    } finally {
      if (identical(_active, this)) _active = null;
      updateDisplay();
      // 取消后又有新请求：交给下一批
      if (_queue.isNotEmpty) _start();
    }
  }

  /// 游戏运行中不出队；每秒查一次，游戏结束自动继续
  Future<void> _pauseWhileGameRunning() async {
    while (!_cancelled && _isGameRunning) {
      statusText = '游戏运行中，暂停渲染';
      updateDisplay();
      await Future<void>.delayed(_gamePollInterval);
    }
    if (!_cancelled) {
      statusText = '渲染中';
      updateDisplay();
    }
  }

  Future<void> _render(_BlueprintRenderRequest request) async {
    final entry = request.entry;
    try {
      if (request.size >= BlueprintPreviewService.maxExportSize) {
        final bytes = await BlueprintPreviewService.instance.exportPng(
          entry,
          maxSize: request.size,
        );
        _logResult(entry, rendered: bytes != null, exported: true);
      } else {
        final image = await BlueprintPreviewService.instance.preview(
          entry,
          maxSize: request.size,
        );
        _logResult(entry, rendered: image != null, exported: false);
      }
    } catch (error) {
      addLog(
        .error,
        '渲染蓝图预览失败 [${entry.name}]：$error',
        tag: 'BlueprintPreview',
      );
    }
  }

  void _logResult(
    BlueprintLibraryEntry entry, {
    required bool rendered,
    required bool exported,
  }) {
    if (rendered) {
      addLog(
        .info,
        '${exported ? '已导出' : '已渲染'}蓝图预览 [${entry.name}]',
        tag: 'BlueprintPreview',
      );
      return;
    }
    final reason = entry.hasModContent == true ? '含 mod 内容，跳过' : '无法渲染';
    addLog(.info, '蓝图预览跳过 [${entry.name}]：$reason', tag: 'BlueprintPreview');
  }

  void _refreshProgress() {
    final total = _completedCount + _queue.length + (_rendering ? 1 : 0);
    progress = total == 0 ? 1 : _completedCount / total;
    statusText ??= '渲染中';
    updateDisplay();
  }

  /// 与 launcher_tray 的 _isGameRunning 同口径：有 process 状态的启动任务
  static bool get _isGameRunning => taskManager.currentTasks.any(
    (task) => task is LaunchMindustryTask && task.status == TaskStatus.process,
  );

  @override
  Widget buildDisplayWidget(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          children: [
            Icon(displayIcon, size: 32),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                displayTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
            if (statusLabel != null)
              Text(statusLabel!, style: theme.textTheme.bodySmall),
            if (canCancel)
              IconButton(
                onPressed: cancel,
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
        LinearProgressIndicator(value: progress),
        Text(statusText ?? formatProgress(), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _BlueprintRenderRequest {
  const _BlueprintRenderRequest(this.entry, this.size);

  final BlueprintLibraryEntry entry;
  final int size;
}
