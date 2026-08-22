import 'package:copper_launcher/ui/util/info/notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通知组件（self-play 动画 + 左滑删除）widget 测试。
///
/// 直接挂载 [NotificationWidget] 而非 [NotificationManager]：
/// 后者是静态单例 + OverlayEntry，跨测试会互相污染。
/// 通过动态调用 State 的公开方法 [addItemWidget] 注入通知。
void main() {
  const kEnter = Duration(milliseconds: 280);

  late State<NotificationWidget> noticeState;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NotificationWidget(onDismiss: _noop),
        ),
      ),
    );
    noticeState = tester.state<State<NotificationWidget>>(
      find.byType(NotificationWidget),
    );
  }

  void addNotice(
    String text, {
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 3),
  }) {
    (noticeState as dynamic).addItemWidget(
      Container(
        color: Colors.grey.shade200,
        child: Text(text),
      ),
      onTap,
      duration,
    );
  }

  /// 等待通知完整入场（首帧布局后 forward + 播完）。
  ///
  /// 时序：pump() build + post-frame 启动 forward → pump(0) 让 ticker 开始
  /// → pump(kEnter) 播完 → pump() 稳定到 value=1。
  /// 不用 pumpAndSettle：它会反复推进虚拟时间，可能提前触发通知定时器
  /// （时长较短时入场未断言就被移除）。
  Future<void> settleEnter(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(Duration.zero);
    await tester.pump(kEnter);
    await tester.pump();
  }

  /// 等待退场动画播完并完成移除。
  ///
  /// 退场分段链：点击 = 缩小(300) → 停顿(100) → 划出淡化(300) → 收缩(200)，
  /// 滑动/定时 = 划出淡化(300) → 收缩(200)。循环推进直至动画结束。
  Future<void> settleExit(WidgetTester tester) async {
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(); // onRemove → setState 重建
  }

  testWidgets('通知出现并播放入场动画', (tester) async {
    await pumpHost(tester);
    addNotice('入场通知');
    await settleEnter(tester);

    expect(find.text('入场通知'), findsOneWidget);
  });

  testWidgets('定时器到期后自动退场消失', (tester) async {
    await pumpHost(tester);
    addNotice('定时消失', duration: const Duration(milliseconds: 400));
    await settleEnter(tester);
    expect(find.text('定时消失'), findsOneWidget);

    // duration 到期 → _remove → reverse 退场
    await tester.pump(const Duration(milliseconds: 400));
    await settleExit(tester);

    expect(find.text('定时消失'), findsNothing);
  });

  testWidgets('左滑超过阈值松手即删除', (tester) async {
    await pumpHost(tester);
    addNotice('滑动删除');
    await settleEnter(tester);

    await tester.drag(find.text('滑动删除'), const Offset(-200, 0));
    await settleExit(tester);

    expect(find.text('滑动删除'), findsNothing);
  });

  testWidgets('左滑未达阈值回弹保留', (tester) async {
    await pumpHost(tester);
    addNotice('未达阈值');
    await settleEnter(tester);

    await tester.drag(find.text('未达阈值'), const Offset(-80, 0));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('未达阈值'), findsOneWidget);
  });

  testWidgets('点击通知触发回调并删除', (tester) async {
    await pumpHost(tester);
    var tapped = false;
    addNotice('点击通知', onTap: () => tapped = true);
    await settleEnter(tester);

    debugPrint('RECT: ${tester.getRect(find.byType(NotificationWidget))}');
    await tester.tap(find.text('点击通知'));
    await settleExit(tester);

    expect(tapped, isTrue);
    expect(find.text('点击通知'), findsNothing);
  });

  testWidgets('多条通知删除互不影响', (tester) async {
    await pumpHost(tester);
    addNotice('通知A');
    addNotice('通知B');
    await settleEnter(tester);

    expect(find.text('通知A'), findsOneWidget);
    expect(find.text('通知B'), findsOneWidget);

    await tester.drag(find.text('通知A'), const Offset(-200, 0));
    await settleExit(tester);

    expect(find.text('通知A'), findsNothing);
    expect(find.text('通知B'), findsOneWidget);
  });
}

void _noop() {}
