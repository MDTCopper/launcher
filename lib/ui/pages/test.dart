import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

import 'package:flutter/material.dart';

/// 测试页
class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => TestState();
}

class TestState extends State<Test> {
  // ── 第 19 区演示状态（DrillLoading 铜钻头循环）──
  DrillLoadingState _drillState = DrillLoadingState.spinning;
  int _drillCycles = 0; // onCycleFinished 计数

  /// 当前状态在做什么，配合演示说清三种状态的差别
  String get _drillStateHint => switch (_drillState) {
    DrillLoadingState.spinning => '旋转态：不停转，每转一次闪一下灯；不出铜',
    DrillLoadingState.completing => '结束态：只转一次，转到头弹一粒铜就停住',
    DrillLoadingState.error => '错误态：只转一次，转到头后中心转红、金属泛红，停住',
  };

  Widget _card({
    required String title,
    required String desc,
    required Widget child,
  }) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return CopperSingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_drillLoadingSection(), const SizedBox(height: 120)],
      ),
    );
  }

  // ════════ 19. 铜钻头循环（DrillLoading） ════════

  void _onDrillCycle() => setState(() => _drillCycles++);

  /// 一块底色牌子，模拟真实等待场景（等待动画基本都出现在卡片/对话框里）
  Widget _buildDrillPlate({required String label, required Widget child}) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          child,
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: colors.itemPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _drillLoadingSection() {
    final colors = AppColors.of(context);
    final labelStyle = TextStyle(color: colors.itemPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('19. DrillLoading（铜钻头循环）'),
        _card(
          title: '线条化的 Mindustry 机械钻头：转一次、闪一下、弹一粒铜',
          desc:
              '层次是底座 → 四片钻臂 → 顶盖 → 中心亮点 → 铜粒。'
              '一个周期走一步：钻臂转到下一个 90 度 → 中心亮点闪到最亮（就是"钻到了"那一下）'
              '→ 从中心弹出一粒铜。下面四块是不停转的尺寸对照。',
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildDrillPlate(
                label: '16',
                child: const DrillLoading(size: 16),
              ),
              _buildDrillPlate(
                label: '28',
                child: const DrillLoading(size: 28),
              ),
              _buildDrillPlate(
                label: '48（默认）',
                child: const DrillLoading(size: 48),
              ),
              _buildDrillPlate(
                label: '96',
                child: const DrillLoading(size: 96),
              ),
            ],
          ),
        ),
        _card(
          title: '三种状态：旋转 / 结束 / 错误（点哪颗切哪个）',
          desc:
              '旋转态不停转、只闪灯不出铜；结束态只转一次、转到头弹一粒铜就停住；'
              '错误态只转一次、转到头后中心亮点转红、整套金属略微泛红。'
              '切状态会**等当前这一步走完**（转完那 90 度再进新状态），所以看不到半路被打断的钻头 —— '
              '可以趁它转的时候连点几下，看它是走完才切。右边那块实时记 onCycleFinished 的次数。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 24,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildDrillPlate(
                    label: '三种状态共用这一块',
                    child: DrillLoading(size: 96, state: _drillState),
                  ),
                  _buildDrillPlate(
                    label: '回调已计 $_drillCycles 步',
                    child: DrillLoading(
                      size: 64,
                      state: _drillState,
                      onCycleFinished: _onDrillCycle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(_drillStateHint, style: labelStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final state in DrillLoadingState.values)
                    IconTextButton(
                      icon: switch (state) {
                        DrillLoadingState.spinning => Icons.rotate_right,
                        DrillLoadingState.completing =>
                          Icons.check_circle_outline,
                        DrillLoadingState.error => Icons.error_outline,
                      },
                      content: switch (state) {
                        DrillLoadingState.spinning => '旋转态',
                        DrillLoadingState.completing => '结束态（转一次弹铜）',
                        DrillLoadingState.error => '错误态（转一次转红）',
                      },
                      onTap: () => setState(() => _drillState = state),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 简易菜单项按钮（本测试页专用）。
///
/// 注意：不要用 `Container(alignment: Alignment.center)`——
/// 内部会包 Align，松约束下会撑满父宽度。用 Row(mainAxisSize: min)
/// 保持自适应宽度，四角测试才能正确显示。
class ReboundMenuButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const ReboundMenuButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.interactive.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.interactive.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label, style: TextStyle(color: colors.itemPrimary))],
        ),
      ),
    );
  }
}
