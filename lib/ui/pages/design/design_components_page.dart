import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

const designComponentsPageRouteKey = '/design/example/components';

/// 设计规范 · 实例页 · 组件定义
///
/// 这一层（`template_widgets.dart`）是**暂定的组件库**：颜色全部由 [TemplateSkin] 算出来，
/// 交互一律走项目的 rebound。每个组件写清四件事 —— **职责 / 状态 / 参数 / 已知问题** ——
/// 这样问题可以用组件名指认，而不是「那个有边框的东西」
class DesignComponentsPage extends StatefulWidget {
  const DesignComponentsPage({super.key});

  @override
  State<DesignComponentsPage> createState() => _DesignComponentsPageState();
}

class _DesignComponentsPageState extends State<DesignComponentsPage> {
  double _hue = TemplateHues.copper;

  // ── 演示状态 ──
  bool _switchValue = true;
  int _segmentValue = 0;
  double _sliderValue = 0.55;
  final _inputController = TextEditingController(text: '-XX:+UseG1GC');

  TemplateSkin get _skin => TemplateSkin.of(
    hue: _hue,
    dark: Theme.of(context).brightness == Brightness.dark,
  );

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = _skin;

    return ListContentPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.xxl,
        vertical: TemplateSpace.xl,
      ),
      items: [
        _buildHueSwitch(skin),
        _buildLead(skin),
        for (final group in _groups(skin)) _buildGroup(skin, group),
      ],
    );
  }

  Widget _buildHueSwitch(TemplateSkin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.xl),
      child: SizedBox(
        width: 320,
        child: TemplateSegment(
          skin: skin,
          options: [for (final item in TemplateHues.named) item.name],
          value: TemplateHues.named.indexWhere((item) => item.hue == _hue),
          onTap: (index) =>
              setState(() => _hue = TemplateHues.named[index].hue),
        ),
      ),
    );
  }

  Widget _buildLead(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.sm,
        children: [
          Text(
            '这一层是暂定的组件库，名字暂用 Template 前缀，收进 Copper 时再定名',
            style: TemplateType.item.copyWith(color: skin.textPrimary),
          ),
          Text(
            '用法：先按职责选组件；每一条下面写清它的状态、参数，以及还不齐的地方',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(TemplateSkin skin, _ComponentGroup group) {
    return TemplateSection(
      skin: skin,
      title: group.title,
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [for (final spec in group.specs) _buildSpec(skin, spec)],
      ),
    );
  }

  Widget _buildSpec(TemplateSkin skin, _ComponentSpec spec) {
    return TemplateRow(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.sm,
        children: [
          Text(
            spec.name,
            style: TemplateType.item.copyWith(
              color: skin.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            spec.duty,
            style: TemplateType.caption.copyWith(color: skin.textSecondary),
          ),
          Text(
            '状态　${spec.states}',
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
          ),
          Text(
            '参数　${spec.params}',
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
          ),
          if (spec.issue != null)
            Text(
              '未齐　${spec.issue}',
              style: TemplateType.micro.copyWith(color: skin.dangerText),
            ),
          Padding(
            padding: const EdgeInsets.only(top: TemplateSpace.xs),
            child: spec.sample,
          ),
        ],
      ),
    );
  }

  /// 组件清单：按「容器 → 行 → 控件 → 按钮 → 反馈」分组
  List<_ComponentGroup> _groups(TemplateSkin skin) => [
    (
      title: '容器与分组',
      specs: [
        (
          name: 'TemplateSection',
          duty: '分组卡：标题在卡外当组标签',
          states: '无交互，状态由它里面的组件承担',
          params: 'title（不给就是纯内容卡）· padding（默认 12）',
          issue: '卡间距 = 本组件 12 + 外层列表 12，改一边要看另一边',
          sample: TemplateSection(
            skin: skin,
            child: TemplateTwoLine(
              skin: skin,
              title: '卡内的一条内容',
              desc: '卡占满宽度、内衬 12',
            ),
          ),
        ),
      ],
    ),
    (
      title: '行',
      specs: [
        (
          name: 'TemplateRow',
          duty: '卡内一行的外壳',
          states: '静止 / 悬停 / 按下（缩放）/ 选中',
          params: 'onTap · selected · padding（默认 12）',
          issue: '行内不画分隔线，行与行只隔 2px，靠圆角块分行',
          sample: TemplateRow(
            skin: skin,
            onTap: () {},
            child: TemplateTwoLine(
              skin: skin,
              title: 'NewHorizon',
              desc: 'v2.1.4 · 大型模组 · 12.8 MB',
            ),
          ),
        ),
        (
          name: 'TemplateTwoLine',
          duty: '标题 + 说明两行',
          states: '无交互，颜色随宿主行',
          params: 'title · desc（可空）',
          issue: '两行都是单行省略',
          sample: TemplateTwoLine(skin: skin, title: '标题', desc: '说明文字'),
        ),
        (
          name: 'TemplateKeyRow',
          duty: '只读的「标签 : 值」行',
          states: '静止 / 悬停',
          params: 'title · value',
          issue: '值过长会省略',
          sample: TemplateKeyRow(
            skin: skin,
            title: '模组加载器',
            value: 'Copper Loader 0.2.0',
          ),
        ),
        (
          name: 'TemplateSwitchRow',
          duty: '开关行：点整行也能切',
          states: '开 / 关（关态的轨道有 3:1 描边）',
          params: 'title · desc · value · onTap',
          issue: '没有禁用态',
          sample: TemplateSwitchRow(
            skin: skin,
            title: '游戏存档隔离',
            desc: '存档与模组放在版本目录里',
            value: _switchValue,
            onTap: () => setState(() => _switchValue = !_switchValue),
          ),
        ),
        (
          name: 'TemplateSelectRow',
          duty: '下拉行：标签 + 下拉框',
          states: '静止 / 悬停',
          params: 'title · value · onTap（为空＝静态框）· labelWidth（150）',
          issue: '只有样子，点了不出菜单',
          sample: TemplateSelectRow(
            skin: skin,
            title: '游戏Java',
            value: 'Java 17',
          ),
        ),
      ],
    ),
    (
      title: '控件',
      specs: [
        (
          name: 'TemplateSegment',
          duty: '单选分段：单选语义只用它',
          states: '选中 / 未选中 / 悬停 / 按下',
          params: 'options · value（下标）· onTap(index)',
          issue: '没有禁用态；选项超过 4 个会挤',
          sample: TemplateSegment(
            skin: skin,
            options: const ['跟随全局', '自动分配', '自定义'],
            value: _segmentValue,
            onTap: (index) => setState(() => _segmentValue = index),
          ),
        ),
        (
          name: 'TemplateSwitch',
          duty: '开关本体（轨道 + 滑块）',
          states: '开 / 关 / 悬停 / 按下',
          params: 'value · onTap',
          issue: '尺寸固定 40 × 22',
          sample: Row(
            spacing: TemplateSpace.xl,
            children: [
              TemplateSwitch(
                skin: skin,
                value: true,
                onTap: () => setState(() => _switchValue = true),
              ),
              TemplateSwitch(
                skin: skin,
                value: false,
                onTap: () => setState(() => _switchValue = false),
              ),
            ],
          ),
        ),
        (
          name: 'TemplateSliderRow',
          duty: '滑条行：标题固定，实时值只在右侧',
          states: '静止 / 拖动中',
          params: 'title · label · value · onChanged · divisions',
          issue: '没有刻度与两端极值提示',
          sample: TemplateSliderRow(
            skin: skin,
            title: '内存上限',
            label: '${(_sliderValue * 12).toStringAsFixed(1)} GB',
            value: _sliderValue,
            onChanged: (value) => setState(() => _sliderValue = value),
          ),
        ),
        (
          name: 'TemplateInputRow',
          duty: '输入行：标签 + 输入框',
          states: '静止 / 聚焦 / 悬停',
          params: 'title · controller · hint',
          issue: '没有错误态；提交时机由宿主决定',
          sample: TemplateInputRow(
            skin: skin,
            title: 'jvm虚拟机参数',
            controller: _inputController,
            hint: '-XX:+UseG1GC',
          ),
        ),
      ],
    ),
    (
      title: '按钮',
      specs: [
        (
          name: 'TemplateButton',
          duty: '按钮四档：实心 / 标准 / 安静 / 破坏',
          states: '静止 / 悬停 / 按下',
          params: 'kind · label · icon · onTap',
          issue: '没有禁用态；实心在暗色悬停时会压到卡面 2.41:1（已知取舍）',
          sample: Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              TemplateButton(
                skin: skin,
                label: '实心',
                icon: Icons.play_arrow,
                kind: TemplateButtonKind.solid,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '标准',
                icon: Icons.copy_all,
                kind: TemplateButtonKind.plain,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '安静',
                icon: Icons.star_outline,
                kind: TemplateButtonKind.quiet,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '破坏',
                icon: Icons.delete_outline,
                kind: TemplateButtonKind.danger,
                onTap: () {},
              ),
            ],
          ),
        ),
        (
          name: 'TemplateShortcut',
          duty: '快捷入口小方块：并列入口',
          states: '静止 / 悬停 / 按下',
          params: 'icon · label · onTap',
          issue: '没有禁用态；宽度自适应，不再逐个定宽',
          sample: Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              TemplateShortcut(
                skin: skin,
                icon: Icons.save,
                label: '存档文件夹',
                onTap: () {},
              ),
              TemplateShortcut(
                skin: skin,
                icon: Icons.map_outlined,
                label: '地图文件夹',
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    ),
    (
      title: '反馈与展示',
      specs: [
        (
          name: 'TemplateNotice',
          duty: '提示条：底色 + 左边 3px 强调线',
          states: '静态',
          params: 'text · icon',
          issue: '没有「关掉就不再显示」那套（customSetting）',
          sample: TemplateNotice(
            skin: skin,
            text: 'tip：可以把资源或游戏本体拖进 Copper 直接导入',
          ),
        ),
        (
          name: 'TemplateProgressBar',
          duty: '细轨 + 实心填充',
          states: '静态，值由外部给',
          params: 'value（0~1）· height',
          issue: '单色，没有分段',
          sample: Column(
            spacing: TemplateSpace.md,
            children: [
              TemplateProgressBar(skin: skin, value: 0.3, height: 8),
              TemplateProgressBar(skin: skin, value: 0.72, height: 8),
            ],
          ),
        ),
      ],
    ),
  ];
}

/// 一组组件（例：行 / 控件 / 按钮）
typedef _ComponentGroup = ({String title, List<_ComponentSpec> specs});

/// 一个组件的定义：职责（干什么）/ 状态（有哪些态）/ 参数 / 已知问题 + 实物小样
typedef _ComponentSpec = ({
  String name,
  String duty,
  String states,
  String params,
  String? issue,
  Widget sample,
});
