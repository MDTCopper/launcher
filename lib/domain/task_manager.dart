import 'dart:async';
import 'dart:io';
import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/ui/util/info/log_list.dart';
import 'package:copperlauncher_main/ui/util/info/notification.dart';
import 'package:copperlauncher_main/util/downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:window_manager/window_manager.dart';

import '../core/constant/app_constant.dart';
import '../data/local_asset.dart';
import '../util/app_paths.dart';

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
    setProgressBar();
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
    _notify();
    _handleTask(task);
  }

  void _changeTaskStatus(String taskId, TaskStatus changeTo) {
    //外部更改任务状态
    Task? task = _tasks[taskId];
    if (task == null) {
      debugPrint('该任务不存在');
      return;
    }
    if ([TaskStatus.failed, TaskStatus.cancel].contains(task.status)) {
      debugPrint('该任务已失效');
      return;
    }
    if (task.status == TaskStatus.completed) {
      debugPrint('该任务已完成');
      return;
    }
    if (changeTo == task.status) return;
    task = task.copyWith(status: changeTo);
    _tasks[taskId] = task;
    _notify();
    _handleTask(task);
  }

  void _handleTask(Task task) {
    switch (task.type) {
      case TaskType.check:
        _check();
        break;
      case TaskType.launch:
        if (task is! LaunchTask) {
          debugPrint('任务类型错误 task ${task.runtimeType}'); //
          _tasks[task.id] = task.copyWith(status: TaskStatus.failed);
          _notify();
          return;
        }
        _launch(task);
        break;

      case TaskType.download:
        if (task is! DownloadTask) {
          debugPrint('任务类型错误 task ${task.runtimeType}'); //
          _tasks[task.id] = task.copyWith(status: TaskStatus.failed);
          _notify();
          return;
        }
        switch (task.status) {
          case TaskStatus.process:
            _download(task);
            break;
          case TaskStatus.paused:
            cancelTokens[task.id]?.cancel('paused');
            break;
          case TaskStatus.cancel:
            cancelTokens[task.id]?.cancel('cancel');
            break;
          case TaskStatus.pending:
            throw UnimplementedError();
          case TaskStatus.completed:
            throw UnimplementedError();
          case TaskStatus.failed:
            throw UnimplementedError();
        }
        break;

      case TaskType.fileValidation:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  }

  void _download(DownloadTask task) async {
    final url = task.url;
    if (url.isEmpty) {
      debugPrint('下载路径为空'); //
      _tasks[task.id] = task.copyWith(status: TaskStatus.failed);
      _notify();
      return;
    }

    final cancelToken = CancelToken();

    cancelTokens[task.id] = cancelToken;

    late File file;

    try {
      final path = task.path;

      int downloadSize = task.totalSize;

      if (path == null) {
        file = File((await AppPaths.rootLocal).toString());
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
      } else {
        file = File(path);
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        downloadSize = await file.length();
      }

      await dr.download(
        url,
        file.path,
        cancelToken: cancelToken,
        deleteOnError: false,
        fileAccessMode: FileAccessMode.append,
        onProgress: (receive, total) {
          if (total <= 0) return;
          final currentTotal = downloadSize + total;
          final currentReceive = downloadSize + receive;
          final progress = currentReceive / currentTotal;

          task = task.copyWith(
            path: path,
            progress: progress,
            downloadedSize: currentReceive,
            totalSize: currentTotal,
          );

          _tasks[task.id] = task;
          _notify();
        },
        onSpeedUpdate: (s) {
          task = task.copyWith(speed: s);
          _tasks[task.id] = task;
          _notify();
        },
      );

      //检查文件完整性
      if (await file.length() != task.totalSize) Exception('文件因未知原因损坏');

      _tasks[task.id] = task.copyWith(
        progress: 1.0,
        status: TaskStatus.completed,
      );

      addLog(LogEntry(LogType.success, '游戏文件下载完成,存储路径:\n${task.path} '));
      addNotice(
        icon: Icons.check,
        title: '下载完成',
        content: '游戏文件下载完成,存储路径:\n${task.path} ',
      );

      final foldIndex = config.versionOptions.versionFolds.indexWhere(
        (fold) => fold.path == task.mindustry.path,
      );
      if (foldIndex != -1) {
        config.versionOptions.versionFolds[foldIndex].versions.add(
          task.mindustry,
        );
        config.save();
      } else {
        debugPrint('无法同步配置文件');
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (e.toString().contains('paused')) {
        } else if (e.toString().contains('cancel')) {
          Future.delayed(Duration(milliseconds: 300), () async {
            await file.delete();
          });
          debugPrint('取消下载:${e.toString()}');

          addLog(LogEntry(LogType.info, '已取消下载'));
          addNotice(icon: Icons.info_outline, title: '取消', content: '已取消下载');
        }
      } else {
        _tasks[task.id] = task.copyWith(status: TaskStatus.failed);
        debugPrint('网络错误：${e.toString()}');
        await file.delete();

        addLog(LogEntry(LogType.error, '网络错误:$e'));
        addNotice(icon: Icons.error_outline, title: '错误', content: '网络错误:$e');
      }
    } catch (e) {
      _tasks[task.id] = task.copyWith(status: TaskStatus.failed);
      debugPrint('未知错误${e.toString()}');
      await file.delete();

      addLog(LogEntry(LogType.error, '未知错误:$e'));
      addNotice(icon: Icons.error_outline, title: '致命错误！', content: '未知错误:$e');
    } finally {
      cancelTokens.remove(task.id);
      _notify();
    }
  }

  void _check() {}

  void _launch(LaunchTask task) {}

  void dispose() {
    _taskStreamController.close();
  }
}

