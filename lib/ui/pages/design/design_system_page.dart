import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/rebound/copper_slider.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_switch.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/pages/design/design_example_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

const designSystemPageRouteKey = '/design';

/// 设计规范页
///
/// 把几何令牌、文字角色、组件选型与交互状态摆在一起，供写 UI 时对照；
/// 本页自身只用规范内的数值，等于规范的参考实现
class DesignSystemPage extends StatefulWidget {
  const DesignSystemPage({super.key});

  @override
  State<DesignSystemPage> createState() => _DesignSystemPageState();
}

class _DesignSystemPageState extends State<DesignSystemPage> {
  /// 对照表的名称列宽；窗口缩窄时不许把右边挤爆
  static const double _labelWidth = 140;

  // ── 演示状态 ──
  bool _switchOn = true;
  bool _actionSelected = true;
  bool _tileSelected = false;
  double _sliderValue = 0.4;

  // ── 尺度表：名称 / 值 / 用在哪 ──
  static const _spacingScale = <({String name, double value, String usage})>[
    (name: 'inline', value: AppSpacing.inline, usage: '图标与文字的间隙、徽标内衬'),
    (name: 'tight', value: AppSpacing.tight, usage: '紧邻的同类元素、控件的紧凑内衬'),
    (name: 'related', value: AppSpacing.related, usage: '同一组内的元素之间'),
    (name: 'group', value: AppSpacing.group, usage: '组与组之间、标题到内容'),
    (name: 'section', value: AppSpacing.section, usage: '区块之间、卡片内衬'),
    (name: 'block', value: AppSpacing.block, usage: '页面内的大块之间、页面横向内衬'),
    (name: 'page', value: AppSpacing.page, usage: '空态与大块留白'),
  ];

  static const _radiusScale = <({String name, double value, String usage})>[
    (name: 'control', value: AppRadius.control, usage: '按钮 / 输入框 / 选项 / 徽标'),
    (name: 'item', value: AppRadius.item, usage: '瓦片 / 菜单项 / 面板模块'),
    (name: 'panel', value: AppRadius.panel, usage: '卡片 / 对话框 / 浮层'),
    (name: 'container', value: AppRadius.container, usage: '页面大块 / 图片 / 首屏'),
    (name: 'pill', value: AppRadius.pill, usage: '胶囊 / 圆形'),
  ];

  static const _iconScale = <({String name, double value, String usage})>[
    (name: 'inline', value: AppIconSize.inline, usage: '标签旁、紧凑说明行'),
    (name: 'item', value: AppIconSize.item, usage: '按钮图标、列表项图标'),
    (name: 'normal', value: AppIconSize.normal, usage: '导航栏、顶栏工具'),
    (name: 'large', value: AppIconSize.large, usage: '卡片头部、次级空态'),
    (name: 'hero', value: AppIconSize.hero, usage: '空态主图、头像位'),
  ];

  static const _heightScale = <({String name, double value, String usage})>[
    (
      name: 'iconButton',
      value: AppControlHeight.iconButton,
      usage: '纯图标按钮、顶栏工具',
    ),
    (name: 'compact', value: AppControlHeight.compact, usage: '小按钮 / 牌子 / 徽标'),
    (name: 'standard', value: AppControlHeight.standard, usage: '标准按钮、输入框、顶栏'),
    (name: 'item', value: AppControlHeight.item, usage: '列表项与触控目标的下限'),
  ];

