import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 三态的回归：切状态不能打断当前这一步；[DrillLoading.onCycleFinished] 里
/// `setState` 不能炸 "setState() called during build"
///
/// 后者踩过：`didUpdateWidget` 是 build 期间跑的，那里直接落地新状态会重置控制器，
/// 控制器同步通知监听器 ⇒ 回调里 `setState` 就炸了
void main() {
  testWidgets('旋转途中切状态要等这一步走完', (tester) async {
    final probe = DrillStateProbe();
    var state = DrillLoadingState.spinning;
    var cycles = 0;

    /// 用 StatefulBuilder 提供 setState：`onCycleFinished` 里 setState 就是
    /// 当初那个 "setState() called during build" 的触发条件
    late StateSetter rebuild;
    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [AppColors.dark],
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setInnerState) {
                rebuild = setInnerState;
                return DrillLoading(
                  size: 64,
                  state: state,
                  probe: probe,
                  onCycleFinished: () => rebuild(() => cycles++),
                );
              },
            ),
          ),
        ),
      );
    }

    Future<void> advance(int milliseconds) async {
      for (var t = 0; t < milliseconds; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await show();
    await advance(300);
    expect(probe.step, lessThan(0.6), reason: '这一步应当还在转');

    state = DrillLoadingState.completing;
    await show();
    await tester.pump();
    expect(probe.active, DrillLoadingState.spinning, reason: '切状态不能打断当前这一步');
    expect(probe.pending, DrillLoadingState.completing);

    await show();
    await advance(1000);
    expect(probe.active, DrillLoadingState.completing, reason: '一步走完才切过去');

    // 结束态只走一步，之后停住
    await advance(1500);
    final settled = cycles;
    await advance(3000);
    expect(cycles, settled, reason: '结束态停住后不该再走步');

    // 切回旋转态应当重新转起来
    state = DrillLoadingState.spinning;
    await show();
    await advance(1500);
    expect(cycles, greaterThan(settled), reason: '回到旋转态应当继续走步');
  });
}
