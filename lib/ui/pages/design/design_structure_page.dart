import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
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

/// 设计规范 · 实例页 · 结构样板
///
/// 一个按规范拼起来的普通功能页：概览 / 设置行 / 列表与筛选 / 对话框 / 起手清单；
/// 每块标题都标了它在规范里的对应条目，写新页面可以整页照抄
class DesignStructurePage extends StatefulWidget {
  const DesignStructurePage({super.key});

  @override
  State<DesignStructurePage> createState() => _DesignStructurePageState();
}

class _DesignStructurePageState extends State<DesignStructurePage> {
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
        _buildOverviewModule(),
        _buildSettingModule(),
        _buildListModule(),
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
              IconTextButton(
                icon: Icons.add,
                content: '添加',
                weight: ActionWeight.primary,
                onTap: () {},
              ),
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

  // ════════ 4 对话框（CustomAnimatedDialog） ════════

  Widget _buildDialogModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '4 对话框（选型表：对话框）',
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

  // ════════ 5 起手清单 ════════

  Widget _buildChecklistModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '5 起手清单',
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
