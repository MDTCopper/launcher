import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/copper_card.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_list_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/setting_bar/option_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/setting_bar_row.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

const designExamplePageRouteKey = '/design/example';

/// 设计规范 · 实例页
///
/// 把规范拼成一个完整页面，讲「一个页面怎么搭起来」；
/// 每块标题后的括号是它在规范页里的对应条目，写新页面照这个骨架起手
class DesignExamplePage extends StatefulWidget {
  const DesignExamplePage({super.key});

  @override
  State<DesignExamplePage> createState() => _DesignExamplePageState();
}

class _DesignExamplePageState extends State<DesignExamplePage> {
  /// 依据表的出处列宽
  static const double _labelWidth = 120;

  // ── 演示状态 ──
  bool _checkUpdateOnLaunch = true;
  bool _isolateData = false;
  double _memoryRatio = 0.5;
  String _mirror = '自动';
  int _filterIndex = 0;
  String? _pickedItem;

  static const _filters = ['全部', '本体', '模组'];
  static const _mirrorOptions = [
    DropdownOption(value: '自动', label: '自动选最快的节点'),
    DropdownOption(value: '直连', label: '只用直连'),
    DropdownOption(value: '关闭', label: '不走镜像'),
  ];
  static const _demoItems = [
    (name: 'Copper 加载器', desc: '模组加载器 · v0.2.0', tag: '模组'),
    (name: 'Mindustry 本体', desc: 'v160.5 · 桌面版', tag: '本体'),
    (name: 'NewHorizon', desc: '大型模组 · 10.4 MB', tag: '模组'),
  ];

  /// 起手清单：新页面照这个顺序做
  static const _startupChecklist = [
    '建 `xxx_page.dart`，声明 `const xxxPageRouteKey = \'/xxx\';`',
    'routeMap 里加一行；要进导航栏就在 app_shell.dart 的分组里加一条 RailItem',
    '页面 = ListContentPanel(items: [...])，内衬 horizontal: AppSpacing.block / vertical: AppSpacing.related',
    '每块 = ContentPanelModule(title:, child:)；条目多的用 ContentListPanelModule',
    '几何取 design_system.dart，颜色取 AppColors，文字取 textTheme 的语义名',
    '新组件写完回规范页第 7 节补一行选型',
  ];

  /// 桌面 UI 规范的原文结论（2026-10-05 查，出处见 components.md 的规范节）
  static const _typographyEvidence = <({String source, String finding})>[
    (
      source: 'Apple HIG',
      finding:
          'macOS 默认字号 13pt、最小 10pt；Headline 与 Body 同为 13pt，只靠字重区分 —— 层级靠字重，不靠把尺寸吹大',
    ),
    (
      source: 'IBM Carbon',
      finding:
          '桌面 productive 档基准 14px：body 14/20、heading-compact 14/18 Semibold，标题与正文同尺寸；label 与 helper 12/16',
    ),
    (
      source: 'Windows / Fluent 2',
      finding:
          'Windows 档位少而步长大：Caption 12、Body 14、Subtitle 20、Title 28；标题一律 Semibold、正文 Regular',
    ),
    (
      source: 'Fluent 2 对比度',
      finding: '正文 ≥ 4.5:1，大字号（加粗 >18.5 或常规 >24）可放宽到 3:1 —— 铜色标题在浅色卡上约 2:1，不合规',
    ),
    (
      source: 'GNOME HIG',
      finding: '尽量减少字号与字重的种类；次要信息「更小 + 更浅」、重要信息「更粗 + 更深」；禁止全大写',
    ),
    (
      source: 'WCAG 2.2',
      finding:
          '可点目标至少 24×24（桌面底线 2.5.8），触控达 44×44（2.5.5）—— 现有 iconButton 24 / item 48 正好卡住',
    ),
  ];

  // ── 交互 ──

