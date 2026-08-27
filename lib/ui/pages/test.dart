import 'package:copper_launcher/ui/components/animation/animated_expansion.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/navigation_collapse_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/button/segment_button.dart';
import 'package:copper_launcher/ui/components/rebound/copper_slider.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_switch.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';

import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

/// 测试页
class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => TestState();
}

class TestState extends State<Test> {
  final PopupOverlayController customController = PopupOverlayController();
  final ScrollController listController = ScrollController();

  // ── 按钮演示区状态 ──
  final int _btnTap = 0; // ReboundButton 点击次数
  final int _btnLongTap = 0; // ReboundButton 长按次数
  final int _iconTap = 0; // IconTextButton 点击次数
  final bool _navCollapsed = false; // NavigationCollapseButton 收起态（箭头旋转）

  // ── 第 11 区演示状态 ──
  int _segSelected = 1; // SegmentedReboundButton 选中值
  bool _groupExpanded = false; // AnimatedExpansion 展开日志

  // ── 第 12 区演示状态 ──
  bool _switchOn = false; // ReboundSwitch 开关
  double _sliderValue = 0.4; // CopperSlider 值(0~1 比例)

  @override
  void dispose() {
    listController.dispose();
    super.dispose();
  }

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
        children: [
          // _buttonSection(),
          _segmentExpansionSection(),
          _switchSliderSection(),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  // ════════ 11. 分段按钮 + 展开/收起容器（copper 风格翻新件） ════════
  Widget _segmentExpansionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('11. SegmentedReboundButton / AnimatedExpansion'),
        _card(
          title: 'SegmentedReboundButton（copper 双模式选中态）',
          desc: '分段按钮：点击切换选中段，选中段背景/前景有过渡动画（暗色玻璃、浅色云母片）。当前选中：$_segSelected。',
          child: SegmentedReboundButton<int>(
            selected: {_segSelected},
            segments: [
              ReboundButtonSegment(
                value: 0,
                icon: Icon(Icons.dark_mode),
                label: Text('暗色'),
              ),
              ReboundButtonSegment(
                value: 1,
                icon: Icon(Icons.auto_mode),
                label: Text('跟随系统'),
              ),
              ReboundButtonSegment(
                value: 2,
                icon: Icon(Icons.light_mode),
                label: Text('浅色'),
              ),
            ],
            onChange: (set) => setState(() => _segSelected = set.first),
          ),
        ),
        _card(
          title: 'AnimatedExpansion（基于 Flutter Expansible，收起后卸载子树）',
          desc:
              '点击标题展开/收起；收起动画完成后内容从树上移除（maintainState:false 性能改进）。最近切换日志：${_groupExpanded ? '展开' : '收起'}。',
          child: AnimatedExpansion(
            title: Text('展开一个分组（点我）'),
            onChange: () => setState(() => _groupExpanded = !_groupExpanded),
            children: [
              for (int i = 0; i < 30; i++)
                Container(
                  height: 32,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('收起后这 30 行不再参与构建 - 第 $i 项'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════ 12. copper 风格开关 / 滑条（ReboundSwitch / CopperSlider） ════════
  Widget _switchSliderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('12. ReboundSwitch / CopperSlider'),
        _card(
          title: 'ReboundSwitch(copper 风格开关)',
          desc: '轨道 + 滑块，选中/未选中平滑过渡；选中轨道变主题色。当前：${_switchOn ? '开' : '关'}。',
          child: ReboundSwitch(
            value: _switchOn,
            onChanged: (v) => setState(() => _switchOn = v),
          ),
        ),
        _card(
          title: 'CopperSlider(点击 / 拖动 / 刻度吸附)',
          desc:
              '轨道 + 填充 + 滑块，点击定位、拖动调整、拖拽时显示浮标；divisions 非空时吸附刻度。当前：${(_sliderValue * 100).round()}。',
          child: CopperSlider(
            value: _sliderValue,
            divisions: 10,
            label: '${(_sliderValue * 100).round()}',
            onChanged: (v) => setState(() => _sliderValue = v),
          ),
        ),
        _card(
          title: 'SwitchSettingBar / SliderSettingBar(弹性标题列)',
          desc: '标题列自适应：空间足时 150 固定宽，空间不足自动收缩 + 省略号。缩窗口即可观察。',
          child: Column(
            spacing: 12,
            children: [
              const SwitchSettingBar(title: '某个开关设置很长', value: true),
              SliderSettingBar(title: '某个滑条设置很长', value: 0.6),
            ],
          ),
        ),
        _card(
          title: '竖排方案试验：描述在上、开关在下',
          desc: '把具体控件放在描述下方（描述居左、控件右对齐独立成行），而非横排右侧。窗口缩窄时描述行仍可完整显示。',
          child: Column(
            spacing: 12,
            children: [
              // 横排对照：描述 + 右侧控件
              SwitchSettingBar(
                title: '横排对照开关',
                value: _switchOn,
                onChanged: (v) => setState(() => _switchOn = v),
              ),
              // 竖排试验：描述一行、开关下一行贴右
              Row(
                children: [
                  const Expanded(child: Text('开启某项高级功能')),
                  ReboundSwitch(
                    value: _switchOn,
                    onChanged: (v) => setState(() => _switchOn = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 竖排变体：描述 + 副说明 + 控件贴右
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('开启自动更新'),
                        Text(
                          '更新到最新版本',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        ReboundSwitch(
                          value: _switchOn,
                          onChanged: (v) => setState(() => _switchOn = v),
                        ),
                      ],
                    ),
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
