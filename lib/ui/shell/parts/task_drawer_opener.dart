import 'dart:async';

import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/animation/animated_opacity_size.dart';
import 'package:copper_launcher/ui/util/animation/switcher_builder.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/ui/vars.dart';
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
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: () => Scaffold.of(
        PageKeyProvider.navigatorKey.currentContext!,
      ).openEndDrawer(),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          border: Border(right: BorderSide(color: colors.border, width: 2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_taskNum == 0 ? 1 : _taskNum} 项任务',
              style: theme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              height: 20,
              child: ValueListenableBuilder<double?>(
                valueListenable: taskManager.totalProcessProgress,
                builder: (context, progress, _) => CircularProgressIndicator(
                  value: progress,
                  padding: const EdgeInsets.all(4),
                  strokeWidth: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showProcess = _taskNum != 0;
    return HintLayer(
      hint: '打开任务列表',
      child: AnimatedSwitcher(
        duration: animationDuration,
        transitionBuilder: SwitcherBuilders.fadeSlide(),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: .centerRight,
          children: [...previousChildren, ?currentChild],
        ),
        child: showProcess
            ? _buildProcessBar()
            : ReboundButton(
                backgroundColor: Colors.transparent,
                child: Icon(Icons.checklist),
                onTap: () {
                  Scaffold.of(
                    PageKeyProvider.navigatorKey.currentContext!,
                  ).openEndDrawer();
                },
              ),
      ),
    );
  }
}
