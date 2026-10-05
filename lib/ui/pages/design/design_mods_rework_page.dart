import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

const designModsReworkPageRouteKey = '/design/example/mods';

/// 设计规范 · 实例页 · 模组页重做
///
/// 第三个真实素材：`ui/pages/overview/version_setting.dart` 的「模组」分项
/// （工具栏 / 列表 / 批量操作栏）。原实现仍在原位跑，这里按规范重做一版
class DesignModsReworkPage extends StatefulWidget {
  const DesignModsReworkPage({super.key});

  @override
  State<DesignModsReworkPage> createState() => _DesignModsReworkPageState();
}

class _DesignModsReworkPageState extends State<DesignModsReworkPage> {
  // ── 演示状态 ──
  String _category = '全部';
  bool _copperOnly = false;
  final Set<String> _selected = {'NewHorizon'};

  final _searchController = TextEditingController();

  static const _categories = ['全部', '已启用', '已禁用'];
  static const _mods = <({String name, String desc, bool enabled})>[
    (name: 'NewHorizon', desc: 'v2.1.4 · 大型模组 · 已启用', enabled: true),
    (name: 'Endless', desc: 'v1.0.7 · 小游戏 · 已启用', enabled: true),
    (name: 'Pac-Man', desc: 'v0.4.2 · 小游戏 · 已禁用', enabled: false),
  ];

