import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

const designModsReworkPageRouteKey = '/design/example/mods';

/// 设计规范 · 实例页 · 模组页重做
///
/// 素材是 `ui/pages/overview/version_setting.dart` 的「模组」分项（模组列表 / 已安装 /
/// 底部操作栏）：原实现仍在原位跑，这一页**用参考模版的皮肤把同样的内容重做一遍**，
/// 用来对比同一批内容的观感；拖选多选那套交互不在这里重做
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

  static const _mods =
      <({String name, String desc, bool enabled, bool copper})>[
        (
          name: 'NewHorizon',
          desc: 'v2.1.4 · 大型模组 · 12.8 MB',
          enabled: true,
          copper: false,
        ),
        (
          name: 'Endless',
          desc: 'v1.0.7 · 小游戏 · 0.4 MB',
          enabled: true,
          copper: false,
        ),
        (
          name: 'Pac-Man',
          desc: 'v0.4.2 · 小游戏 · 0.3 MB',
          enabled: false,
          copper: false,
        ),
      ];

  List<({String name, String desc, bool enabled, bool copper})> get _visible {
    return switch (_filter) {
      1 => [
        for (final mod in _mods)
          if (mod.enabled) mod,
      ],
      2 => [
        for (final mod in _mods)
          if (!mod.enabled) mod,
      ],
      3 => [
        for (final mod in _mods)
          if (mod.copper) mod,
      ],
      _ => _mods,
    };
  }

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
    final visible = _visible;

    return ListContentPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.xxl,
        vertical: TemplateSpace.xl,
      ),
      items: [
        _buildHueSwitch(skin),
        _buildToolbar(skin),
        _buildModList(skin, visible),
        if (_selected.isNotEmpty) _buildActionBar(skin),
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

  // ════════ 模组列表（搜索 + 分类） ════════

  Widget _buildToolbar(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '模组列表（${_mods.length}）',
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

  // ════════ 已安装的模组（筛选不到时就是它自己的空态） ════════

  Widget _buildModList(
    TemplateSkin skin,
    List<({String name, String desc, bool enabled, bool copper})> visible,
  ) {
    return TemplateSection(
      skin: skin,
      title: '已安装（${visible.length}）',
      child: visible.isEmpty
          ? _buildEmptyState(skin)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: [
                for (final mod in visible)
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

  /// 空态：标题写正面、说清下一步、给一个主行动
  Widget _buildEmptyState(TemplateSkin skin) {
    return Padding(
      padding: const EdgeInsets.all(TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Icon(Icons.inbox_outlined, size: 28, color: skin.textTertiary),
          Text(
            '没有匹配的模组',
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

  // ════════ 底部操作栏（选中 ≥1 才出现） ════════

  Widget _buildActionBar(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '已选 ${_selected.length}',
      child: Wrap(
        spacing: TemplateSpace.md,
        runSpacing: TemplateSpace.md,
        children: [
          TemplateButton(
            skin: skin,
            label: '启用',
            icon: Icons.check,
            // 批量操作里最常按的那个当实心主行动，其余中性 / 安静档
            // （用户 2026-10-05「你没有演示主行动的效果」）
            kind: TemplateButtonKind.solid,
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
}
