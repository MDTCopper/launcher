import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个保持 process 且进度可固定的假任务（runTask 不自动完成）。
class _FakeTask extends Task {
  _FakeTask({required String id, double? fixedProgress})
      : _fixedProgress = fixedProgress,
        super(id: id) {
    type = TaskType.download;
  }

  final double? _fixedProgress;

  @override
  Future<void> runTask() async {
    progress = _fixedProgress; // 保持 process，不置 completed
  }

  @override
  Widget buildDisplayWidget(BuildContext context) => Text(id);
}

/// window_manager 在测试环境无插件，setProgressBar 会走 MethodChannel 抛异常，
/// 这里 mock 掉 `window_manager` 通道，让任务栏进度调用变成 no-op。
void mockWindowBar() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => null,
  );
}

void main() {
  testWidgets('addTask 自动启动并聚合多个进程任务的进度（修复优先级 bug）', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    addTask(_FakeTask(id: 'a', fixedProgress: 0.2));
    addTask(_FakeTask(id: 'b', fixedProgress: 0.4));

    await tester.pump(const Duration(milliseconds: 100)); // trailing 发射并聚合
    // 修复前 `progress ?? 0.0 + task.progress!` 只取第一个任务 0.2 再 /2 → 0.1；
    // 修复后 (0.2 + 0.4) 平均 → 0.3
    expect(taskManager.totalProcessProgress.value, closeTo(0.3, 0.0001));

    await tester.pump(const Duration(milliseconds: 1000)); // 冲刷 setProgressBar 的 timer
  });

  testWidgets('进程任务均无可测量进度时总进度为 null', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    addTask(_FakeTask(id: 'a'));
    addTask(_FakeTask(id: 'b'));

    await tester.pump(const Duration(milliseconds: 100));
    expect(taskManager.totalProcessProgress.value, isNull);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('高频更新被节流合并（leading + trailing）', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    var count = 0;
    // 注意：不能 `await sub.cancel()`——broadcast 流的 cancel 在 fake async 下会死等，
    // 用 fire-and-forget 取消 + pump 冲刷即可。
    final sub = taskManager.stream.listen((_) => count++);

    addTask(_FakeTask(id: 'a', fixedProgress: 0.1)); // leading → 发射一次
    await tester.pump(); // 冲刷流微任务，接收 leading 事件
    expect(count, 1);

    // 同一窗口内连续 5 次触发，被合并（仅置 pending，不新增发射）
    for (var i = 0; i < 5; i++) {
      taskManager.currentTasks.first.updateDisplay();
    }
    expect(count, 1);

    await tester.pump(const Duration(milliseconds: 100)); // trailing：计时器到点，发射合并后的最新快照
    await tester.pump(); // 冲刷流微任务
    await tester.pump(const Duration(milliseconds: 1000)); // 冲刷 bar timer
    expect(count, lessThanOrEqualTo(2)); // 6 次触发被合并成 ≤2 次

    sub.cancel(); // fire-and-forget，避免 fake async 死等
    await tester.pump();
  });

  testWidgets('changeTaskStatus 可取消进行中的任务', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    final task = _FakeTask(id: 'a');
    addTask(task);
    await tester.pump(const Duration(milliseconds: 100));
    expect(task.status, TaskStatus.process);

    changeTaskStatus('a', TaskStatus.cancel);
    expect(task.status, TaskStatus.cancel);

    await tester.pump(const Duration(milliseconds: 1000)); // 冲刷 bar timer
  });

  testWidgets('changeTaskStatus 可暂停进行中的任务', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    final task = _FakeTask(id: 'a');
    addTask(task);
    await tester.pump(const Duration(milliseconds: 100));
    expect(task.status, TaskStatus.process);

    changeTaskStatus('a', TaskStatus.paused);
    expect(task.status, TaskStatus.paused);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('changeTaskStatus 对已取消任务的重启无效（保护守卫）', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    final task = _FakeTask(id: 'a');
    addTask(task);
    await tester.pump(const Duration(milliseconds: 100));
    changeTaskStatus('a', TaskStatus.cancel);
    expect(task.status, TaskStatus.cancel);

    // 已取消任务再试图启动应为 no-op
    changeTaskStatus('a', TaskStatus.process);
    expect(task.status, TaskStatus.cancel);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('单任务时聚合进度即该任务进度', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    addTask(_FakeTask(id: 'a', fixedProgress: 0.6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taskManager.totalProcessProgress.value, closeTo(0.6, 0.0001));

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('全部完成结算后启动新任务，不会误清除任务栏进度条', (tester) async {
    taskManager.debugReset();

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async {
      calls.add(call);
      return null;
    });

    // 立即完成的任务 → 进入完成结算分支，1s 后计划清除（setProgressBar(-1)）
    addTask(SimpleTask(type: TaskType.download));
    await tester.pump(const Duration(milliseconds: 100));

    // 在 1s 清除窗口内启动一个新任务 → 应取消待清除的 -1
    addTask(_FakeTask(id: 'b', fixedProgress: 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1200)); // 冲过 1s 让计时器触发

    final cleared =
        calls.any((c) => c.method == 'setProgressBar' && c.arguments == -1);
    expect(cleared, isFalse);

    await tester.pump(const Duration(milliseconds: 1000));
  });
}
