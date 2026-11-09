import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/capsule_action_bar.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/segment_button.dart';
import 'package:copper_launcher/ui/components/cu_card.dart';
import 'package:copper_launcher/ui/components/effect/border_progress.dart';
import 'package:copper_launcher/ui/components/input/color_picker.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/pager.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/rebound/cu_slider.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_checkbox.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_switch.dart';
import 'package:copper_launcher/ui/components/row/priority_row.dart';
import 'package:copper_launcher/ui/components/setting_bar/input_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/setting_bar_row.dart';
import 'package:copper_launcher/ui/components/setting_bar/option_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/components/tile/navigation_tile.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 原组件（`lib/ui/components/` 里的真实组件）对照区
///
/// 每一组先列出「设计版少了什么」，再放原组件本体；改设计组件时对着这里补齐功能
class RealComponentDemo extends StatefulWidget {
  const RealComponentDemo({super.key, required this.skin});

  final TemplateSkin skin;

  @override
  State<RealComponentDemo> createState() => _RealComponentDemoState();
}

class _RealComponentDemoState extends State<RealComponentDemo> {
  final _text = TextEditingController(text: 'Copper Launcher');
  bool _switch = true;
  bool _checkbox = true;
  double _slider = 0.35;
  int _segment = 1;
  int _language = 0;
  Color _pickedColor = const Color(0xFFC89958);
  TextEditingController? _settingText;

  TemplateSkin get skin => widget.skin;