  // ── 组件选型：要什么 / 用什么 / 别用什么 ──
  static const _componentChoices = <({String need, String use, String avoid})>[
    (
      need: '页面骨架',
      use: 'ListContentPanel',
      avoid: '别自己写 SingleChildScrollView + Column',
    ),
    (
      need: '页面区块',
      use: 'ContentPanelModule',
      avoid: '别手写 Container + BoxDecoration 当卡片',
    ),
    (
      need: '长列表模块 / 网格模块',
      use: 'ContentListPanelModule / ContentGridPanelModule',
      avoid: '模块里别再套一层滚动容器',
    ),
    (
      need: '动作按钮（点了就执行）',
      use: 'IconTextButton（weight: primary / secondary / tertiary / danger）',
      avoid: '别用 ActionButton，它有选中态；一个视图里别放两个 primary；删除类用 danger',
    ),
    (
      need: '选项 / 多选 chips',
      use: 'ActionButton',
      avoid: '别用 IconTextButton 冒充选项',
    ),
    (
      need: '纯图标按钮',
      use: 'ReboundButton + HintLayer',
      avoid: '别用裸 IconButton，没有回弹与提示',
    ),
    (need: '列表项', use: 'ReboundListTile', avoid: '别用 ListTile 或手写 Row'),
    (need: '导航项', use: 'NavigationTile', avoid: '自己拼图标 + 文本会丢掉选中态'),
    (
      need: '设置行',
      use:
          'SettingBarRow + Switch / Option / Slider / Input / Checkbox / Segment SettingBar',
      avoid: '别在页面里手拼设置控件',
    ),
    (
      need: '下拉单选 / 多选',
      use: 'DropdownLayer',
      avoid: '别用 DropdownButton，样式与主题不一致',
    ),
    (need: '悬停提示', use: 'HintLayer', avoid: '别用 Tooltip'),
    (
      need: '滚动容器',
      use: 'CopperSingleChildScrollView',
      avoid: '别用裸 SingleChildScrollView，滚动条样式不一样',
    ),
    (
      need: '开关 / 滑条 / 复选',
      use: 'ReboundSwitch / CopperSlider / ReboundCheckbox',
      avoid: '别用 flutter 的同名原生件',
    ),
    (need: '分段选择', use: 'SegmentedReboundButton', avoid: '别用 ToggleButtons'),
    (need: '对话框', use: 'CustomAnimatedDialog', avoid: '别手写 Dialog，也别手写那圈描边'),
    (need: '页内提示条', use: 'buildWarningBar', avoid: '同样的提示别在页面里复制一遍'),
  ];

  // ── 历史数值的归位表 ──
  static const _legacyValues = <({String old, String target, String where})>[
    (old: '圆角 6', target: 'item 8', where: '菜单项、README 块、对话框内块'),
    (old: '圆角 10', target: 'item 8 或 panel 12', where: '下载页卡片'),
    (old: '内衬 3 / 7 / 10 / 14 / 20', target: '最近的刻度', where: '零散的内衬与间距'),
    (old: '图标 14 / 15 / 17 / 18', target: 'item 20', where: '行内图标'),
    (old: '图标 28 / 30', target: 'large 32', where: '卡片头部'),
    (
      old: '字号 15 / 18 / 20 / 28',
      target: 'textTheme 语义名',
      where: '页面与组件里硬写的字号',
    ),
    (
      old: 'Colors.grey / Color(0x…)',
      target: 'AppColors 的语义色',
      where: '说明文字、分隔',
    ),
  ];

  /// 文字角色：语义名 / 解析出的样式 / 用在哪
  List<({String name, TextStyle? style, String usage})> _typeRoles(
    TextTheme textTheme,
  ) {
    return [
      (
        name: 'displayLarge',
        style: textTheme.displayLarge,
        usage: '首屏主标题、版本号这类英雄文字',
      ),
      (name: 'displayMedium', style: textTheme.displayMedium, usage: '次级英雄文字'),
      (name: 'displaySmall', style: textTheme.displaySmall, usage: '三级英雄文字'),
      (name: 'headlineLarge', style: textTheme.headlineLarge, usage: '页面级大标题'),
      (
        name: 'headlineMedium',
        style: textTheme.headlineMedium,
        usage: '列表瓦片标题',
      ),
      (name: 'headlineSmall', style: textTheme.headlineSmall, usage: '面板模块标题'),
      (name: 'titleLarge', style: textTheme.titleLarge, usage: '大标题行'),
      (name: 'titleMedium', style: textTheme.titleMedium, usage: '卡片标题、设置项标题'),
      (name: 'titleSmall', style: textTheme.titleSmall, usage: '小节标题、键名'),
      (name: 'bodyLarge', style: textTheme.bodyLarge, usage: '大段正文'),
      (name: 'bodyMedium', style: textTheme.bodyMedium, usage: '正文与按钮文字'),
      (name: 'bodySmall', style: textTheme.bodySmall, usage: '次要说明'),
      (name: 'labelLarge', style: textTheme.labelLarge, usage: '标签'),
      (name: 'labelMedium', style: textTheme.labelMedium, usage: '小标签、徽标'),
      (name: 'labelSmall', style: textTheme.labelSmall, usage: '版本号这类最小字'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.block,
        vertical: AppSpacing.related,
      ),
      items: [
        _buildIntroModule(),
        _buildSpacingModule(),
        _buildRadiusModule(),
        _buildBorderModule(),
        _buildIconModule(),
        _buildHeightModule(),
        _buildTypeModule(),
        _buildComponentModule(),
        _buildStateModule(),
        _buildLegacyModule(),
      ],
    );
  }

