import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

const designModsReworkPageRouteKey = '/design/example/mods';

/// 设计规范 · 实例页 · 模组页重做
///
/// 素材是 `ui/pages/overview/version_setting.dart` 的「模组」分项（工具栏 / 列表 /
/// 批量操作栏）：原实现仍在原位跑，这一页**用参考模版的皮肤重做**外观与组装；
/// 拖选多选那套交互不在这里重做
class DesignModsReworkPage extends StatefulWidget {
  const DesignModsReworkPage({super.key});

  @override
  State<DesignModsReworkPage> createState() => _DesignModsReworkPageState();
}

class _DesignModsReworkPageState extends State<DesignModsReworkPage> {
  double _hue = TemplateHues.copper;

  // ── 演示状态 ──
  int _filter = 0;
  final Set<String> _selected = {'NewHorizon'};
  final _searchController = TextEditingController();

  static const _filters = ['全部', '已启用', '已禁用', 'Copper'];

  static const _mods = <({String name, String desc, bool enabled})>[
    (name: 'NewHorizon', desc: 'v2.1.4 · 大型模组 · 12.8 MB', enabled: true),
    (name: 'Endless', desc: 'v1.0.7 · 小游戏 · 0.4 MB', enabled: true),
    (name: 'Pac-Man', desc: 'v0.4.2 · 小游戏 · 0.3 MB', enabled: false),
  ];

  /// 要规范的地方：位置 / 现象 / 建议
  static const _problems = <({String where, String problem, String fix})>[
    (
      where: '批量操作栏的两个分支',
      problem:
          '宽窗与窄窗两个分支把同样五个按钮逐字写了两遍（约 60 行重复），靠 `LayoutBuilder` 的 470 这个魔法阈值切换',
      fix: '按钮列表构造一次交给 `Wrap`（天然换行），删掉阈值与重复分支（重做版已这么做）',
    ),
    (
      where: '批量操作栏的主次',
      problem: '启用 / 禁用 / 删除 / 全选 / 取消选择 五个同重量；同页右键菜单里「删除」已标 danger，按钮却没有',
      fix: '删除用 `TemplateButtonKind.danger`、全选与取消选择降为安静档（重做版已改）',
    ),
    (
      where: '批量操作栏的外壳',
      problem:
          '`Material(elevation: 6)` + 手写 `Container(cardBackground, radius 8, Border.all)` + 外层 `Padding(8)`，又是一处手写浮层',
      fix: '让它落在一张卡面上（模版的 `TemplateSection`），浮层那套等「表面层级」定了一起收',
    ),
    (
      where: '列表底部的预留高度',
      problem:
          '`SizedBox(height: selectedCount != 0 ? 68.0 : 0.0)` 写死 68 —— 操作栏换行后比 68 高，会盖住最后一项',
      fix: '占位跟着操作栏的实际高度走（或把操作栏放进同一滚动流）',
    ),
    (
      where: '瓦片几何与禁用态',
      problem:
          '`padding: symmetric(10, 6)`、`borderRadius: circular(6)` 硬写；禁用态手写三种手法（图标 16 行灰度矩阵、标题删除线、颜色乘 alpha），而 `ReboundListTile` 自带 `enable`',
      fix: '几何取令牌；禁用态先定一套语言（`enable: false`），别在页面里各写各的',
    ),
    (
      where: '分类筛选 chips',
      problem:
          '`ActionButton(padding: symmetric(10, 4))` 覆盖组件默认内衬；`Wrap(spacing: 8, runSpacing: 4)` 两个方向还不一样',
      fix: '用默认内衬或统一成一处常量；间距取令牌（重做版用 `TemplateSegment`）',
    ),
    (
      where: '加载态与空态',
      problem: '拿一句「加载中…」当加载态；拿「没有匹配的模组」一句话当空态，没说怎么才会有',
      fix: '加载用骨架 / 进度；空态照四件套来（重做版已改）',
    ),
  ];

  TemplateSkin get _skin => TemplateSkin.of(
    hue: _hue,
    dark: Theme.of(context).brightness == Brightness.dark,
  );

