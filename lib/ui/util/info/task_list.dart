import 'dart:async';
import 'package:copperlauncher_main/ui/util/animation/pixel_slide_transition.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:flutter/material.dart';
import '../../../domain/task_manager.dart';

//UI
class TaskList extends StatefulWidget {
  const TaskList({super.key});

  @override
  State<StatefulWidget> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  final List<Task> _tasks = [];

  final _key = GlobalKey<AnimatedListState>();

  StreamSubscription<List<Task>>? _taskSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeTaskStream();
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    super.dispose();
  }

  List<Task> _findTasksFormList(List<Task> tasks) {
    return tasks.where((task) {
      return [TaskStatus.process].contains(task.status);
    }).toList();
  }

  void _subscribeTaskStream() {
    _tasks.addAll(_findTasksFormList(taskManager.currentTasks));

    _taskSubscription?.cancel();

    _taskSubscription = taskManager.stream.listen((tasks) {
      final newTasks = _findTasksFormList(tasks);

      newTasks.sort((a, b) => a.createTime.compareTo(b.createTime));
      _updateList(newTasks);

      setState(() {
        _tasks.clear();
        _tasks.addAll(newTasks);
      });
    });
  }

  void _updateList(List<Task> newTasks) {
    for (final oldTask in _tasks) {//todo 可以尝试弄一个完成和失败特效
      final needRemove = !newTasks.any((newTask) => newTask.id == oldTask.id);
      if (needRemove) {
        final index = _tasks.indexOf(oldTask);
        if (index != -1 && _key.currentState != null) {
          _key.currentState!.removeItem(
            index,
            (context, animation) => _buildRemoveAnimation(oldTask, animation),
            duration: const Duration(milliseconds: 800),
          );
        }
      }
    }

    for (final newTask in newTasks) {
      final needAdd = !_tasks.any((oldTask) => oldTask.id == newTask.id);
      if (needAdd && _key.currentState != null) {
        _key.currentState!.insertItem(newTasks.indexOf(newTask));
      }
    }
  }

  Widget _buildRemoveAnimation(Task task, Animation<double> animation) {
    final sizeFactor = CurvedAnimation(
      parent: animation,
      curve: Interval(0.0, 0.4, curve: Curves.easeIn),
    );

    final position = Tween<Offset>(
      begin: Offset(0.8, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Interval(0.3, 0.9, curve: Curves.easeIn),
      ),
    );

    final opacity = CurvedAnimation(
      parent: animation,
      curve: Interval(0.5, 0.9, curve: Curves.easeIn),
    );

    final Widget widget = SizeTransition(
      sizeFactor: sizeFactor,
      child: SlideTransition(
        position: position,
        child: FadeTransition(
          opacity: opacity,
          child: TaskItem(task: task, onCancel: () {}),
        ),
      ),
    );

    return widget;
  }

  Widget _buildNoTaskPage() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, color: Colors.white60, size: 48),
          Text(
            '没有任务啦 ~(‾▾‾~)~',
            style: TextStyle(color: Colors.white60, fontSize: 28),
          ),
          SizedBox(height: 50),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = _buildNoTaskPage();

    final list = AnimatedList(
      key: _key,
      initialItemCount: _tasks.length,
      padding: EdgeInsets.symmetric(horizontal: 8),
      itemBuilder: (context, index, animation) {
        final task = _tasks[index];

        final position = Tween<Offset>(
          begin: Offset(0.3, 0.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        );

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: position,
            child: TaskItem(
              task: task,
              onCancel: () {
                changeTaskStatus(task.id, TaskStatus.cancel);
              },
            ),
          ),
        );
      },
    );

    final Widget widget = AnimatedSwitcher(
      duration: Duration(milliseconds: 600),
      child: _tasks.isEmpty ? note : list,
      transitionBuilder: (child, animation) {
        final position = Tween<Offset>(
          begin: Offset(0.0, 40.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Interval(0.6, 1.0, curve: Curves.easeOutBack),
            reverseCurve: Interval(0.0, 0.4, curve: Curves.easeInBack),
          ),
        );

        final opacity = CurvedAnimation(
          parent: animation,
          curve: Interval(0.6, 1.0),
          reverseCurve: Interval(0.0, 0.4),
        );

        return PixelSlideAnimation(
          position: position,
          child: FadeTransition(opacity: opacity, child: child),
        );
      },
    );

    return widget;
  }
}

