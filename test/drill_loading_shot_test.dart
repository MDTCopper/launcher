import 'dart:io';
import 'dart:ui' as ui;

import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把 DrillLoading 的几个相位渲染出来存成 PNG，用来肉眼核对：
/// 四片钻臂衔接处有没有内轮廓、中心亮点的闪光、铜粒弹出、出错态转红
void main() {
  testWidgets('渲染铜钻头循环并截图', (tester) async {
    // physicalSize 会被 devicePixelRatio 除；窗口刚好裹住一个 120 的钻头
    tester.view.physicalSize = const Size(360, 360);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 相位取自组件的一组时间点：0.02 刚起转 / 0.35 转到一半 / 0.6 闪到最亮刚弹铜
    // / 0.8 铜粒飞在半路 / 1.0 一轮结束 / 出错定格
    final samples = <(String, Widget)>[
      ('起转', const DrillLoading(size: 120, progress: 0.02)),
      ('旋转30度', const DrillLoading(size: 120, progress: 0.3)),
      ('转到一半', const DrillLoading(size: 120, progress: 0.35)),
      ('闪光弹铜', const DrillLoading(size: 120, progress: 0.6)),
      ('铜粒飞出', const DrillLoading(size: 120, progress: 0.8)),
      ('一轮结束', const DrillLoading(size: 120, progress: 1.0)),
      ('出错', const DrillLoading(size: 120, error: true)),
    ];

    for (final (name, sample) in samples) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [AppColors.dark],
          ),
          home: Scaffold(
            backgroundColor: const Color(0xFF202020),
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
        '${Directory.systemTemp.path}${Platform.pathSeparator}drill_$name.png',
      );
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('已写出：${file.path}');
    }
  });
}