  /// 要规范的地方：位置 / 现象 / 建议
  static const _problems = <({String where, String problem, String fix})>[
    (
      where: '批量操作栏的两个分支',
      problem:
          '宽窗与窄窗两个分支把同样五个 `IconTextButton` **逐字写了两遍**（约 60 行重复），'
          '靠 `LayoutBuilder` 的 470 这个魔法阈值切换',
      fix: '按钮列表构造一次交给 `Wrap`（天然换行），删掉阈值与重复分支',
    ),
    (
      where: '批量操作栏的主次',
      problem:
          '启用 / 禁用 / **删除** / 全选 / 取消选择 五个同重量；同一页的右键菜单里「删除」已经标了 `danger: true`，按钮却没有',
      fix: '删除用 `ActionWeight.danger`、全选与取消选择降为 tertiary、启用 / 禁用保持 secondary',
    ),
    (
      where: '批量操作栏的外壳',
      problem:
          '`Material(elevation: 6)` + 手写 `Container(cardBackground, radius 8, Border.all)` + 外层 `Padding(8)`，'
          '又是一处手写浮层（与「关于」页的 tip 条同类）',
      fix: '等「表面层级」那一节定了 elevation 阶梯与统一描边再收进组件',
    ),
    (
      where: '列表底部的预留高度',
      problem:
          '`SizedBox(height: selectedCount != 0 ? 68.0 : 0.0)` 写死 68 —— 操作栏换行后比 68 高，会盖住最后一项',
      fix: '占位跟着操作栏的实际高度走（量高或把操作栏放进同一滚动流）',
    ),
    (
      where: '瓦片几何与禁用态',
      problem:
          '`padding: symmetric(10, 6)`、`borderRadius: circular(6)` 硬写（6 不在刻度里）；'
          '禁用态手写了三种手法：图标 `ColorFiltered` 灰度矩阵（16 行）、标题 `lineThrough`、`withAlpha(150)`，'
          '而 `ReboundListTile` 自带 `enable` 就会置灰前景',
      fix: '几何取令牌；禁用态先定一套语言（用 `enable: false`），别在页面里各写各的',
    ),
    (
      where: '分类筛选 chips',
      problem:
          '`ActionButton(padding: symmetric(horizontal: 10, vertical: 4))` 覆盖了组件默认的 `all(8)`；'
          '`Wrap(spacing: 8, runSpacing: 4)` 两个方向的间距还不一样',
      fix: '用组件默认内衬（或统一成一处常量）；间距取 `AppSpacing.related` / `AppSpacing.tight`',
    ),
    (
      where: '加载态与空态',
      problem:
          '`Text(\'加载中...\')` 拿文字当加载态；`Text(\'没有匹配的模组\')` 一句话当空态 —— 没说怎么才会有',
      fix: '加载用骨架 / 进度；空态照「试验五」的四件套（正面标题 + 说明 + 一个主行动）',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        _buildToolbarModule(),
        _buildListModule(),
        _buildActionBarModule(),
        _buildProblemsModule(),
      ],
    );
  }

  Widget _buildIntroModule() {
    return ContentPanelModule(
      title: '这是什么',
      child: Text(
        '素材是 `version_setting.dart` 的「模组」分项（工具栏 / 列表 / 批量操作栏）；'
        '原实现仍在原位跑，这一页是重做版 + 问题清单。拖选多选那套交互不在这里重做，只重做外观与组装',
        style: _hintStyle(),
      ),
    );
  }

  // ════════ 1 工具栏（重做） ════════

  Widget _buildToolbarModule() {
    return ContentPanelModule(
      title: '1 工具栏（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.related,
        children: [
          OutlinedTextField(
            label: '搜索模组',
            controller: _searchController,
            onEditingComplete: () => setState(() {}),
          ),
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              for (final category in _categories)
                ActionButton(
                  selected: _category == category,
                  content: Text(category),
                  onTap: () => setState(() => _category = category),
                ),
              ActionButton(
                selected: _copperOnly,
                content: const Text('Copper'),
                onTap: () => setState(() => _copperOnly = !_copperOnly),
              ),
            ],
          ),
          Text(
            'chips 用 `ActionButton` 的默认内衬（原来在调用处覆盖成 10 / 4）；'
            '两个方向的间距都取 `AppSpacing.related`（原来 spacing 8、runSpacing 4）',
            style: _hintStyle(),
          ),
        ],
      ),
    );
  }

  // ════════ 2 列表（重做） ════════

  Widget _buildListModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '2 模组列表（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.tight,
        children: [
          for (final mod in _mods)
            ReboundListTile(
              leading: Icon(Icons.extension_outlined, size: AppIconSize.large),
              title: Text(mod.name),
              subtitle: Text(mod.desc),
              // 禁用态交给组件，不在页面里手写灰度与删除线
              enable: mod.enabled,
              selected: _selected.contains(mod.name),
              onTap: mod.enabled
                  ? () => setState(() {
                      if (!_selected.remove(mod.name)) _selected.add(mod.name);
                    })
                  : null,
            ),
          const SizedBox(height: AppSpacing.group),
          // 空态：正面标题 + 说明 + 一个主行动（原来只有「没有匹配的模组」一句）
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.related,
            children: [
              Text('先换一个筛选条件', style: theme.textTheme.titleMedium),
              Text('当前筛选下没有模组；清掉筛选就能看到已安装的那几个', style: _hintStyle()),
              Align(
                alignment: Alignment.centerLeft,
                child: IconTextButton(
                  icon: Icons.filter_alt_off_outlined,
                  content: '清空筛选',
                  weight: ActionWeight.primary,
                  onTap: () => setState(() {
                    _category = '全部';
                    _copperOnly = false;
                  }),
                ),
              ),
            ],
          ),
          Text(
            '瓦片的几何改由组件与令牌决定（原来硬写 padding 10 / 6、圆角 6）；'
            '禁用态改用 `enable: false`（原来图标走 16 行灰度矩阵、标题加删除线、颜色再乘 alpha）',
            style: _hintStyle(),
          ),
        ],
      ),
    );
  }

  // ════════ 3 批量操作栏（重做） ════════

  Widget _buildActionBarModule() {
    return ContentPanelModule(
      title: '3 批量操作栏（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.group,
        children: [
          Text('已选 ${_selected.length}', style: _hintStyle()),
          // 一份按钮列表 + Wrap 自适应，不再按 470 分两个分支各写一遍
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              IconTextButton(icon: Icons.check, content: '启用', onTap: () {}),
              IconTextButton(icon: Icons.block, content: '禁用', onTap: () {}),
              IconTextButton(
                icon: Icons.delete_outline,
                content: '删除',
                weight: ActionWeight.danger,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.select_all,
                content: '全选',
                weight: ActionWeight.tertiary,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.close,
                content: '取消选择',
                weight: ActionWeight.tertiary,
                onTap: () {},
              ),
            ],
          ),
          Text(
            '五个按钮只写一遍，换行交给 `Wrap`（原来宽窗 / 窄窗两个分支各抄一份、靠 470 判断）；'
            '删除用 danger、全选与取消选择降为 tertiary；'
            '浮层外壳与「底部预留 68」等表面层级那一节定了再收',
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

  /// 页内说明文字（A 类：说明用 bodySmall + itemSecondary）
  TextStyle? _hintStyle() => Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: AppColors.of(context).itemSecondary);
}
