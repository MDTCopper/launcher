import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/setting_bar/setting_bar_row.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/tips/warning_bar.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

const designAboutReworkPageRouteKey = '/design/example/about';

/// 设计规范 · 实例页 · 关于页重做
///
/// 拿真实页面当素材：`ui/pages/overview/version_setting.dart` 的「关于」分项。
/// 原实现还在原位跑，这里只是**按规范重做一版**，并把它暴露出来的
/// 「用途不明确 / 参数神出鬼没」逐条点名，作为组件库规范的输入
class DesignAboutReworkPage extends StatefulWidget {
  const DesignAboutReworkPage({super.key});

  @override
  State<DesignAboutReworkPage> createState() => _DesignAboutReworkPageState();
}

class _DesignAboutReworkPageState extends State<DesignAboutReworkPage> {
  /// 快捷方式按钮的定宽：原实现硬写在每个调用处，这里集中成一个常量
  static const double _shortcutWidth = 136;

  static const _shortcuts = <({IconData icon, String label})>[
    (icon: Icons.save, label: '存档文件夹'),
    (icon: Icons.map_outlined, label: '地图文件夹'),
    (icon: Icons.paste, label: '蓝图文件夹'),
    (icon: Icons.extension_outlined, label: '模组文件夹'),
    (icon: Icons.file_copy, label: '导出崩溃日志'),
    (icon: Icons.broken_image_outlined, label: '查看崩溃日志'),
    (icon: Icons.download_for_offline_outlined, label: '导入本机存档'),
  ];

  /// 要规范的地方：位置 / 现象 / 建议
  static const _problems = <({String where, String problem, String fix})>[
    (
      where: '版本信息的两条信息行',
      problem:
          '页面内联的 `buildInfo()` 局部函数（`labelLarge` + `Spacer` + 默认 Text 样式），没有对应组件',
      fix: '用 `SettingBarRow`（标题列 + 右侧控件），别在页面里再写一份',
    ),
    (
      where: '版本瓦片',
      problem:
          '`ReboundListTile(borderRadius: circular(4), padding: all(4))` —— 圆角与内衬硬写在调用处',
      fix: '取 `AppRadius.controlShape` / `AppSpacing.tight`，与别处的瓦片一致',
    ),
    (
      where: '动作行（收藏 / 生成脚本 / 补齐加载器 / 删除版本）',
      problem: '四个动作全是 `IconTextButton` 默认重量，**破坏性的「删除版本」与「收藏」一样重**',
      fix: '按 `ActionWeight` 分级，删除类用 `danger`（2026-10-05 加的这一档，重做版里已用上）',
    ),
    (
      where: '快捷方式',
      problem:
          '`Wrap(spacing: 8, runSpacing: 8)` 的 8 与每个按钮的 `width: 136` 都硬写在调用处',
      fix: '间距取 `AppSpacing.related`；定宽集中成一个常量（这里已收成 `_shortcutWidth`）',
    ),
    (
      where: '导入资源的 tip 条',
      problem:
          '手写的 `Container(lowBackgroundOnCard, radius 4, labelMedium)`，而项目里早有 `buildWarningBar`',
      fix: '同一用途收进 `buildWarningBar`，别保留两套实现',
    ),
    (
      where: '各区块里的说明文字',
      problem: '直接用 `theme.textTheme.labelMedium` 当说明（label 一族本该给标签 / 徽标）',
      fix: '按 A 类改法：说明用 `bodySmall` + `itemSecondary`',
    ),
    (
      where: '模组文件夹按钮（`_ModsFolderButton`）',
      problem: '与 `IconTextButton` 并排但行为不同（先解析路径再打开），从名字与外观上看不出来',
      fix: '组件说明里写清它的用途与参数；或收成一个更通用的「按类型打开目录」组件',
    ),
  ];

  // ── 交互 ──

