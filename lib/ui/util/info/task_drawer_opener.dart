import 'dart:async';

import 'package:copperlauncher_main/ui/util/animation/animated_opacity_size.dart';
import 'package:copperlauncher_main/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';

import '../../../domain/task.dart';
import '../../../domain/task_manager.dart';
import '../widget/feature_button.dart';

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
      _taskNum = _findTasksFormList(tasks).length;
      setState(() {});
    });
  }

  List<Task> _findTasksFormList(List<Task> tasks) {
    return tasks.where((task) {
      return [TaskStatus.process].contains(task.status);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    double? progress = taskManager.totalProcessProgress;

    final theme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedOpacitySize(
          child:
              _taskNum != 0
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 8),
                      Text(
                        '${_taskNum == 0 ? 1 : _taskNum} 项任务',
                        style: theme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        height: 8,
                        child: LinearProgressIndicator(
                          borderRadius: BorderRadius.circular(4),
                          value: _taskNum == 0 ? 1.0 : progress,
                        ),
                      ),
                    ],
                  )
                  : null,
        ),
        SizedBox(width: 8),
        ReboundButton(
          backgroundColor: Colors.transparent,
          child: Icon(Icons.chrome_reader_mode_outlined),
          onTap: () {
            Scaffold.of(
              PageKeyProvider.navigatorKey.currentContext!,
            ).openEndDrawer();
          },
        ),
      ],
    );
  }
}
