import 'dart:async';

import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

///任务抽象类，需要长时间或异步运行的程序在task类中进行
///
///- 复杂任务继承 [Task]，实现 [runTask] 与 [buildDisplayWidget]
///- 需要并进一个主任务的步骤用 [attachSubTask] 挂成子任务
abstract class Task implements Listenable {
  late final String id;
  TaskStatus status = TaskStatus.pending; //创建时为待定，需要外部启动
  double? progress;

  ///若不自己设定，则默认为任务当前创建时间
  late final DateTime createTime;

  final Set<VoidCallback> listeners = {};

  /// 所属主任务：非空说明这是**子任务** —— 不进 `TaskManager`、不单独占卡片、不发用户通知
  Task? parent;

  /// 挂在主任务下面的子任务（按 [weight] 折算总体进度由主任务自己算）
  final List<Task> subTasks = [];

  /// 在总体进度里的权重（主任务自己解释）
  double weight = 1;

  bool get isSubTask => parent != null;

  Task({DateTime? createTime, String? id}) {
    this.createTime = createTime ?? DateTime.now();
    this.id = id ?? this.createTime.hashCode.toString();
  }

  /// 把一个任务挂到自己下面：它之后就是子任务（取消会级联）
  void attachSubTask(Task child) {
    child.parent = this;
    subTasks.add(child);
  }

  /// 子任务不发通知，只留一行日志；主任务照常弹
  void notice({
    IconData? icon,
    String? title,
    String? content,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (isSubTask) {
      final text = [
        title,
        content,
      ].whereType<String>().where((value) => value.isNotEmpty).join('：');
      if (text.isNotEmpty) {
        addLog(.info, removeNewlines(text), tag: 'Task');
      }
      return;
    }
    addNotice(icon: icon, title: title, content: content, duration: duration);
  }

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  /// 卡片头部的图标与标题：默认按下发处理，特殊任务（校验 / 启动 / 联机）自己覆写
  IconData get displayIcon => Icons.task;

  String get displayTitle => '任务';

  String formatProgress() {
    if (progress == null) return '0.0%';
    return '${(progress! * 100).toStringAsFixed(1)} %';
  }

  ///是否还能取消：只有进行中才有意义，任务结束后请求 / 进程都不在了
  bool get canCancel => status == TaskStatus.process;

  ///状态简称，标在卡片标题右侧
  String? get statusLabel => switch (status) {
    TaskStatus.pending => '待启动',
    TaskStatus.process => null,
    TaskStatus.completed => '已完成',
    TaskStatus.failed => '失败',
    TaskStatus.paused => '已暂停',
    TaskStatus.cancel => '已取消',
  };

  ///需更新任务呈现信息时调用
  void updateDisplay() {
    for (var it in listeners) {
      it.call();
    }
  }

  void cancel() {
    if (status == TaskStatus.cancel) {
      debugPrint('重复取消');
      return;
    }
    status = TaskStatus.cancel;
    // 子任务跟着一起停：主卡上的 ✕ 要能让正在下的那一份也停
    for (final child in subTasks) {
      child.cancel();
    }
    updateDisplay();
  }

  void pause() {
    if (status == TaskStatus.paused) {
      debugPrint('重复暂停');
      return;
    }
    status = TaskStatus.paused;
    updateDisplay();
  }

  void start() {
    unawaited(startAsync());
  }

  /// 可等待的启动：`await` 它就知道这一轮真的跑完了（子任务 / 需要串联的流程用）
  Future<void> startAsync() async {
    if (status == TaskStatus.process) {
      debugPrint('重复开始');
      return;
    }
    status = TaskStatus.process;
    updateDisplay();
    try {
      await runTask();
    } finally {
      updateDisplay();
    }
  }

  ///呈现在信息栏位的组件
  Widget buildDisplayWidget(BuildContext context);

  ///自定义任务内容
  Future<void> runTask();
}

enum TaskStatus { pending, process, completed, failed, paused, cancel }