enum TaskType { check, launch, download, fileValidation }

enum TaskStatus {
  pending,
  process,
  completed,
  failed,
  paused,
  cancel,
} //待定，进行中，完成，失败，暂停，取消

//todo 更改为可监听，task自己完成自己的任务，不依赖于任务管理器，只在task自身状态改变时回调管理器更新
//task类有自己的基类，这个基类支持自定义任务程序，复杂任务可以继承task基类
class Task implements Listenable {
  String id;
  TaskType type;
  TaskStatus status;
  double? progress;
  String? describe;
  String? details;
  late Widget displayWidget;
  late final DateTime createTime;

  final Set<VoidCallback> listeners = {};

  Task({
    //常规任务
    required this.id,
    required this.type,
    this.status = TaskStatus.process,
    this.progress,
    this.describe,
    this.details,
    DateTime? createTime,
  }) : createTime = createTime ?? DateTime.now();

  Task copyWith({
    //用来改变某些变量，比如状态和描述
    TaskStatus? status,
    double? progress,
    String? describe,
    String? details,
  }) {
    return Task(
      id: id,
      type: type,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      describe: describe ?? this.describe,
      createTime: createTime,
    );
  }

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  void update() {
    for (var it in listeners) {
      it.call();
    }
  }

  void runTask(){

  }

}

class DownloadTask extends Task {
  final String url;
  final String? path;
  final int totalSize; //存储字节大小
  final int downloadedSize;
  final double speed;
  final Mindustry mindustry;

  DownloadTask({
    //下载任务
    required super.id,
    required this.mindustry,
    super.type = TaskType.download,
    super.status,
    super.progress,
    super.describe,
    super.details,
    super.createTime,

    required this.url,
    required this.path,
    this.totalSize = 0,
    this.downloadedSize = 0,
    this.speed = 0.0,
  });

  @override
  DownloadTask copyWith({
    TaskStatus? status,
    double? progress,
    String? describe,
    String? details,
    String? path,
    int? totalSize,
    int? downloadedSize,
    double? downloadSpeed,
    double? speed,
  }) {
    return DownloadTask(
      id: id,
      type: type,
      url: url,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      describe: describe ?? this.describe,
      details: details ?? this.details,
      path: path ?? this.path,
      totalSize: totalSize ?? this.totalSize,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      speed: speed ?? this.speed,
      createTime: createTime,
      mindustry: mindustry,
    );
  }
}

class LaunchTask extends Task {
  LaunchTask({
    required super.id,
    super.type = TaskType.launch,
    super.status,
    super.progress,
    super.describe,
    super.details,
    super.createTime,
  });
}

class CheckTask extends Task {
  CheckTask({
    required super.id,
    super.type = TaskType.check,
    super.status,
    super.progress,
    super.describe,
    super.details,
    super.createTime,
  });
}
