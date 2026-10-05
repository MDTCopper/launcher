import 'dart:io';
import 'dart:ui' as ui;

import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把 DrillLoading 三种状态的关键帧渲染出来存成 PNG，用来肉眼核对：
/// 钻臂衔接处有没有内轮廓、中心亮点的闪光、结束态弹铜、错误态转红、两套主题
///
/// 组件自己驱动 Controller，所以取帧靠 `pump(时长)` 推进，而不是给 progress
void main() {
  // 一步 = 转 0.6 + 停 0.4；窗口要裹得下一个 120 的钻头
  const step = Duration(milliseconds: 1600);

  testWidgets('渲染铜钻头三种状态并截图', (tester) async {
    tester.view.physicalSize = const Size(1260, 420);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Duration at(double portion) =>
        Duration(milliseconds: (step.inMilliseconds * portion).round());

    // 名字 → 状态 + 取样时刻（相对这一步的起点，必须单调递增：pump 是绝对推进不是累加）
    // 旋转态 0.58 落在闪光峰值之前一点（正好 0.6 会翻到下一轮的开头）
    final shots = <(String, DrillLoadingState, Duration)>[
      ('旋转_起转', DrillLoadingState.spinning, at(0.02)),
      ('旋转_转过一个角度', DrillLoadingState.spinning, at(0.3)),
      ('旋转_闪灯', DrillLoadingState.spinning, at(0.58)),
      ('旋转_停顿', DrillLoadingState.spinning, at(0.8)),
      ('结束_起手', DrillLoadingState.completing, at(0.1)),
      ('结束_旋转中', DrillLoadingState.completing, at(0.35)),
      ('结束_弹铜', DrillLoadingState.completing, at(0.5)),
      ('结束_回弹', DrillLoadingState.completing, at(0.85)),
      ('结束_停住', DrillLoadingState.completing, at(1.0)),
      ('错误_起手', DrillLoadingState.error, at(0.1)),
      ('错误_旋转中', DrillLoadingState.error, at(0.45)),
      ('错误_转红', DrillLoadingState.error, at(1.5)),
    ];

    for (final brightness in Brightness.values) {
      final isDark = brightness == Brightness.dark;
      for (final (name, state, target) in shots) {
        await tester.pumpWidget(
          MaterialApp(
            // 换主题要给 MaterialApp 换 key：pumpWidget 复用同一棵树时不重建主题，
            // 不换的话两套主题都会走最先那一次
            key: ValueKey('$brightness-$name'),
            theme: ThemeData(
              brightness: brightness,
              extensions: [isDark ? AppColors.dark : AppColors.light],
            ),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: const ValueKey('shot'),
                  // 外面留一圈不透明的页面底色：截图里才看得到承托层与页面的对比
                  // （紧贴组件截的话，透明区在图片查看器里会被合成成白的）
                  child: ColoredBox(
                    color: isDark
                        ? AppColors.dark.pageBackground
                        : AppColors.light.pageBackground,
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: DrillLoading(size: 120, state: state),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // 每帧都是新树，控制器从 0 起，一次 pump 推到取样时刻
        await tester.pump(target);

        final image = await captureImage(
          tester.element(find.byKey(const ValueKey('shot'))),
        );
        // toByteData 走真实异步，得放在 runAsync 里，否则会卡死
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'drill_${brightness.name}_$name.png',
        );
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('已写出：${file.path}');
      }
    }
  });

  testWidgets('渲染尺寸组并截图', (tester) async {
    tester.view.physicalSize = const Size(900, 300);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('sizes'),
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [AppColors.dark],
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF202020),
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  DrillLoading(size: 16),
                  SizedBox(width: 16),
                  DrillLoading(size: 28),
                  SizedBox(width: 16),
                  DrillLoading(size: 48),
                  SizedBox(width: 16),
                  DrillLoading(size: 96),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final image = await captureImage(
      tester.element(find.byKey(const ValueKey('shot'))),
    );
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}drill_sizes.png',
    );
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('已写出：${file.path}');
  });
}