  @override
  void dispose() {
    _searchController.dispose();
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
        _buildIntro(skin),
        _buildToolbar(skin),
        _buildModList(skin),
        _buildEmptyState(skin),
        _buildActionBar(skin),
        _buildProblems(skin),
      ],
    );
  }

  Widget _buildHueSwitch(TemplateSkin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.xl),
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          Text(
            '主题色相（色温）',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          SizedBox(
            width: 320,
            child: TemplateSegment(
              skin: skin,
              options: [for (final item in TemplateHues.named) item.name],
              value: TemplateHues.named.indexWhere((item) => item.hue == _hue),
              onTap: (index) =>
                  setState(() => _hue = TemplateHues.named[index].hue),
            ),
          ),
          Text(
            '这一页用的是参考模版的皮肤，不是 AppColors',
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '这是什么',
      child: Text(
        '素材是 `version_setting.dart` 的「模组」分项，用参考模版的皮肤重做；'
        '拖选多选那套交互不在这里重做，只重做外观与组装',
        style: TemplateType.caption.copyWith(color: skin.textSecondary),
      ),
    );
  }

  // ════════ 1 工具栏 ════════

  Widget _buildToolbar(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '1 工具栏（${_mods.length} 个）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.lg,
        children: [
          // 搜索框：控件边界那道描边就是给它用的（1.4.11 要 3:1）
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: TemplateSpace.md,
              vertical: TemplateSpace.md,
            ),
            decoration: BoxDecoration(
              color: skin.sunken,
              borderRadius: BorderRadius.circular(TemplateRadius.control),
              border: Border.all(color: skin.controlBorder),
            ),
            child: Row(
              spacing: TemplateSpace.md,
              children: [
                Icon(Icons.search, size: 18, color: skin.textTertiary),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TemplateType.item.copyWith(color: skin.textPrimary),
                    cursorColor: skin.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '搜索模组',
                      hintStyle: TemplateType.item.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TemplateSegment(
            skin: skin,
            options: _filters,
            value: _filter,
            onTap: (index) => setState(() => _filter = index),
          ),
        ],
      ),
    );
  }

  // ════════ 2 模组列表 ════════

  Widget _buildModList(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '2 已安装的模组',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          for (final mod in _mods)
            TemplateRow(
              skin: skin,
              selected: _selected.contains(mod.name),
              onTap: () => setState(() {
                if (!_selected.remove(mod.name)) _selected.add(mod.name);
              }),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: skin.sunken,
                      borderRadius: BorderRadius.circular(
                        TemplateRadius.control,
                      ),
                    ),
                    child: Icon(
                      Icons.extension_outlined,
                      size: 20,
                      color: skin.textSecondary,
                    ),
                  ),
                  const SizedBox(width: TemplateSpace.md),
                  Expanded(
                    child: TemplateTwoLine(
                      skin: skin,
                      title: mod.name,
                      desc: mod.desc,
                    ),
                  ),
                  if (!mod.enabled) ...[
                    Text(
                      '已禁用',
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                    const SizedBox(width: TemplateSpace.md),
                  ],
                  if (_selected.contains(mod.name))
                    Icon(Icons.check, size: 18, color: skin.accentText),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ════════ 3 空态：标题写正面、说清下一步、给一个主行动 ════════

  Widget _buildEmptyState(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '3 筛选不到时的样子',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Icon(Icons.inbox_outlined, size: 28, color: skin.textTertiary),
          Text(
            '先换一个筛选条件',
            style: TemplateType.section.copyWith(color: skin.textPrimary),
          ),
          SizedBox(
            width: 380,
            child: Text(
              '当前筛选下没有模组；清掉筛选就能看到已安装的那几个',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          Row(
            spacing: TemplateSpace.md,
            children: [
              TemplateButton(
                skin: skin,
                label: '清空筛选',
                icon: Icons.filter_alt_off_outlined,
                kind: TemplateButtonKind.solid,
                onTap: () => setState(() => _filter = 0),
              ),
              TemplateButton(
                skin: skin,
                label: '导入本地模组',
                icon: Icons.folder_open,
                kind: TemplateButtonKind.quiet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════ 4 批量操作栏 ════════

  Widget _buildActionBar(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '4 批量操作栏（选中后才浮出，这里排在同一流里）',
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.md,
      ),
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          Text(
            '已选 ${_selected.length}',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          const Spacer(),
          TemplateButton(
            skin: skin,
            label: '启用',
            icon: Icons.check,
            kind: TemplateButtonKind.plain,
          ),
          TemplateButton(
            skin: skin,
            label: '禁用',
            icon: Icons.block,
            kind: TemplateButtonKind.plain,
          ),
          TemplateButton(
            skin: skin,
            label: '删除',
            icon: Icons.delete_outline,
            kind: TemplateButtonKind.danger,
          ),
          TemplateButton(
            skin: skin,
            label: '全选',
            icon: Icons.select_all,
            kind: TemplateButtonKind.quiet,
          ),
          TemplateButton(
            skin: skin,
            label: '取消选择',
            icon: Icons.close,
            kind: TemplateButtonKind.quiet,
            onTap: () => setState(_selected.clear),
          ),
        ],
      ),
    );
  }

  // ════════ 5 要规范的地方 ════════

  Widget _buildProblems(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '5 要规范的地方（组件库的输入）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          for (final item in _problems)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.xs,
              children: [
                Text(
                  item.where,
                  style: TemplateType.section.copyWith(color: skin.textPrimary),
                ),
                Text(
                  item.problem,
                  style: TemplateType.caption.copyWith(
                    color: skin.textSecondary,
                  ),
                ),
                Text(
                  '→ ${item.fix}',
                  style: TemplateType.caption.copyWith(color: skin.accentText),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
