import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/info/task_drawer_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTask extends Task {
  _FakeTask({required String id, double? fixedProgress})
      : _fixedProgress = fixedProgress,
        super(id: id) {
    type = TaskType.download;
  }
  final double? _fixedProgress;
  @override
  Future<void> runTask() async => progress = _fixedProgress;
  @override
  Widget buildDisplayWidget(BuildContext context) => Text(id);
}

void mockBar() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async => null);
}

void main() {
  testWidgets('无任务时抽屉不显示任务数，添加任务后显示数量', (tester) async {
    taskManager.debugReset();
    mockBar();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
          extensions: [AppColors.light],
        ),
        home: const Scaffold(body: TaskDrawerOpener()),
      ),
    );
    await tester.pump();

    expect(find.textContaining('项任务'), findsNothing);

    addTask(_FakeTask(id: 'a', fixedProgress: 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.textContaining('项任务'), findsOneWidget);
    expect(find.text('1 项任务'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000)); // 冲刷 bar timer
  });
}
