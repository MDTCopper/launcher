import 'package:copper_launcher/ui/pages/design/template_menu.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_state.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 一条模组占位数据（接入后换成 `ModOfficialListEntry`）
class _ModItem {
  const _ModItem({
    required this.name,
    required this.repo,
    required this.desc,
    required this.java,
    required this.beta,
    required this.downloads,
    required this.stars,
    required this.updated,
    required this.installed,
    required this.range,
    required this.compatible,
  });

  final String name;
  final String repo;
  final String desc;
  final bool java;
  final bool beta;
  final String downloads;
  final String stars;
  final String updated;

  /// 本地是否已安装（只在下载操作旁做标识，不做按钮态）
  final bool installed;

  /// 支持的游戏版本范围，如 `v146-v153`（由 minGameVersion 换算）
  final String range;

  /// 这份记录是否支持当前选中版本
  final bool compatible;
}

/// 浏览页的三种排布
enum _ViewMode { compact, list, grid }

/// 模组浏览页（设计层版本，App 内可打开：`/template_mod_view`，仅 debug 可见）
///
/// 2026-11-07 第三版（用户反馈）：
/// - 去掉「已安装」这类状态（浏览页不表示本地状态）
/// - 统计改成**等宽四列**（`Expanded`，随宽度拉伸），跨行对齐
/// - 新增**紧凑视图**；窄屏只给「列表 / 网格」两种，其中列表就用紧凑行
/// - 网格卡片补回徽标（Java / Beta）
class TemplateModViewScreen extends StatefulWidget {
  const TemplateModViewScreen({super.key});

  @override
  State<TemplateModViewScreen> createState() => _TemplateModViewScreenState();
}

class _TemplateModViewScreenState extends State<TemplateModViewScreen> {
  final _search = TextEditingController();

  int _type = 0;
  int _gameVersion = 0;
  int _sort = 0;

  _ViewMode _view = _ViewMode.list;
  int _page = 1;

  static const _mods = [
    _ModItem(
      name: 'New Horizon',
      repo: 'Yuria-Shikibe/NewHorizonMod',
      desc: '把 Mindustry 的玩法推到极限：新的科技树、单位与建筑，配套的星球与战役。',
      java: true,
      beta: true,
      downloads: '126.9M',
      stars: '1.2k',
      updated: '3 天前',
      installed: true,
      range: 'v146-v153',
      compatible: true,
    ),
    _ModItem(
      name: 'Exogenesis',
      repo: 'Team-Exogenesis/Exogenesis',
      desc: '一套以「终极科技」为核心的超大型内容模组，新增大量单位、建筑与星球。',
      java: true,
      beta: false,
      downloads: '88.4M',
      stars: '2.4k',
      updated: '1 周前',
      installed: false,
      range: 'v146-v153',
      compatible: true,
    ),
    _ModItem(
      name: 'Mindustry Extended',
      repo: 'Mindustry-Extended/Extended',
      desc: '在原版基础上扩展科技树与单位，玩法更完整，但加载时间也更长。',
      java: true,
      beta: false,
      downloads: '35.2M',
      stars: '640',
      updated: '2 周前',
      installed: false,
      range: 'v146-v152',
      compatible: false,
    ),
    _ModItem(
      name: 'UI Lib',
      repo: 'Copper-Studio/ui-lib',
      desc: '给其它模组用的 UI 组件库：列表、对话框、标签页一应俱全。',
      java: false,
      beta: false,
      downloads: '1.2M',
      stars: '96',
      updated: '1 个月前',
      installed: true,
      range: '不限版本',
      compatible: true,
    ),
    _ModItem(
      name: 'Random Ore',
      repo: 'Some-Author/RandomOre',
      desc: '随机生成矿物分布，让每张地图的资源都不一样。',
      java: false,
      beta: false,
      downloads: '860k',
      stars: '48',
      updated: '2 个月前',
      installed: false,
      range: 'v153 起',
      compatible: false,
    ),
    _ModItem(
      name: 'Debug Toolkit',
      repo: 'Some-Author/DebugToolkit',
      desc: '调试工具集：显示实体数量、碰撞箱与性能面板。',
      java: true,
      beta: false,
      downloads: '12.4k',
      stars: '12',
      updated: '3 个月前',
      installed: false,
      range: '不限版本',
      compatible: true,
    ),
  ];

