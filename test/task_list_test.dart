import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/ui/util/info/task_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTask extends Task {
  _FakeTask({required String id}) : super(id: id) {
    type = TaskType.download;
  }

  @override
  Future<void> runTask() async {}

  @override
  Widget buildDisplayWidget(BuildContext context) => Text(id);
}

void mockWindowBar() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => null,
  );
}

void main() {
  testWidgets('一批同时移除多条任务时列表正确消失（索引漂移修复）', (tester) async {
    taskManager.debugReset();
    mockWindowBar();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TaskList())),
    );

    final ta = _FakeTask(id: 'a');
    final tb = _FakeTask(id: 'b');
    addTask(ta); // leading
    addTask(tb); // 同窗口合并
    await tester.pump(const Duration(milliseconds: 100)); // trailing：a、b 进入列表
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    // 用一个"无删除"的更新武装一个新的节流窗口（leading，不触发移除）
    ta.updateDisplay();

    // 同窗口内取消 a、b → 合并成一次 trailing：它们同时离开 process，
    // 触发一次 _updateList 移除 2 条 → 覆盖原"逐条按旧索引删"的索引漂移 bug。
    changeTaskStatus('a', TaskStatus.cancel);
    changeTaskStatus('b', TaskStatus.cancel);

    await tester.pump(const Duration(milliseconds: 100)); // trailing 发射、开始移除动画
    await tester.pump(const Duration(milliseconds: 900)); // 播完 AnimatedList 移除动画
    await tester.pump(const Duration(milliseconds: 1000)); // 冲刷 bar timer

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
  });
}
