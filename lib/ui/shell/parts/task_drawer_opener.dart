import 'dart:async';

import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/util/animation/animated_opacity_size.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';

import '../../../domain/task.dart';
import '../../../domain/task_manager.dart';

class TaskDrawerOpener extends StatefulWidget {
  const TaskDrawerOpener({super.key});

  @override
  State<StatefulWidget> createState() => _TaskDrawerOpenerState();
}

class _TaskDrawerOpenerState extends State<TaskDrawerOpener> {
  int _taskNum = 0;
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

  void _subscribeTaskStream() {
    _taskSubscription?.cancel();
    _taskSubscription = taskManager.stream.listen((tasks) {
      final n = _findTasksFormList(tasks).length;
      // 只有条数变化才重绘窗口组件；进度条由 totalProcessProgress 的
      // ValueListenable 精确驱动，避免每次 progress 变化整树 rebuild。
      if (n != _taskNum) {
        setState(() => _taskNum = n);
      }
    });
  }

  List<Task> _findTasksFormList(List<Task> tasks) {
    return tasks.where((task) {
      return [TaskStatus.process].contains(task.status);
    }).toList();
  }

  Widget _buildProcessBar() {
    final theme = Theme.of(context).textTheme;
    final show = _taskNum != 0;

    final child = !show
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_taskNum == 0 ? 1 : _taskNum} 项任务',
                style: theme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 8,
                child: ValueListenableBuilder<double?>(
                  valueListenable: taskManager.totalProcessProgress,
                  builder: (context, progress, _) => LinearProgressIndicator(
                    borderRadius: BorderRadius.circular(4),
                    value: progress,
                  ),
                ),
              ),
              SizedBox(width: 8),
            ],
          );

    return AnimatedOpacitySize(child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProcessBar(),
        HintLayer(
          hint: '打开任务列表',
          child: ReboundButton(
            backgroundColor: Colors.transparent,
            child: Icon(Icons.chrome_reader_mode_outlined),
            onTap: () {
              Scaffold.of(
                PageKeyProvider.navigatorKey.currentContext!,
              ).openEndDrawer();
            },
          ),
        ),
      ],
    );
  }
}