  static const _types = ['全部', 'Java 模组', 'JS 模组', '其它'];
  static const _gameVersions = ['跟随当前版本', '不限版本', 'v146', 'v153'];
  static const _sorts = ['按下载量', '按星标', '最近更新'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_ModItem> get _visibleMods {
    final keyword = _search.text.trim().toLowerCase();
    final filtered = _mods.where((mod) {
      if (keyword.isNotEmpty) {
        final haystack = '${mod.name} ${mod.repo} ${mod.desc}'.toLowerCase();
        if (!haystack.contains(keyword)) return false;
      }
      return switch (_type) {
        1 => mod.java,
        2 => !mod.java,
        _ => true,
      };
    }).toList();
    switch (_sort) {
      case 1:
        filtered.sort(
          (a, b) => _parseCount(b.stars).compareTo(_parseCount(a.stars)),
        );
      case 2:
        filtered.sort((a, b) => _ageOf(a).compareTo(_ageOf(b)));
      default:
        filtered.sort(
          (a, b) =>
              _parseCount(b.downloads).compareTo(_parseCount(a.downloads)),
        );
    }
    return filtered;
  }

  /// `10.2k` / `1.2M` / `860k` → 数字，用于占位排序
  static double _parseCount(String raw) {
    final text = raw.trim().toLowerCase();
    final multiplier = text.endsWith('m')
        ? 1000000.0
        : text.endsWith('k')
        ? 1000.0
        : 1.0;
    final number = double.tryParse(text.replaceAll(RegExp(r'[km]$'), '')) ?? 0;
    return number * multiplier;
  }

  /// 更新时间 → 天数（占位排序用）
  static double _ageOf(_ModItem mod) {
    final match = RegExp(r'(\d+)').firstMatch(mod.updated);
    final value = double.tryParse(match?.group(1) ?? '0') ?? 0;
    if (mod.updated.contains('周')) return value * 7;
    if (mod.updated.contains('个月')) return value * 30;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);
    // 窄屏判定按**窗口宽**：组件坐在侧栏右边时自身变窄不该触发窄屏（用户 2026-11-07）
    final windowWidth = MediaQuery.sizeOf(context).width;
    final compact = TemplateBreakpoints.isCompactWindow(windowWidth);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mods = _visibleMods;
        // 窄屏只留「列表 / 网格」；列表在窄屏用紧凑行
        final narrowList = compact && _view != _ViewMode.grid;

        return ColoredBox(
          color: skin.page,
          child: TemplateScrollView(
            skin: skin,
            padding: EdgeInsets.all(
              compact ? TemplateSpace.md : TemplateSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.lg,
              children: [
                _buildHead(skin, compact),
                _buildFilters(skin, compact),
                _buildToolbar(skin, compact, mods.length),
                if (mods.isEmpty)
                  TemplateCard(
                    skin: skin,
                    child: TemplateEmptyState(
                      skin: skin,
                      icon: Icons.search_off,
                      title: '没有符合条件的模组',
                      message: '换个关键词，或把类型 / 版本筛选放宽',
                      action: TemplateButton(
                        skin: skin,
                        label: '清空筛选',
                        icon: Icons.filter_alt_off_outlined,
                        kind: TemplateButtonKind.plain,
                        onTap: () => setState(() {
                          _search.clear();
                          _type = 0;
                          _gameVersion = 0;
                          _sort = 0;
                        }),
                      ),
                    ),
                  )
                else if (_view == _ViewMode.grid)
                  _buildGrid(skin, compact, mods)
                else if (_view == _ViewMode.compact || narrowList)
                  _buildCompactList(skin, mods)
                else
                  _buildList(skin, mods),
                if (mods.isNotEmpty)
                  TemplatePager(
                    skin: skin,
                    page: _page,
                    pageCount: 3,
                    firstLast: !compact,
                    onPage: (page) => setState(() => _page = page),
                  ),
                TemplateNotice(
                  skin: skin,
                  tone: TemplateNoticeTone.note,
                  title: '数据从哪来',
                  text:
                      '模组条目来自 Copper 的官方索引与 GitHub；下载量与星标每日更新，'
                      '适配范围由社区维护的清单补充',
                  onClose: () {},
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 标题卡 ──

  Widget _buildHead(TemplateSkin skin, bool compact) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [
        Row(
          spacing: TemplateSpace.sm,
          children: [
            Text(
              '模组',
              style: TemplateType.page.copyWith(
                color: skin.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            TemplateBadge(
              skin: skin,
              label: '官方索引',
              tone: TemplateBadgeTone.accent,
            ),
          ],
        ),
        Text(
          '共 ${_mods.length} 个模组 · 数据来自 Copper 官方索引与 GitHub',
          style: TemplateType.caption.copyWith(color: skin.textTertiary),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.sm,
      children: [
        TemplateButton(
          skin: skin,
          label: '刷新',
          icon: Icons.refresh,
          kind: TemplateButtonKind.plain,
          onTap: () {},
        ),
        TemplateButton(
          skin: skin,
          label: '打开索引仓库',
          icon: Icons.open_in_new,
          kind: TemplateButtonKind.quiet,
          onTap: () {},
        ),
      ],
    );

    final compactActions = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.xs,
      children: [
        TemplateIconButton(
          skin: skin,
          icon: Icons.refresh,
          tooltip: '刷新',
          onTap: () {},
        ),
        TemplateIconButton(
          skin: skin,
          icon: Icons.open_in_new,
          tooltip: '打开索引仓库',
          onTap: () {},
        ),
      ],
    );

    // 头卡按「自身可用宽」决定动作形态：内容宽只有 ~580 时文字按钮太占位
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 640;
        return TemplateCard(
          skin: skin,
          child: Row(
            spacing: TemplateSpace.md,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: skin.accentTint,
                  borderRadius: BorderRadius.circular(TemplateRadius.card),
                ),
                child: Icon(
                  Icons.extension_outlined,
                  size: 26,
                  color: skin.onAccentTint,
                ),
              ),
              Expanded(child: info),
              if (compact || tight) compactActions else actions,
            ],
          ),
        );
      },
    );
  }

  // ── 搜索 + 筛选 ──

  Widget _buildFilters(TemplateSkin skin, bool compact) {
    final dropdownWidth = compact ? 150.0 : 170.0;

    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          TemplateTextField(
            skin: skin,
            controller: _search,
            hint: '搜索模组 / 作者 / 仓库',
            suffix: Padding(
              padding: const EdgeInsets.only(right: TemplateSpace.md),
              child: Icon(Icons.search, size: 18, color: skin.textTertiary),
            ),
          ),
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TemplateDropdown<int>(
                skin: skin,
                width: dropdownWidth,
                value: _type,
                items: [
                  for (var i = 0; i < _types.length; i++)
                    TemplateDropdownItem(value: i, label: _types[i]),
                ],
                onSelected: (value) => setState(() => _type = value),
              ),
              TemplateDropdown<int>(
                skin: skin,
                width: dropdownWidth,
                value: _gameVersion,
                items: [
                  for (var i = 0; i < _gameVersions.length; i++)
                    TemplateDropdownItem(value: i, label: _gameVersions[i]),
                ],
                onSelected: (value) => setState(() => _gameVersion = value),
              ),
              TemplateDropdown<int>(
                skin: skin,
                width: dropdownWidth,
                value: _sort,
                items: [
                  for (var i = 0; i < _sorts.length; i++)
                    TemplateDropdownItem(value: i, label: _sorts[i]),
                ],
                onSelected: (value) => setState(() => _sort = value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 工具条 ──

  Widget _buildToolbar(TemplateSkin skin, bool compact, int count) {
    final chips = <Widget>[
      if (_type != 0)
        TemplateChip(
          skin: skin,
          label: _types[_type],
          selected: true,
          onClose: () => setState(() => _type = 0),
        ),
      if (_gameVersion != 0)
        TemplateChip(
          skin: skin,
          label: _gameVersions[_gameVersion],
          selected: true,
          onClose: () => setState(() => _gameVersion = 0),
        ),
    ];

    final info = Text(
      '找到 $count 个 · 更新于 2 分钟前',
      style: TemplateType.caption.copyWith(color: skin.textTertiary),
    );

    // 宽屏三档（紧凑 / 列表 / 网格），窄屏只给 列表 / 网格
    final modes = compact
        ? const [_ViewMode.list, _ViewMode.grid]
        : const [_ViewMode.compact, _ViewMode.list, _ViewMode.grid];
    final labels = compact ? const ['列表', '网格'] : const ['紧凑', '列表', '网格'];
    final icons = compact
        ? const [Icons.view_list_outlined, Icons.grid_view_outlined]
        : const [
            Icons.density_small_outlined,
            Icons.view_list_outlined,
            Icons.grid_view_outlined,
          ];
    final selected = compact ? (_view == _ViewMode.grid ? 1 : 0) : _view.index;

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.sm,
      children: [
        ...chips,
        SizedBox(
          width: compact ? 132 : 216,
          child: TemplateSegment(
            skin: skin,
            icons: icons,
            options: labels,
            value: selected,
            onTap: (index) => setState(() => _view = modes[index]),
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          info,
          Align(alignment: Alignment.centerLeft, child: controls),
        ],
      );
    }
    return Row(
      spacing: TemplateSpace.md,
      children: [
        Expanded(child: info),
        controls,
      ],
    );
  }

  // ── 紧凑视图（窄屏的列表也用它）──

  Widget _buildCompactList(TemplateSkin skin, List<_ModItem> mods) {
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.symmetric(vertical: TemplateSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < mods.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(
                  horizontal: TemplateSpace.md,
                ),
                color: skin.border,
              ),
            _buildCompactRow(skin, mods[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactRow(TemplateSkin skin, _ModItem mod) {
    return TemplateRow(
      skin: skin,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.sm,
      ),
      child: Row(
        spacing: TemplateSpace.sm,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: skin.sunken,
              borderRadius: BorderRadius.circular(TemplateRadius.control),
            ),
            child: Icon(
              mod.java ? Icons.coffee_outlined : Icons.extension_outlined,
              size: 15,
              color: skin.textSecondary,
            ),
          ),
          // 名称 / 下载 / 星标 / 适配 四列按比例分，窄屏也塞得下
          Expanded(
            flex: 5,
            child: Row(
              spacing: TemplateSpace.xs,
              children: [
                Flexible(
                  child: Text(
                    mod.name,
                    style: TemplateType.item.copyWith(
                      color: skin.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (mod.beta)
                  TemplateBadge(
                    skin: skin,
                    label: 'Beta',
                    tone: TemplateBadgeTone.danger,
                  ),
              ],
            ),
          ),
          Expanded(flex: 2, child: _stat(skin, Icons.download, mod.downloads)),
          Expanded(flex: 2, child: _stat(skin, Icons.star_outline, mod.stars)),
          // 适配列给 4：范围文字 + 兼容徽标，窄窗口下也塞得下
          Expanded(flex: 4, child: _compat(skin, mod, dense: true)),
          // 已安装：只在下载旁做标识（紧凑行里用小勾，不占按钮位）
          if (mod.installed)
            Icon(Icons.check_circle, size: 14, color: skin.success),
          TemplateIconButton(
            skin: skin,
            icon: Icons.download,
            tooltip: '下载',
            size: 26,
            iconSize: 15,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  // ── 列表视图（宽屏）──

  Widget _buildList(TemplateSkin skin, List<_ModItem> mods) {
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.symmetric(vertical: TemplateSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < mods.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(
                  horizontal: TemplateSpace.md,
                ),
                color: skin.border,
              ),
            _buildModRow(skin, mods[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildModRow(TemplateSkin skin, _ModItem mod) {
    Widget badges() => Wrap(
      spacing: TemplateSpace.xs,
      runSpacing: TemplateSpace.xs,
      children: [
        TemplateBadge(
          skin: skin,
          label: mod.java ? 'Java' : 'JS',
          tone: mod.java ? TemplateBadgeTone.warning : TemplateBadgeTone.note,
        ),
        if (mod.beta)
          TemplateBadge(
            skin: skin,
            label: 'Beta',
            tone: TemplateBadgeTone.danger,
          ),
      ],
    );

    return TemplateRow(
      skin: skin,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.md,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: skin.sunken,
                  borderRadius: BorderRadius.circular(TemplateRadius.card),
                ),
                child: Icon(
                  mod.java ? Icons.coffee_outlined : Icons.extension_outlined,
                  size: 26,
                  color: skin.textSecondary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.xxs,
                  children: [
                    Row(
                      spacing: TemplateSpace.sm,
                      children: [
                        Flexible(
                          child: Text(
                            mod.name,
                            style: TemplateType.item.copyWith(
                              color: skin.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        badges(),
                      ],
                    ),
                    Text(
                      mod.repo,
                      style: TemplateType.micro.copyWith(
                        color: skin.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      mod.desc,
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 操作区：已安装只在下载旁做标识（固定宽槽，保证各行按钮对齐），
              // 「更多」放在下载右边（用户 2026-11-07）
              Row(
                spacing: TemplateSpace.sm,
                children: [
                  SizedBox(
                    width: 56,
                    child: mod.installed
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: TemplateBadge(
                              skin: skin,
                              label: '已安装',
                              tone: TemplateBadgeTone.success,
                            ),
                          )
                        : null,
                  ),
                  TemplateButton(
                    skin: skin,
                    label: '下载',
                    icon: Icons.download,
                    kind: TemplateButtonKind.plain,
                    onTap: () {},
                  ),
                  TemplateIconButton(
                    skin: skin,
                    icon: Icons.more_horiz,
                    tooltip: '更多操作',
                    size: 28,
                    iconSize: 16,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          // 统计：按权重分宽（适配列更宽），随卡片宽度拉伸，跨行对齐
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _stat(skin, Icons.download, mod.downloads),
              ),
              Expanded(
                flex: 2,
                child: _stat(skin, Icons.star_outline, mod.stars),
              ),
              Expanded(flex: 4, child: _compat(skin, mod)),
              Expanded(
                flex: 2,
                child: _stat(skin, Icons.schedule, '更新于 ${mod.updated}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(TemplateSkin skin, IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.xs,
      children: [
        Icon(icon, size: 14, color: skin.textTertiary),
        Flexible(
          child: Text(
            value,
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 适配范围 + 兼容 / 不兼容；紧凑视图里只留徽标与范围文字
  Widget _compat(TemplateSkin skin, _ModItem mod, {bool dense = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.xs,
      children: [
        Icon(
          mod.compatible ? Icons.check_circle_outline : Icons.info_outline,
          size: 14,
          color: skin.textTertiary,
        ),
        Flexible(
          child: Text(
            dense ? mod.range : '适配 ${mod.range}',
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TemplateBadge(
          skin: skin,
          label: mod.compatible ? '兼容' : '不兼容',
          tone: mod.compatible
              ? TemplateBadgeTone.success
              : TemplateBadgeTone.warning,
        ),
      ],
    );
  }

  // ── 网格视图 ──

  Widget _buildGrid(TemplateSkin skin, bool compact, List<_ModItem> mods) {
    const gap = TemplateSpace.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = compact ? 1 : 2;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final mod in mods)
              SizedBox(width: itemWidth, child: _buildGridCard(skin, mod)),
          ],
        );
      },
    );
  }

  Widget _buildGridCard(TemplateSkin skin, _ModItem mod) {
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.md,
            children: [
              // logo 高度盖住「标题 + 仓库 + 标签」再高一点点（用户 2026-11-07）
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: skin.sunken,
                  borderRadius: BorderRadius.circular(TemplateRadius.card),
                ),
                child: Icon(
                  mod.java ? Icons.coffee_outlined : Icons.extension_outlined,
                  size: 34,
                  color: skin.textSecondary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.xs,
                  children: [
                    Text(
                      mod.name,
                      style: TemplateType.item.copyWith(
                        color: skin.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      mod.repo,
                      style: TemplateType.micro.copyWith(
                        color: skin.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 徽标补回来（用户：网格视图没了标签）
                    Wrap(
                      spacing: TemplateSpace.xs,
                      runSpacing: TemplateSpace.xs,
                      children: [
                        TemplateBadge(
                          skin: skin,
                          label: mod.java ? 'Java' : 'JS',
                          tone: mod.java
                              ? TemplateBadgeTone.warning
                              : TemplateBadgeTone.note,
                        ),
                        if (mod.beta)
                          TemplateBadge(
                            skin: skin,
                            label: 'Beta',
                            tone: TemplateBadgeTone.danger,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Text(
            mod.desc,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              Expanded(child: _stat(skin, Icons.download, mod.downloads)),
              Expanded(child: _stat(skin, Icons.star_outline, mod.stars)),
              // 适配列需要更多宽度：范围文字 + 兼容徽标
              Expanded(flex: 2, child: _compat(skin, mod, dense: true)),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '更新于 ${mod.updated}',
                  style: TemplateType.micro.copyWith(color: skin.textTertiary),
                ),
              ),
              // 已安装只在下载旁做标识
              if (mod.installed) ...[
                TemplateBadge(
                  skin: skin,
                  label: '已安装',
                  tone: TemplateBadgeTone.success,
                ),
                const SizedBox(width: TemplateSpace.sm),
              ],
              TemplateButton(
                skin: skin,
                label: '下载',
                icon: Icons.download,
                kind: TemplateButtonKind.plain,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}
