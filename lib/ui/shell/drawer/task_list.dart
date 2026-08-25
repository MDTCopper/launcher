import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/animation/pixel_slide_transition.dart';
import 'package:copper_launcher/ui/components/scroll/desktop_scroll_view.dart';
import 'package:flutter/material.dart';

import '../../../domain/task.dart';
import '../../../domain/task_manager.dart';

class TaskList extends StatefulWidget {
  const TaskList({super.key});

  @override
  State<StatefulWidget> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  final List<Task> _tasks = [];

  final _key = GlobalKey<AnimatedListState>();

  StreamSubscription<List<Task>>? _taskSubscription;
  final controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _subscribeTaskStream();
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    controller.dispose();
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
    final state = _key.currentState;
    if (state == null) return;
    final removed =
        _tasks.where((t) => !newTasks.any((n) => n.id == t.id)).toList()
          ..sort((a, b) => _tasks.indexOf(b).compareTo(_tasks.indexOf(a)));
    for (final task in removed) {
      final index = _tasks.indexOf(task);
      if (index != -1) {
        state.removeItem(
          index,
          (context, animation) => _buildRemoveAnimation(task, animation),
          duration: const Duration(milliseconds: 800),
        );
      }
    }

    for (final newTask in newTasks) {
      final needAdd = !_tasks.any((oldTask) => oldTask.id == newTask.id);
      if (needAdd) {
        state.insertItem(newTasks.indexOf(newTask));
      }
    }
  }

  Widget _buildRemoveAnimation(Task task, Animation<double> animation) {
    final sizeFactor = CurvedAnimation(
      parent: animation,
      curve: Interval(0.0, 0.4, curve: Curves.easeIn),
    );

    final position = Tween<Offset>(begin: Offset(0.8, 0.0), end: Offset.zero)
        .animate(
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
        child: FadeTransition(opacity: opacity, child: _buildTaskTile(task)),
      ),
    );

    return widget;
  }

  Widget _buildTaskTile(Task task) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.secondaryContainer,
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style,
        child: task.buildDisplayWidget(context),
      ),
    );
  }

  Widget _buildNoTaskPage() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, color: colors.itemHint, size: 48),
          Text(
            '没有任务啦 ~(‾▾‾~)~',
            style: theme.textTheme.displayLarge?.copyWith(
              color: colors.itemHint,
            ),
          ),
          SizedBox(height: 50),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = _buildNoTaskPage();

    Widget list = AnimatedList(
      key: _key,
      initialItemCount: _tasks.length,
      controller: controller,
      padding: EdgeInsets.symmetric(horizontal: 8),
      itemBuilder: (context, index, animation) {
        final task = _tasks[index];

        final position =
            Tween<Offset>(begin: Offset(0.3, 0.0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            );

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: position,
            child: _buildTaskTile(task),
          ),
        );
      },
    );
    if (Platform.isWindows) {
      list = DesktopScrollViewContainer(controller: controller, child: list);
    }
    final Widget widget = AnimatedSwitcher(
      duration: Duration(milliseconds: 600),
      child: _tasks.isEmpty ? note : list,
      transitionBuilder: (child, animation) {
        final position =
            Tween<Offset>(begin: Offset(0.0, 40.0), end: Offset.zero).animate(
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