  void _showWarningDialog() {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '删除这个版本？',
      content: '只删记录与启动器自己下载的文件；你自己放进来的本体不受影响',
      action: () {},
    );
  }

  void _showCustomDialog() {
    showDefaultDialogPopup(
      pageBuilder: (context, animation, secondaryAnimation) {
        final theme = Theme.of(context);
        return CopperSingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.group,
            children: [
              Text('自定义内容的弹窗', style: theme.textTheme.titleLarge),
              Text(
                '壳子是同一套：圆角、内衬与那圈「顶粗两侧细」的描边都在 showDefaultDialogPopup 里，'
                '页面只负责给内容，内容自己滚',
                style: theme.textTheme.bodyMedium,
              ),
              for (final line in _startupChecklist)
                Text('· $line', style: theme.textTheme.bodySmall),
            ],
          ),
        );
      },
    );
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
        _buildCompareModule(),
        _buildOverviewModule(),
        _buildSettingModule(),
        _buildListModule(),
        _buildEmptyModule(),
        _buildDialogModule(),
        _buildChecklistModule(),
      ],
    );
  }

  // ════════ 说明 ════════

  Widget _buildIntroModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '这是什么',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.related,
        children: [
          Text(
            '规范页讲「有哪些刻度、什么场合用什么组件」，这一页讲「一个页面怎么搭起来」——'
            '它是一个普通功能页，也是可以直接抄的样板',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            '骨架、间距、圆角、文字角色全部取自规范，页面里没有一处硬写的数值；'
            '每块标题后的括号是它在规范页里的对应条目',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
          ),
        ],
      ),
    );
  }

  // ════════ 0 对照：文字层级（桌面密度模型） ════════

  Widget _buildCompareModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '0 对照：文字层级（现状 / 桌面密度改法）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.section,
        children: [
          Text(
            '两边的结构与内容完全一样，差别只在「用哪一档文字角色 + 用哪个语义色」，'
            '所以下面的对照不会掺进布局变量',
            style: theme.textTheme.bodySmall,
          ),
          _buildSpecimen(
            caption:
                '现状：卡片标题 headlineSmall 16 bold + 主题色；条目 headlineMedium 18 bold；正文 bodyMedium + itemSecondary',
            tuned: false,
          ),
          _buildSpecimen(
            caption:
                '改法：卡片标题 titleMedium 14 w600 + itemPrimary；条目 bodyMedium 14 + itemPrimary；'
                '说明 bodySmall 12 + itemSecondary；主题色只留给交互与图标',
            tuned: true,
          ),
          Text('依据：桌面 UI 规范的原文结论', style: theme.textTheme.titleSmall),
          for (final item in _typographyEvidence)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.group,
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(item.source, style: theme.textTheme.titleSmall),
                ),
                Expanded(
                  child: Text(item.finding, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          Text(
            '注：这一块是试验田，样式写在页面里、没有动公共组件；定稿后再落到 textTheme 与 ContentPanelModule',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 同一组内容渲染两遍；tuned 为 true 走桌面密度改法
  Widget _buildSpecimen({required String caption, required bool tuned}) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final textTheme = theme.textTheme;

    // 改法只做三件事：换 textTheme 的档位、标题去主题色、正文提到 itemPrimary
    final titleStyle = tuned
        ? textTheme.titleMedium?.copyWith(color: colors.itemPrimary)
        : textTheme.headlineSmall?.copyWith(color: colors.interactive);
    final itemStyle = tuned
        ? textTheme.bodyMedium?.copyWith(color: colors.itemPrimary)
        : textTheme.headlineMedium;
    final bodyStyle = tuned
        ? textTheme.bodyMedium?.copyWith(color: colors.itemPrimary)
        : textTheme.bodyMedium;
    final hintStyle = textTheme.bodySmall?.copyWith(
      color: tuned ? colors.itemSecondary : colors.itemHint,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.related,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        CopperCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(AppSpacing.section),
          borderRadius: AppRadius.itemShape,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.related,
            children: [
              Text('运行环境', style: titleStyle),
              Text('下面这些是启动游戏要用到的东西', style: hintStyle),
              Row(
                spacing: AppSpacing.group,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Java 运行环境', style: itemStyle),
                        Text('已安装 · JDK 25', style: hintStyle),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: AppIconSize.item,
                    color: colors.itemHint,
                  ),
                ],
              ),
              Text('正文示例：把这份 Java 拉起来、摆好参数，再把游戏画面接到设备上。', style: bodyStyle),
            ],
          ),
        ),
      ],
    );
  }

  // ════════ 1 概览（条目级：ReboundListTile） ════════

  Widget _buildOverviewModule() {
    final theme = Theme.of(context);

    return ContentListPanelModule(
      title: '1 概览（选型表：列表项）',
      children: [
        ReboundListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('当前版本'),
          subtitle: const Text('v160.5 · 桌面版 · 已隔离数据目录'),
          trailing: IconTextButton(
            icon: Icons.settings,
            content: '设置',
            onTap: () {},
          ),
          onTap: () {},
        ),
        ReboundListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('数据目录'),
          subtitle: const Text('默认目录 · 存档与模组都在这里'),
          trailing: Text('12.4 MB', style: theme.textTheme.bodySmall),
          onTap: () {},
        ),
      ],
    );
  }

  // ════════ 2 设置行（SettingBarRow 家族） ════════

  Widget _buildSettingModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '2 设置行（选型表：设置行）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          SwitchSettingBar(
            title: '启动时检查更新',
            value: _checkUpdateOnLaunch,
            onChanged: (value) => setState(() => _checkUpdateOnLaunch = value),
          ),
          SwitchSettingBar(
            title: '隔离游戏数据目录',
            value: _isolateData,
            onChanged: (value) => setState(() => _isolateData = value),
          ),
          SliderSettingBar(
            title: '内存上限',
            value: _memoryRatio,
            label: '${(_memoryRatio * 100).round()}%',
            onChanged: (value) => setState(() => _memoryRatio = value),
          ),
          OptionSettingBar<String>(
            title: '下载镜像',
            initialValue: _mirror,
            options: _mirrorOptions,
            onSelect: (value) => setState(() => _mirror = value),
          ),
          SettingBarRow(
            title: '当前状态',
            control: Text('已就绪', style: theme.textTheme.bodyMedium),
          ),
          Text(
            '行内说明写在控件下面、取 bodySmall；'
            '行与行之间取 related，别各写各的间距',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // ════════ 3 列表与筛选（ActionButton / ContentListPanelModule） ════════

  Widget _buildListModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final visible = _demoItems
        .where(
          (item) => _filterIndex == 0 || item.tag == _filters[_filterIndex],
        )
        .toList();

    return ContentPanelModule(
      title: '3 列表与筛选（选型表：选项 chips / 列表项）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.group,
        children: [
          // 筛选用 ActionButton，选中态由 selected 驱动，不要在页面里改颜色
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              for (var i = 0; i < _filters.length; i++)
                ActionButton(
                  content: Text(_filters[i]),
                  selected: _filterIndex == i,
                  onTap: () => setState(() => _filterIndex = i),
                ),
            ],
          ),
          for (final item in visible)
            ReboundListTile(
              leading: const Icon(Icons.extension_outlined),
              title: Text(item.name),
              subtitle: Text(item.desc),
              selected: _pickedItem == item.name,
              onTap: () => setState(() => _pickedItem = item.name),
              trailing: HintLayer(
                hint: '删除这一项',
                child: ReboundButton(
                  onTap: () {},
                  child: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          Row(
            spacing: AppSpacing.related,
            children: [
              IconTextButton(icon: Icons.refresh, content: '刷新', onTap: () {}),
              IconTextButton(icon: Icons.add, content: '添加', onTap: () {}),
              const Spacer(),
              Text(
                '已选 ${_pickedItem ?? '无'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════ 4 空态（图标 hero） ════════

  Widget _buildEmptyModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '4 空态（图标尺寸 hero）',
      child: Center(
        child: Column(
          spacing: AppSpacing.related,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: AppIconSize.hero,
              color: colors.itemHint,
            ),
            Text('这里还没有东西', style: theme.textTheme.titleMedium),
            Text(
              '空态要说清「怎么才会有」，不要只写一句「暂无数据」',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemHint,
              ),
            ),
            IconTextButton(icon: Icons.add, content: '新建一个', onTap: () {}),
          ],
        ),
      ),
    );
  }

  // ════════ 5 对话框（CustomAnimatedDialog） ════════

  Widget _buildDialogModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '5 对话框（选型表：对话框）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text(
            '两个入口都是现成实现：确认类走 showConfirmationPopup，自定义内容走 showDefaultDialogPopup。'
            '圆角与描边在实现里，页面不手写',
            style: theme.textTheme.bodySmall,
          ),
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              IconTextButton(
                icon: Icons.warning_amber_outlined,
                content: '确认类弹窗',
                onTap: _showWarningDialog,
              ),
              IconTextButton(
                icon: Icons.info_outline,
                content: '自定义内容弹窗',
                onTap: _showCustomDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════ 6 起手清单 ════════

  Widget _buildChecklistModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '6 起手清单',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.related,
        children: [
          Text('新页面照这个顺序做，做完在规范页第 7 节补一行选型', style: theme.textTheme.bodySmall),
          for (var i = 0; i < _startupChecklist.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.related,
              children: [
                Text(
                  '${i + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.interactive,
                  ),
                ),
                Expanded(
                  child: Text(
                    _startupChecklist[i],
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