//套一层UI壳子
class TaskItem extends StatelessWidget {
  final Task task;
  final VoidCallback? onCancel;

  const TaskItem({super.key, required this.task, this.onCancel});

  IconData _getIcon(TaskType type) {
    switch (type) {
      case TaskType.fileValidation:
      case TaskType.check:
        return Icons.search;
      case TaskType.launch:
        return Icons.rocket_launch;
      case TaskType.download:
        return Icons.download;
    }
  }

  String _getTitle(TaskType type) {
    switch (type) {
      case TaskType.fileValidation:
      case TaskType.check:
        return '校验';
      case TaskType.launch:
        return '启动';
      case TaskType.download:
        return '下载';
    }
  }

  String _formatProgress(double? progress) {
    if (progress == null) return '0.0%';
    return '${(progress * 100).toStringAsFixed(1)} %';
  }

  String _formatDownloadProgress(DownloadTask task) {
    int downloadedSize = task.downloadedSize;
    int totalSize = task.totalSize;
    double downloadSpeed = task.speed;

    if (<int>[downloadedSize, totalSize].contains(0)) return '等待连接...';

    String progress;
    String speed;

    if (totalSize < 1024) {
      progress =
          '${downloadedSize.toStringAsFixed(1)}/${totalSize.toStringAsFixed(1)}B';
    } else if (totalSize < 1024 * 1024) {
      progress =
          '${(downloadedSize / 1024).toStringAsFixed(1)}/${(totalSize / 1024).toStringAsFixed(1)}KB';
    } else if (totalSize < 1024 * 1024 * 1024) {
      progress =
          '${(downloadedSize / 1024 / 1024).toStringAsFixed(1)}/${(totalSize / 1024 / 1024).toStringAsFixed(1)}MB';
    } else {
      progress =
          '${(downloadedSize / 1024 / 1024 / 1024).toStringAsFixed(1)}/${(totalSize / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
    }

    if (downloadSpeed < 1024) {
      speed = '${(downloadSpeed).toStringAsFixed(1)}B/S';
    } else if (downloadSpeed < 1024 * 1024) {
      speed = '${(downloadSpeed / 1024).toStringAsFixed(1)}KB/S';
    } else {
      speed = '${(downloadSpeed / 1024 / 1024).toStringAsFixed(1)}MB/S';
    }
    if(downloadSpeed <= 0){
      speed = '0B/S';
    }

    String status = '$progress($speed)';

    return status;
  }

  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.secondaryContainer,
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium??DefaultTextStyle.of(context).style,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_getIcon(task.type),size: 32),
                SizedBox(width: 4),
                Text(
                  _getTitle(task.type),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900 ,color: theme.colorScheme.secondary),
                ),
                Expanded(child: SizedBox()),
                if (onCancel != null)
                  ReboundButton(
                    onTap: onCancel,
                    child: Icon(Icons.close),
                  ),
              ],
            ),
            LinearProgressIndicator(value: task.progress),
            if (task.progress != null)
              Row(
                children: [
                  if (task is DownloadTask)
                    Text(_formatDownloadProgress(task as DownloadTask)),
                  Expanded(child: SizedBox()),
                  Text(_formatProgress(task.progress)),
                ],
              ),

            Text(task.describe ?? 'unknown task'),

            if (task.details != null) Text(task.details!),
            Text(task.createTime.toString().split(' ').last.split('.').first,style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