  // ════════ 0. 怎么用 ════════

  Widget _buildIntroModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.itemHint,
    );
    final rules = [
      '几何参数取 design_system.dart 的 AppSpacing / AppRadius / AppBorderWidth / AppIconSize / AppControlHeight，不写字面量',
      '颜色取 AppColors.of(context) 的语义色，文字取 theme.textTheme 的语义名，不写 fontSize 与 Colors.xxx',
      '页面骨架用 ListContentPanel，区块用 ContentPanelModule，长列表用 ContentListPanelModule',
      '动手前先在本页与「组件选型」里找，再翻 flutter 与 pub，都不合适才新建组件，新建后回本页补一节',
      '页面骨架怎么拼看实例页：它就是一个按本规范写成的普通功能页，可以整页照抄',
    ];

    return ContentPanelModule(
      title: '怎么用这套规范',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.related,
        children: [
          Text(
            '本页就是规范的参考实现：它自己只用规范内的数值，写新页面对照它抄',
            style: theme.textTheme.bodyMedium,
          ),
          for (final rule in rules)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.related,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.tight),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: AppIconSize.inline,
                    color: colors.interactive,
                  ),
                ),
                Expanded(child: Text(rule, style: hintStyle)),
              ],
            ),
          IconTextButton(
            icon: Icons.open_in_new,
            content: '看实例页：一个完整页面长什么样',
            onTap: () => Navigator.pushNamed(
              context,
              designExamplePageRouteKey,
              arguments: {'lead': '设计规范', 'title': '实例'},
            ),
          ),
        ],
      ),
    );
  }

  // ════════ 1. 间距刻度 ════════

  Widget _buildSpacingModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '1 间距刻度 AppSpacing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text(
            '两个方块之间就是这一档的实际间隙；2 只用于行内微调，其余都是 4 的倍数',
            style: theme.textTheme.bodySmall,
          ),
          for (final item in _spacingScale)
            Row(
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(
                    '${item.name}  ${item.value.round()}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _buildBlock(),
                SizedBox(width: item.value),
                _buildBlock(),
                const SizedBox(width: AppSpacing.block),
                Expanded(
                  child: Text(item.usage, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          Text(
            '规则：同一组内的元素取同一档；相邻两档的差值不小于 4，否则肉眼分不出层级',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  /// 间距演示用的小方块
  Widget _buildBlock() {
    final colors = AppColors.of(context);
    return Container(
      width: AppSpacing.section,
      height: AppSpacing.section,
      decoration: BoxDecoration(
        color: colors.interactive,
        borderRadius: AppRadius.controlShape,
      ),
    );
  }

  // ════════ 2. 圆角刻度 ════════

  Widget _buildRadiusModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '2 圆角刻度 AppRadius',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text(
            '按层级取：控件 < 条目 < 面板 < 容器；嵌套时内层比外层小一档，两圈才不会打架',
            style: theme.textTheme.bodySmall,
          ),
          for (final item in _radiusScale)
            Row(
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(
                    '${item.name}  ${item.value.round()}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: 72,
                  height: AppControlHeight.standard,
                  decoration: BoxDecoration(
                    color: colors.interactive.withAlpha(60),
                    border: Border.all(
                      color: colors.interactive,
                      width: AppBorderWidth.hairline,
                    ),
                    borderRadius: BorderRadius.circular(item.value),
                  ),
                ),
                const SizedBox(width: AppSpacing.block),
                Expanded(
                  child: Text(item.usage, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ════════ 3. 描边宽度 ════════

  Widget _buildBorderModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final widths = [
      (
        name: 'hairline',
        value: AppBorderWidth.hairline,
        usage: '常规描边、分隔、描边进度轨道',
      ),
      (
        name: 'emphasis',
        value: AppBorderWidth.emphasis,
        usage: '聚焦 / 选中 / 输入框这类要点出来的状态',
      ),
    ];

    return ContentPanelModule(
      title: '3 描边宽度 AppBorderWidth',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          for (final item in widths)
            Row(
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(
                    '${item.name}  ${item.value.round()}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: 72,
                  height: AppControlHeight.standard,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.interactive,
                      width: item.value,
                    ),
                    borderRadius: AppRadius.controlShape,
                  ),
                ),
                const SizedBox(width: AppSpacing.block),
                Expanded(
                  child: Text(item.usage, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          Text(
            '规则：暗色靠描边分层、浅色靠底色分层，所以浅色下不必为了对比再加一圈描边；'
            '对话框那套「顶粗两侧细」取 CustomAnimatedDialog 给的壳，不在页面里手写',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  // ════════ 4. 图标尺寸 ════════

  Widget _buildIconModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '4 图标尺寸 AppIconSize',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          for (final item in _iconScale)
            Row(
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(
                    '${item.name}  ${item.value.round()}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                SizedBox(
                  width: AppIconSize.hero,
                  child: Icon(
                    Icons.widgets_outlined,
                    size: item.value,
                    color: colors.interactive,
                  ),
                ),
                const SizedBox(width: AppSpacing.block),
                Expanded(
                  child: Text(item.usage, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          Text(
            '规则：同一行里图标与文字不写 size，交给 IconTheme；单独给 size 时取上面这几档',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  // ════════ 5. 控件高度 ════════

  Widget _buildHeightModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '5 控件高度 AppControlHeight',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          for (final item in _heightScale)
            Row(
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(
                    '${item.name}  ${item.value.round()}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: 72,
                  height: item.value,
                  decoration: BoxDecoration(
                    color: colors.interactive.withAlpha(60),
                    borderRadius: AppRadius.controlShape,
                    border: Border.all(
                      color: colors.interactive,
                      width: AppBorderWidth.hairline,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.block),
                Expanded(
                  child: Text(item.usage, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          Text(
            '规则：同一行里的控件取同一档；高度靠内衬与内容撑出来，别写死 SizedBox',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  // ════════ 6. 文字角色 ════════

  Widget _buildTypeModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '6 文字角色 textTheme',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text(
            '下面每行用该角色自己的样式渲染；写界面时只选角色，不写 fontSize 与 fontWeight',
            style: theme.textTheme.bodySmall,
          ),
          for (final role in _typeRoles(theme.textTheme))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.name, style: theme.textTheme.titleSmall),
                      Text(
                        _describeStyle(role.style),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppSpacing.tight,
                    children: [
                      Text(
                        'Copper 启动器',
                        style: role.style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(role.usage, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 把样式里的字号 / 字重 / 颜色来源写成一行说明
  String _describeStyle(TextStyle? style) {
    if (style == null) return '未定义';
    final weight = switch (style.fontWeight) {
      FontWeight.bold => 'bold',
      FontWeight.w600 => 'w600',
      FontWeight.w900 => 'w900',
      _ => 'normal',
    };
    return '${style.fontSize?.round() ?? '-'} / $weight';
  }

  // ════════ 7. 组件选型 ════════

  Widget _buildComponentModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '7 组件选型',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text(
            '左边是要做的事与对应组件，右边是别再用的写法；窗口窄了会自己折行，不会互相挤',
            style: theme.textTheme.bodySmall,
          ),
          for (final item in _componentChoices)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppSpacing.tight,
                    children: [
                      Text(item.need, style: theme.textTheme.bodyMedium),
                      Text(
                        item.use,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.interactive,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.group),
                Expanded(
                  flex: 4,
                  child: Text(
                    item.avoid,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.itemHint,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ════════ 8. 交互状态 ════════

  Widget _buildStateModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '8 交互状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.section,
        children: [
          Text(
            '常态 / 选中 / 禁用在这里看，悬停与按下把鼠标移上去、按住不放就是实际效果',
            style: theme.textTheme.bodySmall,
          ),
          _buildStateRow(
            label: 'IconTextButton（动作）',
            children: [
              IconTextButton(
                icon: Icons.download,
                content: '动作按钮',
                onTap: () {},
              ),
              IconTextButton(icon: Icons.block, content: '禁用', onTap: null),
              HintLayer(
                hint: '纯图标按钮配 HintLayer',
                child: ReboundButton(
                  onTap: () {},
                  child: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          _buildStateRow(
            label: '动作重量 weight（一个视图只放一个 primary）',
            children: [
              IconTextButton(
                icon: Icons.play_arrow,
                content: 'primary',
                weight: ActionWeight.primary,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.settings,
                content: 'secondary（默认）',
                weight: ActionWeight.secondary,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.folder_open,
                content: 'tertiary',
                weight: ActionWeight.tertiary,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.delete_outline,
                content: 'danger（破坏性）',
                weight: ActionWeight.danger,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.block,
                content: '禁用（实心档）',
                weight: ActionWeight.primary,
                onTap: null,
              ),
            ],
          ),
          _buildStateRow(
            label: 'ActionButton（选项，可选中）',
            children: [
              ActionButton(
                icon: const Icon(Icons.grid_view),
                content: Text(_actionSelected ? '已选中' : '点我选中'),
                selected: _actionSelected,
                onTap: () => setState(() => _actionSelected = !_actionSelected),
              ),
              ActionButton(
                icon: const Icon(Icons.grid_view),
                content: const Text('始终选中'),
                selected: true,
                onTap: () {},
              ),
              ActionButton(
                icon: const Icon(Icons.grid_view),
                content: const Text('禁用'),
                enable: false,
              ),
            ],
          ),
          _buildStateRow(
            label: 'ReboundListTile（列表项）',
            children: [
              SizedBox(
                width: 280,
                child: ReboundListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(_tileSelected ? '已选中' : '未选中'),
                  subtitle: const Text('点一下切换选中态'),
                  selected: _tileSelected,
                  onTap: () => setState(() => _tileSelected = !_tileSelected),
                ),
              ),
              SizedBox(
                width: 280,
                child: ReboundListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('禁用'),
                  subtitle: const Text('走 enable: false，不改颜色冒充'),
                  enable: false,
                ),
              ),
            ],
          ),
          _buildStateRow(
            label: 'ReboundSwitch / CopperSlider（开关与滑条）',
            children: [
              ReboundSwitch(
                value: _switchOn,
                onChanged: (value) => setState(() => _switchOn = value),
              ),
              SizedBox(
                width: 240,
                child: CopperSlider(
                  value: _sliderValue,
                  divisions: 10,
                  label: '${(_sliderValue * 100).round()}',
                  onChanged: (value) => setState(() => _sliderValue = value),
                ),
              ),
            ],
          ),
          Text(
            '规则：能点的东西都要有常态 / 悬停 / 按下 / 选中 / 禁用五态；'
            '禁用靠 onTap: null 或 enable: false，不要在页面里改颜色冒充禁用（'
            'IconTextButton 现在会自己置灰并丢掉实心底）；'
            '破坏性动作用 danger，别用 primary 表达「删除」',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.itemHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 一行状态演示：左边标签、右边若干控件
  Widget _buildStateRow({
    required String label,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.group),
        Expanded(
          flex: 5,
          child: Wrap(
            spacing: AppSpacing.group,
            runSpacing: AppSpacing.group,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
        ),
      ],
    );
  }

  // ════════ 9. 历史数值的归位 ════════

  Widget _buildLegacyModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '9 历史数值的归位',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text(
            '左边这些是历史存量，新代码不要再写；收敛到右边时按「最近的一档」取，不要为了对齐再添新档',
            style: theme.textTheme.bodySmall,
          ),
          for (final item in _legacyValues)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppSpacing.tight,
                    children: [
                      Text(
                        item.old,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.warning,
                        ),
                      ),
                      Text(item.target, style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.group),
                Expanded(
                  flex: 4,
                  child: Text(item.where, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
