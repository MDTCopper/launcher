import 'dart:async';

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

class _TaskDrawerOpenerState extends State<TaskDrawerOpener>
    with SingleTickerProviderStateMixin {
  int _taskNum = 0;
  StreamSubscription<List<Task>>? _taskSubscription;

  late final AnimationController _controller;

  bool _showProgress = false;

  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    )..addStatusListener((status) {
      if (status.isDismissed) {
        setState(() {
          _showProgress = false;
        });
      }
    });
    _subscribeTaskStream();
    super.initState();
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _subscribeTaskStream() {
    _taskSubscription?.cancel();
    _taskSubscription = taskManager.stream.listen((tasks) {
      _taskNum = _findTasksFormList(tasks).length;
      changeAnimation(_taskNum > 0);
    });
  }

  void changeAnimation(bool forward) {
    setState(() {
      if (forward) {
        _showProgress = true;
        if (!_controller.isForwardOrCompleted) _controller.forward();
      } else {
        if (_controller.isForwardOrCompleted) _controller.reverse();
      }
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 150),
      child: Row(
        spacing: 16,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_taskNum != 0 || _showProgress)
            GestureDetector(
              onTap: () {
                Scaffold.of(
                  PageKeyProvider.innerKey.currentContext!,
                ).openEndDrawer();
              },
              child: FadeTransition(
                opacity: _controller,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_taskNum == 0 ? 1 : _taskNum}项任务处理中',
                      style: TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    SizedBox(
                      width: 100,
                      height: 8,
                      child: LinearProgressIndicator(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.white,
                        backgroundColor: Colors.white30,
                        value: _taskNum == 0 ? 1.0 : progress,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          ReboundButton(
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
            hoverElevation: 4.0,
            child: Icon(Icons.chrome_reader_mode_outlined, color: Theme.of(context).appBarTheme.iconTheme?.color),

            onTap: () {
              Scaffold.of(
                PageKeyProvider.innerKey.currentContext!,
              ).openEndDrawer();
            },
          ),
        ],
      ),
    );
  }
}
