import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/domain/task.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

final Map<String, CancelToken> cancelTokens = {};

final taskManager = TaskManager();

///添加任务后自动开始
void addTask(Task task) => taskManager._addTask(task);

void changeTaskStatus(String taskId, TaskStatus changeTo) =>
    taskManager._changeTaskStatus(taskId, changeTo);

class TaskManager {
  static final _instance = TaskManager._();
  TaskManager._();
  factory TaskManager() => _instance;

  /// 通知刷新窗口：高频 progress 更新被合并到该间隔内，最多每窗口发一次。
  static const _kNotifyInterval = Duration(milliseconds: 100);
  static const _kBarDelay = Duration(seconds: 1);

  final Map<String, Task> _tasks = {};

  final StreamController<List<Task>> _taskStreamController =
      StreamController.broadcast();

  /// 聚合进度：只读监听源，UI 可精确刷新而无需每次 build 遍历全表。
  final ValueNotifier<double?> _totalProgress = ValueNotifier<double?>(null);
  ValueListenable<double?> get totalProcessProgress => _totalProgress;

  Stream<List<Task>> get stream => _taskStreamController.stream;

  List<Task> get currentTasks => List.from(_tasks.values);

  static bool _isProcessing(Task task) => task.status == TaskStatus.process;

  // ── 通知节流 ──
  // 窗口外首变化立即发，窗口内标记 pending，
  // 窗口结束时补发一次合并后的最新快照（trailing，保证最新状态必达）
  // 不随每次 notify 重置计时器 → 连续高频更新被限频到
  Timer? _notifyTimer;
  bool _pending = false;

  void _notify() {
    if (_notifyTimer != null) {
      _pending = true;
      return;
    }
    _emit();
    _notifyTimer = Timer(_kNotifyInterval, () {
      _notifyTimer = null;
      if (_pending) {
        _pending = false;
        _emit();
      }
    });
  }

  void _emit() {
    _totalProgress.value = _computeTotalProcessProgress();
    _taskStreamController.add(List.from(_tasks.values));
    if (Platform.isWindows) setProgressBar();
  }

  double? _computeTotalProcessProgress() {
    double sum = 0;
    int measurable = 0;
    for (final task in _tasks.values.where(_isProcessing)) {
      if (task.progress != null) {
        sum += task.progress!;
        measurable++;
      }
    }
    return measurable == 0 ? null : sum / measurable;
  }

  //通知UI变化
  Timer? _setBarTimer;
  Timer? _clearBarTimer;

  void setProgressBar() {
    final progress = _totalProgress.value;
    final hasProcessing = _tasks.values.any(_isProcessing);

    //完成结算：无进行中任务，或总进度到位 → 1 秒后清除任务栏进度条
    if (progress == 1.0 || (progress == null && !hasProcessing)) {
      _setBarTimer?.cancel();
      _setBarTimer = null;
      _clearBarTimer ??= Timer(_kBarDelay, () {
        windowManager.setProgressBar(-1);
        _clearBarTimer = null;
      });
      return;
    }

    //仍有进行中任务：取消待清除，1 秒防抖后更新进度
    _clearBarTimer?.cancel();
    _clearBarTimer = null;
    if (_setBarTimer == null || !_setBarTimer!.isActive) {
      _setBarTimer = Timer(_kBarDelay, () {
        windowManager.setProgressBar(progress ?? 2.0);
      });
    }
  }

  void _addTask(Task task) {
    _tasks[task.id] = task;
    task.addListener(_notify);
    task.start();
  }

  void _changeTaskStatus(String taskId, TaskStatus changeTo) {
    //外部更改任务状态
    final task = _tasks[taskId];
    if (task == null) {
      debugPrint('该任务不存在');
      return;
    }
    if (changeTo == task.status) return;
    if ([TaskStatus.failed, TaskStatus.cancel].contains(task.status)) {
      debugPrint('该任务已失效');
      return;
    }
    if (task.status == TaskStatus.completed) {
      debugPrint('该任务已完成');
      return;
    }

    switch (changeTo) {
      case TaskStatus.pending:
      case TaskStatus.completed:
      case TaskStatus.failed:
        debugPrint('任务的状态不可更改为完成/待定/失败');
        break;
      case TaskStatus.process:
        task.start();
        break;
      case TaskStatus.paused:
        task.pause();
        break;
      case TaskStatus.cancel:
        task.cancel();
        break;
    }
  }

  void dispose() {
    _notifyTimer?.cancel();
    _setBarTimer?.cancel();
    _clearBarTimer?.cancel();
    _totalProgress.dispose();
    _taskStreamController.close();
  }

  /// 仅供测试：清空单例状态，隔离用例（TaskManager 是单例，无外部重置入口）。
  @visibleForTesting
  void debugReset() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _setBarTimer?.cancel();
    _setBarTimer = null;
    _clearBarTimer?.cancel();
    _clearBarTimer = null;
    _pending = false;
    for (final task in _tasks.values) {
      task.removeListener(_notify);
    }
    _tasks.clear();
    _totalProgress.value = null;
  }
}
