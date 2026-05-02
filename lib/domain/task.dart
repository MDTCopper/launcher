import 'package:flutter/material.dart';

import '../ui/util/widget/feature_button.dart';
import '../util/downloader.dart';

///任务抽象类，需要长时间或异步运行的程序在task类中进行
///
///- 简单任务用[SimpleTask]快速实现
///- 复杂任务需要继承[Task]并实现[runTask]和[buildDisplayWidget]
abstract class Task implements Listenable {
  late final String id;

  ///继承后需要定义类型
  late final TaskType type;
  TaskStatus status = TaskStatus.pending; //创建时为待定，需要外部启动
  double? progress;

  ///若不自己设定，则默认为任务当前创建时间
  late final DateTime createTime;

  final Set<VoidCallback> listeners = {};

  Task({DateTime? createTime, String? id}) {
    this.createTime = createTime ?? DateTime.now();
    this.id = id ?? createTime.hashCode.toString();
  }

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  IconData getIcon(TaskType type) {
    switch (type) {
      case TaskType.check:
        return Icons.search;
      case TaskType.launch:
        return Icons.rocket_launch;
      case TaskType.download:
        return Icons.download;
    }
  }

  String getTitle(TaskType type) {
    switch (type) {
      case TaskType.check:
        return '校验';
      case TaskType.launch:
        return '启动';
      case TaskType.download:
        return '下载';
    }
  }

  String formatProgress() {
    if (progress == null) return '0.0%';
    return '${(progress! * 100).toStringAsFixed(1)} %';
  }

  ///呈现在信息栏位的组件
  Widget buildDisplayWidget(BuildContext context);

  ///需更新任务呈现信息时调用
  void updateDisplay() {
    for (var it in listeners) {
      it.call();
    }
  }

  void cancel() {
    status = TaskStatus.cancel;
    updateDisplay();
  }

  void pause() {
    status = TaskStatus.paused;
    updateDisplay();
  }

  void start() {
    status = TaskStatus.process;
    runTask();
    updateDisplay();
  }

  ///自定义任务内容
  Future<void> runTask();
}

enum TaskType { check, launch, download }

enum TaskStatus { pending, process, completed, failed, paused, cancel }

///简单任务，传入方法，方法提供Simple本体来操作任务进度和描述
///
///可在displayBuilder中重写呈现组件
class SimpleTask extends Task {
  final void Function(SimpleTask)? task;
  final Future<void> Function(SimpleTask)? futureTask;
  final Widget Function(BuildContext, SimpleTask)? displayBuilder;
  String? describe;
  String? details;

  SimpleTask({
    required TaskType type,
    super.id,
    this.task,
    this.futureTask,
    this.displayBuilder,
    this.describe,
    this.details,
  }) {
    this.type = type;
  }

  @override
  Future<void> runTask() async {
    task?.call(this);
    await futureTask?.call(this);
    progress = 1.0;
    status = TaskStatus.completed;
  }

  @override
  Widget buildDisplayWidget(BuildContext context) {
    if (displayBuilder != null) return displayBuilder!.call(context, this);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(getIcon(type), size: 32),
            SizedBox(width: 4),
            Text(
              getTitle(type),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            Expanded(child: SizedBox()),
            ReboundButton(onTap: cancel, child: Icon(Icons.close)),
          ],
        ),
        LinearProgressIndicator(value: progress),
        if (progress != null) Text(formatProgress()),
        if (describe != null) Text(describe!),
        if (details != null) Text(details!),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

final dr = Downloader();



