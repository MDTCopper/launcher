import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 PopupOverlay 的透明关闭层改为 translucent Listener 后，
/// 打开浮层时点击下层内容：事件透传（下层能收到）+ 浮层同时关闭。
void main() {
  testWidgets('打开浮层后点击下层内容：事件透传且浮层关闭', (tester) async {
    final controller = PopupOverlayController();
    var childTapped = false;
    final childKey = GlobalKey();
    final menuKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PopupOverlay(
              controller: controller,
              dismissOnTapOutside: true,
              dismissOnScrollOutside: true,
              overlayChildBuilder: (context, anchorRect) => Container(
                key: menuKey,
                width: 120,
                height: 80,
                color: Colors.red,
              ),
              child: GestureDetector(
                key: childKey,
                onTap: () => childTapped = true,
                child: Container(width: 100, height: 60, color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    controller.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(menuKey), findsOneWidget);
    expect(controller.isShowing, isTrue);

    // 点击锚点 child（位于浮层下方）；translucent 关闭层应透传事件
    // 同时关闭浮层
    await tester.tap(find.byKey(childKey));
    await tester.pump();

    expect(childTapped, isTrue); // 事件透传到下层 → 命中 child.onTap

    // 关闭动画播完 → 浮层隐藏
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.isShowing, isFalse);
  });
}
