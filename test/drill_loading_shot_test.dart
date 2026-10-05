import 'dart:io';
import 'dart:ui' as ui;

import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把 DrillLoading 的几个相位渲染出来存成 PNG，用来肉眼核对：
/// 四片钻臂衔接处有没有内轮廓、中心亮点的闪光、铜粒弹出、出错态转红、两套主题
void main() {
  testWidgets('渲染铜钻头循环并截图', (tester) async {
    // physicalSize 会被 devicePixelRatio 除；窗口要裹得下一个尺寸组
    tester.view.physicalSize = const Size(1260, 420);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 相位取自组件的一组时间点：0.02 刚起转 / 0.3 转过一个角度 / 0.6 闪到最亮刚弹铜
    // / 0.8 铜粒飞在半路 / 1.0 一轮走完 / 出错定格
    final samples = <(String, Widget)>[
      ('起转', const DrillLoading(size: 120, progress: 0.02)),
      ('旋转30度', const DrillLoading(size: 120, progress: 0.3)),
      ('闪光弹铜', const DrillLoading(size: 120, progress: 0.6)),
      ('铜粒飞出', const DrillLoading(size: 120, progress: 0.8)),
      ('一轮结束', const DrillLoading(size: 120, progress: 1.0)),
      ('出错', const DrillLoading(size: 120, error: true)),
    ];

    for (final brightness in Brightness.values) {
      final isDark = brightness == Brightness.dark;
      // 换主题要给 MaterialApp 换 key：pumpWidget 复用同一棵树时不会重建主题，
      // 不换的话两套主题都会走最先那一次
      final samples2 = <(String, Widget)>[
        ...samples,
        (
          '尺寸组',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              DrillLoading(size: 16),
              SizedBox(width: 16),
              DrillLoading(size: 28),
              SizedBox(width: 16),
              DrillLoading(size: 48),
            ],
          ),
        ),
      ];

      for (final (name, sample) in samples2) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(brightness),
            theme: ThemeData(
              brightness: brightness,
              extensions: [isDark ? AppColors.dark : AppColors.light],
            ),
            home: Scaffold(
              backgroundColor: isDark
                  ? const Color(0xFF202020)
                  : const Color(0xFFE8E8E8),
              body: Center(
                child: RepaintBoundary(
                  key: const ValueKey('shot'),
                  child: sample,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

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
}