  /// 提示条：被关掉之后不再返回组件，这里补一句说明免得看着像丢了东西
  List<Widget> _buildTipBar() {
    final bar = buildWarningBar(
      context,
      'design_example_about_tip',
      'tip：可以把资源或游戏本体拖进 Copper 直接导入',
      onTap: () => setState(() {}),
    );
    if (bar != null) return [bar];
    return [
      Text('这条提示已经被关掉（关闭状态记在 customSettings 里，不再显示）', style: _hintStyle()),
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
        _buildVersionInfoModule(),
        _buildShortcutModule(),
        _buildTipModule(),
        _buildProblemsModule(),
      ],
    );
  }

  /// 说明这一页的来由
  Widget _buildIntroModule() {
    return ContentPanelModule(
      title: '这是什么',
      child: Text(
        '素材是真实页面 `ui/pages/overview/version_setting.dart` 的「关于」分项 —— '
        '原实现还在原位跑，这一页只做两件事：按规范重做一版、把它暴露出来的问题逐条点名',
        style: _hintStyle(),
      ),
    );
  }

  // ════════ 1 版本信息（重做） ════════

  Widget _buildVersionInfoModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    Widget infoRow(String label, String value) => SettingBarRow(
      title: label,
      control: Align(
        alignment: Alignment.centerRight,
        child: Text(value, style: theme.textTheme.bodyMedium),
      ),
    );

    return ContentPanelModule(
      title: '1 版本信息（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          HintLayer(
            hint: '点击重命名该版本',
            child: ReboundListTile(
              borderRadius: AppRadius.controlShape,
              padding: const EdgeInsets.all(AppSpacing.tight),
              leading: Icon(
                Icons.memory,
                size: AppIconSize.hero,
                color: colors.interactive,
              ),
              title: const Text('v160.5'),
              subtitle: const Text('桌面版 · 已隔离数据目录'),
              onTap: () {},
            ),
          ),
          infoRow('添加时间', '2026-10-05 13:54'),
          infoRow('模组加载器', 'Copper Loader 0.2.0'),
          Row(
            spacing: AppSpacing.related,
            children: [
              IconTextButton(
                icon: Icons.star_outline,
                content: '未收藏',
                weight: ActionWeight.tertiary,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.build_circle,
                content: '生成启动脚本',
                weight: ActionWeight.tertiary,
                onTap: () {},
              ),
              const Spacer(),
              IconTextButton(
                icon: Icons.delete,
                content: '删除版本',
                weight: ActionWeight.danger,
                onTap: () {},
              ),
            ],
          ),
          Text(
            '改了三处：信息行从页面内联函数换成 `SettingBarRow`；'
            '瓦片的圆角与内衬取令牌；动作按重量排开，「删除版本」用 danger 推到最右',
            style: _hintStyle(),
          ),
        ],
      ),
    );
  }

  // ════════ 2 快捷方式（重做） ════════

  Widget _buildShortcutModule() {
    return ContentPanelModule(
      title: '2 快捷方式（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text('快速打开对应文件夹', style: _hintStyle()),
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              for (final item in _shortcuts)
                IconTextButton(
                  width: _shortcutWidth,
                  icon: item.icon,
                  content: item.label,
                  weight: ActionWeight.secondary,
                  onTap: () {},
                ),
            ],
          ),
          Text(
            '间距从硬写的 8 换成 `AppSpacing.related`，定宽收成 `_shortcutWidth` 一处；'
            '按钮自身的重量统一为 secondary —— 这一块是并列入口，没有主次',
            style: _hintStyle(),
          ),
          Text(
            '说明文字用 bodySmall + itemSecondary，而不是拿 labelMedium 当正文',
            style: _hintStyle(),
          ),
        ],
      ),
    );
  }

  // ════════ 3 提示条（重做） ════════

  Widget _buildTipModule() {
    return ContentPanelModule(
      title: '3 提示条（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.group,
        children: [
          ..._buildTipBar(),
          Text(
            '同一件事在 version_setting 里是手写的 Container，而项目里早有 `buildWarningBar` —— '
            '这种「一个用途两套实现」正是要用规范收掉的东西；点右边的叉可以看关闭后的样子',
            style: _hintStyle(),
          ),
        ],
      ),
    );
  }

  // ════════ 4 要规范的地方 ════════

  Widget _buildProblemsModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '4 要规范的地方（组件库的输入）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          Text(
            '每一条都是「用途不明确」或「参数神出鬼没」的具体样子，位置 / 现象 / 建议三列',
            style: _hintStyle(),
          ),
          for (final item in _problems)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.tight,
              children: [
                Text(item.where, style: theme.textTheme.titleSmall),
                Text(item.problem, style: theme.textTheme.bodySmall),
                Text(
                  '→ ${item.fix}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.of(context).interactive,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 页内说明文字的统一写法（A 类：说明用 bodySmall + itemSecondary）
  TextStyle? _hintStyle() => Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: AppColors.of(context).itemSecondary);
}
