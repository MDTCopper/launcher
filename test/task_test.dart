import 'package:copper_launcher/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// SimpleTask / Task 的行为测试（不依赖 TaskManager 单例，避免跨用例污染）。
void main() {
  group('SimpleTask', () {
    testWidgets('start 置为 process 并通知，完成后置 completed 并再次通知', (tester) async {
      var notified = 0;
      final task = SimpleTask(type: TaskType.download);
      task.addListener(() => notified++);

      task.start();

      // start 同步：status=process + 一次通知；runTask 还停在 await null 之前 → progress 未定
      expect(task.status, TaskStatus.process);
      expect(task.progress, isNull);
      expect(notified, 1);

      // 让异步 runTask 完成 → finally 广播（修"完成不通知" bug）
      await tester.pump();
      expect(task.status, TaskStatus.completed);
      expect(task.progress, 1.0);
      expect(notified, 2);
    });

    testWidgets('可设置进度后归档，完成后广播最新进度', (tester) async {
      var notified = 0;
      final task = SimpleTask(
        type: TaskType.check,
        task: (t) => t.progress = 0.5,
      );
      task.addListener(() => notified++);

      task.start();
      await tester.pump();

      expect(task.status, TaskStatus.completed);
      expect(task.progress, 1.0);
      expect(notified, greaterThanOrEqualTo(2));
    });
  });
}
