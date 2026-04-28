import 'dart:async';
import 'dart:io';

import 'package:copperlauncher_main/domain/task.dart';
import 'package:copperlauncher_main/util/downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:window_manager/window_manager.dart';

import '../core/constant/app_constant.dart';

final dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 20), //链接超时
    receiveTimeout: const Duration(seconds: 300), //下载超时
    headers: {
      'User-Agent': 'MindustryModDownloader',
      'Authorization': 'token $githubToken',
    },
  ),
);

final dr = Downloader();

final Map<String, CancelToken> cancelTokens = {};

final taskManager = TaskManager();

void addTask(Task task) => taskManager._addTask(task);

void changeTaskStatus(String taskId, TaskStatus changeTo) =>
    taskManager._changeTaskStatus(taskId, changeTo);

class TaskManager {
  static final _instance = TaskManager._();
  TaskManager._();
  factory TaskManager() => _instance;

  final Map<String, Task> _tasks = {};

  final StreamController<List<Task>> _taskStreamController =
      StreamController.broadcast();

  Stream<List<Task>> get stream => _taskStreamController.stream;

  double? get totalProcessProgress {
    double? progress;
    final tasks =
        _tasks.values.where((task) {
          return [TaskStatus.process].contains(task.status);
        }).toList();
    int measurableTasks = 0;
    for (final task in tasks) {
      if (task.progress != null) {
        progress = progress ?? 0.0 + task.progress!;
        measurableTasks++;
      }
    }
    if (progress != null) {
      progress /= measurableTasks;
    }
    return progress;
  }

  List<Task> get currentTasks => List.from(_tasks.values);

  //通知UI变化
  void _notify() {
    _taskStreamController.add(List.from(_tasks.values));
    if (Platform.isWindows) setProgressBar();
  }

  Timer? _timer;
  void setProgressBar() {
    final progress = totalProcessProgress;

    final tasks = _tasks.values.where((task) {
      return [TaskStatus.process].contains(task.status);
    });
    //完成结算
    if (progress == 1.0 || (progress == null && tasks.isEmpty)) {
      _timer?.cancel();
      _timer = null;
      Future.delayed(const Duration(seconds: 1), () {
        windowManager.setProgressBar(-1);
      });
      return;
    }

    if (_timer == null || !_timer!.isActive) {
      _timer = Timer(const Duration(seconds: 1), () {
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
    _taskStreamController.close();
  }
}