  @override
  void dispose() {
    _text.dispose();
    _settingText?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _lead(),
        _diffCard(
          '按钮',
          '设计版 `TemplateButton` 只有 solid / plain / quiet 三种观感；'
              '原组件还有「选中态持久高亮」「长按」「悬停抬升 / 按下缩放」「气泡提示」',
        ),
        _buttons(),
        _diffCard(
          '开关与复选',
          '设计版 `TemplateSwitch` 只有开关本体；原组件还有带图标 / 文字标签的复选、'
              '禁用态与悬停提示',
        ),
        _toggles(),
        _diffCard(
          '滑块',
          '设计版 `TemplateSliderRow` 是「标题 + 标签 + 滑条」的行式；'
              '原组件额外提供拖动开始 / 结束回调（停在哪个刻度上要落库时用）',
        ),
        _sliderRow(),
        _diffCard(
          '输入框',
          '设计版 `TemplateTextField` 只有占位 / 错误文案；'
              '原组件还有旁置 label 与固定宽度、错误态动画、自定义右键菜单、编辑完成回调',
        ),
        _inputs(),
        _diffCard(
          '分段按钮',
          '设计版 `TemplateSegment` 是整条分段；原组件能单段禁用、单段带图标、'
              '多选时回调整个集合',
        ),
        _segments(),
        _diffCard(
          '分页',
          '设计版 `TemplatePager` 只有上一页 / 下一页；原组件支持首页 / 末页、'
              '末页判断（能提前置灰）',
        ),
        _pager(),
        _diffCard(
          '进度',
          '设计版只有单条 / 不确定两种进度条；原组件还有「边框进度」（包住内容走一圈）、'
              '「多段占比条」',
        ),
        _progress(),
        _diffCard(
          '设置行',
          '设计版是按场景拼的行；原组件把「标题固定宽 + 右侧控件」封装成设置行，'
              '多行之间标题能对齐；容器装饰（含行底分隔线）由调用方透传',
        ),
        _settingBars(),
        _diffCard(
          '卡片与列表',
          '设计版 `TemplateListCard` / `TemplateRow` 是静态行；'
              '按压已从「整体缩放」改为「变色」（CuPressable），因此行间分隔线可以加回来',
        ),
        _cards(),
        _diffCard('优先行', '设计版没有这个：窗口窄时按优先级依次丢弃次要信息，保证主信息不被挤断'),
        _priorityRow(),
        _diffCard(
          '下拉选择',
          '设计版 `TemplateDropdown` 是简化面板；原组件 `DropdownLayer` 支持选项分组、'
              '行内图标 / 说明、多选、弹出宽度与展开动画',
        ),
        _dropdown(),
        _diffCard('颜色选择', '设计版只有预设色块 chips；原组件是取色面板 + 透明度 + 数值读数'),
        _colorPicker(),
        _diffCard(
          '气泡提示',
          '设计版用 Flutter `Tooltip` 一带而过；原组件 `HintLayer` 会按窗口空间自动选方位，'
              '支持点击触发、自定义组件提示、长按显示',
        ),
        _hintLayer(),
        _diffCard('胶囊操作条', '设计版没有这个形态：窄窗 / 移动端把一组图标操作收成一枚胶囊，点开展开、再点折叠'),
        _capsuleBar(),
        _diffCard('侧栏条目', '设计版侧栏条目是独立实现；原组件 `NavigationTile` 支持收起态只剩图标、悬停提示'),
        _navigationTile(),
      ],
    );
  }

  Widget _lead() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [
        Text(
          '原组件对照',
          style: TemplateType.page.copyWith(color: skin.textPrimary),
        ),
        Text(
          '这里的控件来自 lib/ui/components/，是真实现役组件；'
          '每组上方写明设计版缺哪些能力，补齐后再替换原组件',
          style: TemplateType.caption.copyWith(
            color: skin.textTertiary,
            height: 18 / 12,
          ),
        ),
      ],
    );
  }

  Widget _diffCard(String title, String diff) {
    return TemplateNotice(
      skin: skin,
      tone: TemplateNoticeTone.note,
      title: title,
      text: diff,
      icon: Icons.compare_arrows,
    );
  }

  Widget _group(Widget child) {
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.md),
      child: child,
    );
  }

  Widget _buttons() {
    return _group(
      Wrap(
        spacing: TemplateSpace.sm,
        runSpacing: TemplateSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionButton(
            icon: const Icon(Icons.play_arrow),
            content: const Text('ActionButton'),
            onTap: () {},
          ),
          ActionButton(
            icon: const Icon(Icons.push_pin_outlined),
            content: const Text('选中态'),
            selected: true,
            onTap: () {},
          ),
          ActionButton(
            icon: const Icon(Icons.block),
            content: const Text('禁用'),
            enable: false,
            onTap: () {},
          ),
          IconTextButton(
            icon: Icons.folder_open,
            content: '主按钮',
            weight: ActionWeight.primary,
            onTap: () {},
          ),
          IconTextButton(
            icon: Icons.copy,
            content: '次按钮',
            weight: ActionWeight.secondary,
            onTap: () {},
          ),
          IconTextButton(
            icon: Icons.delete_outline,
            content: '危险',
            weight: ActionWeight.danger,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _toggles() {
    return _group(
      Wrap(
        spacing: TemplateSpace.xl,
        runSpacing: TemplateSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ReboundSwitch(
            value: _switch,
            onChanged: (value) => setState(() => _switch = value),
          ),
          ReboundCheckbox(
            value: _checkbox,
            label: '带文字',
            onChange: (value) => setState(() => _checkbox = value),
          ),
          ReboundCheckbox(
            value: !_checkbox,
            icon: Icons.star_outline,
            hint: '带图标',
            onChange: (value) => setState(() => _checkbox = !value),
          ),
          const ReboundCheckbox(value: false, label: '禁用', enable: false),
        ],
      ),
    );
  }

  Widget _sliderRow() {
    return _group(
      CuSlider(
        value: _slider,
        label: '${(_slider * 100).round()}%',
        divisions: 20,
        onChanged: (value) => setState(() => _slider = value),
        onChangeEnd: (_) {},
      ),
    );
  }

  Widget _inputs() {
    return _group(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          OutlinedTextField(label: '名称', labelWidth: 64, controller: _text),
          OutlinedTextField(
            label: '错误',
            labelWidth: 64,
            controller: TextEditingController(text: '不合法的值'),
            error: '这里填错了',
          ),
          const OutlinedTextField(label: '禁用', labelWidth: 64, enable: false),
        ],
      ),
    );
  }

  Widget _segments() {
    return _group(
      SegmentedReboundButton<int>(
        segments: [
          ReboundButtonSegment(value: 0, content: '紧凑'),
          ReboundButtonSegment(value: 1, content: '列表'),
          ReboundButtonSegment(value: 2, content: '网格', enabled: false),
        ],
        selected: {_segment},
        onChange: (selected) => setState(() => _segment = selected.first),
      ),
    );
  }

  Widget _pager() {
    return _group(
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Pager(
            2,
            endIndex: 9,
            endPage: false,
            onDown: () {},
            onUp: () {},
            goHome: () {},
            goEnd: () {},
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    return _group(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          BorderProgress(
            progress: 0.45,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              child: Text(
                '边框进度 45%',
                style: TemplateType.caption.copyWith(color: skin.textSecondary),
              ),
            ),
          ),
          PercentBar(
            total: 100,
            height: 12,
            dataList: [
              PercentBarData(value: 52, label: 'Java'),
              PercentBarData(value: 28, label: '资源'),
              PercentBarData(value: 20, label: '缓存'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingBars() {
    return _group(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          SwitchSettingBar(
            title: '自动更新',
            value: _switch,
            onChanged: (value) => setState(() => _switch = value),
          ),
          SettingBarRow(
            title: '启动参数',
            control: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '-Xmx2G',
                style: TemplateType.caption.copyWith(color: skin.textSecondary),
              ),
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: skin.border)),
            ),
          ),
          SliderSettingBar(
            title: '窗口缩放',
            value: _slider,
            label: '${(_slider * 100).round()}%',
            onChanged: (value) => setState(() => _slider = value),
          ),
          InputSettingBar(
            title: '备注',
            initialValue: '测试文本',
            controller: _settingText,
          ),
        ],
      ),
    );
  }

  Widget _cards() {
    return _group(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          CuCard(
            child: Padding(
              padding: const EdgeInsets.all(TemplateSpace.sm),
              child: Text(
                'CuCard：带抬升与可选长按',
                style: TemplateType.item.copyWith(color: skin.textPrimary),
              ),
            ),
          ),
          // 行间带分隔线：按压只变色不缩放，所以线不会被挤出缝
          ReboundListTile(
            leading: Icon(Icons.extension_outlined, color: skin.textSecondary),
            title: Text(
              'ReboundListTile',
              style: TemplateType.item.copyWith(color: skin.textPrimary),
            ),
            subtitle: Text(
              '按压 = 变色（不再是整体缩放），行底可加分隔线',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
            trailing: Icon(Icons.chevron_right, color: skin.textTertiary),
            onTap: () {},
            onLongTap: () {},
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: skin.border)),
            ),
          ),
          ReboundListTile(
            leading: Icon(Icons.push_pin_outlined, color: skin.textSecondary),
            title: Text(
              '选中态行',
              style: TemplateType.item.copyWith(color: skin.textPrimary),
            ),
            subtitle: Text(
              'selected 走强调色淡底',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
            trailing: Icon(Icons.check, color: skin.textTertiary),
            selected: true,
            onTap: () {},
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: skin.border)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priorityRow() {
    return _group(
      SizedBox(
        width: 320,
        child: PriorityRow(
          items: [
            PriorityRowItem.text(
              text: '主信息',
              priority: 0,
              textStyle: TextStyle(color: skin.textPrimary),
            ),
            PriorityRowItem.text(
              text: 'build 123',
              priority: 1,
              textStyle: TextStyle(color: skin.textSecondary),
            ),
            PriorityRowItem.text(
              text: '78.4 MB',
              priority: 2,
              textStyle: TextStyle(color: skin.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigationTile() {
    return _group(
      SizedBox(
        width: 180,
        child: NavigationTile(
          icon: const Icon(Icons.home_outlined, size: 20),
          content: '主页',
          selected: true,
          onTap: () {},
        ),
      ),
    );
  }

  Widget _dropdown() {
    return _group(
      OptionSettingBar<int>(
        title: '界面语言',
        initialValue: _language,
        options: [
          const DropdownOption(value: 0, label: '简体中文'),
          const DropdownOption(value: 1, label: 'English'),
          DropdownOption(
            value: 2,
            label: '日本語',
            leading: Icon(Icons.translate, size: 18, color: skin.textSecondary),
          ),
        ],
        onSelect: (value) => setState(() => _language = value),
      ),
    );
  }

  Widget _colorPicker() {
    return _group(
      Row(
        spacing: TemplateSpace.md,
        children: [
          SizedBox(
            width: 260,
            height: 220,
            child: ColorPicker(
              color: _pickedColor,
              onChanged: (color) => setState(() => _pickedColor = color),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _pickedColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: skin.border),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintLayer() {
    return _group(
      Wrap(
        spacing: TemplateSpace.md,
        runSpacing: TemplateSpace.sm,
        children: [
          HintLayer(
            hint: '自动选方位的气泡提示',
            child: ActionButton(
              icon: const Icon(Icons.info_outline),
              content: const Text('悬停看提示'),
              onTap: () {},
            ),
          ),
          HintLayer(
            hint: '点击触发的提示',
            showOnTap: true,
            child: ActionButton(
              icon: const Icon(Icons.touch_app_outlined),
              content: const Text('点击看提示'),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _capsuleBar() {
    return _group(
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 48,
          child: CapsuleActionBar(
            actions: const [
              CapsuleAction(icon: Icons.search, hint: '搜索', onTap: _noop),
              CapsuleAction(icon: Icons.tune, hint: '筛选', onTap: _noop),
              CapsuleAction(icon: Icons.refresh, hint: '刷新', onTap: _noop),
            ],
          ),
        ),
      ),
    );
  }

  static void _noop() {}
}
