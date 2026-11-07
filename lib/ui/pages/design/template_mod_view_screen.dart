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
    required this.installed,
    required this.downloads,
    required this.stars,
    required this.updated,
    required this.range,
    required this.compatible,
  });

  final String name;
  final String repo;
  final String desc;
  final bool java;
  final bool beta;
  final bool installed;
  final String downloads;
  final String stars;
  final String updated;

  /// 支持的游戏版本范围，如 `v146-v153`（由 minGameVersion 换算）
  final String range;

  /// 这份记录是否支持当前选中版本
  final bool compatible;
}

/// 模组浏览页（设计层版本，App 内可打开：`/template_mod_view`，仅 debug 可见）
///
/// 2026-11-07：用户要「做 modviewpage，不一定按照现在的样子」——
/// 现有页面是「搜索 + 类型 / 版本 / 排序 三个下拉 + 长列表」，这里重排成：
/// 标题卡 → 搜索与筛选条（可 Wrap）→ 工具条（计数 / 视图切换）→ 列表或网格 → 翻页
///
/// 2026-11-07 第二版（用户反馈）：下载量 / 星标那排原来跟按钮抢位置、也没对齐 →
/// 单独一行、等距排列；logo 放大到 52；补上「适配范围 + 兼容 / 不兼容」信息
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

  /// 0 = 列表，1 = 网格
  int _view = 0;
  int _page = 1;

  static const _mods = [
    _ModItem(
      name: 'New Horizon',
      repo: 'Yuria-Shikibe/NewHorizonMod',
      desc: '把 Mindustry 的玩法推到极限：新的科技树、单位与建筑，配套的星球与战役。',
      java: true,
      beta: true,
      installed: true,
      downloads: '126.9M',
      stars: '1.2k',
      updated: '3 天前',
      range: 'v146-v153',
      compatible: true,
    ),
    _ModItem(
      name: 'Exogenesis',
      repo: 'Team-Exogenesis/Exogenesis',
      desc: '一套以「终极科技」为核心的超大型内容模组，新增大量单位、建筑与星球。',
      java: true,
      beta: false,
      installed: false,
      downloads: '88.4M',
      stars: '2.4k',
      updated: '1 周前',
      range: 'v146-v153',
      compatible: true,
    ),
    _ModItem(
      name: 'Mindustry Extended',
      repo: 'Mindustry-Extended/Extended',
      desc: '在原版基础上扩展科技树与单位，玩法更完整，但加载时间也更长。',
      java: true,
      beta: false,
      installed: false,
      downloads: '35.2M',
      stars: '640',
      updated: '2 周前',
      range: 'v146-v152',
      compatible: false,
    ),
    _ModItem(
      name: 'UI Lib',
      repo: 'Copper-Studio/ui-lib',
      desc: '给其它模组用的 UI 组件库：列表、对话框、标签页一应俱全。',
      java: false,
      beta: false,
      installed: true,
      downloads: '1.2M',
      stars: '96',
      updated: '1 个月前',
      range: '不限版本',
      compatible: true,
    ),
    _ModItem(
      name: 'Random Ore',
      repo: 'Some-Author/RandomOre',
      desc: '随机生成矿物分布，让每张地图的资源都不一样。',
      java: false,
      beta: false,
      installed: false,
      downloads: '860k',
      stars: '48',
      updated: '2 个月前',
      range: 'v153 起',
      compatible: false,
    ),
    _ModItem(
      name: 'Debug Toolkit',
      repo: 'Some-Author/DebugToolkit',
      desc: '调试工具集：显示实体数量、碰撞箱与性能面板。',
      java: true,
      beta: false,
      installed: false,
      downloads: '12.4k',
      stars: '12',
      updated: '3 个月前',
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = TemplateBreakpoints.isCompact(constraints.maxWidth);
        final mods = _visibleMods;

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
                else if (_view == 0)
                  _buildList(skin, compact, mods)
                else
                  _buildGrid(skin, compact, mods),
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
          if (!compact) actions,
        ],
      ),
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

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.sm,
      children: [
        ...chips,
        SizedBox(
          width: compact ? 132 : 156,
          child: TemplateSegment(
            skin: skin,
            icons: const [Icons.view_list_outlined, Icons.grid_view_outlined],
            options: const ['列表', '网格'],
            value: _view,
            onTap: (index) => setState(() => _view = index),
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

  // ── 列表视图 ──

  Widget _buildList(TemplateSkin skin, bool compact, List<_ModItem> mods) {
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
            _buildModRow(skin, compact, mods[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildModRow(TemplateSkin skin, bool compact, _ModItem mod) {
    Widget logo() => Container(
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
    );

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
        if (mod.installed)
          TemplateBadge(
            skin: skin,
            label: '已安装',
            tone: TemplateBadgeTone.success,
          ),
      ],
    );

    // 统计与适配范围单独一行：等距、对齐，不和右侧按钮抢位置
    Widget meta() => Wrap(
      spacing: TemplateSpace.lg,
      runSpacing: TemplateSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _stat(skin, Icons.download, mod.downloads),
        _stat(skin, Icons.star_outline, mod.stars),
        _compat(skin, mod),
        Text(
          '更新于 ${mod.updated}',
          style: TemplateType.micro.copyWith(color: skin.textTertiary),
        ),
      ],
    );

    Widget download() => TemplateButton(
      skin: skin,
      label: mod.installed ? '已安装' : '下载',
      icon: mod.installed ? Icons.check : Icons.download,
      kind: mod.installed ? TemplateButtonKind.quiet : TemplateButtonKind.plain,
      onTap: () {},
    );

    if (compact) {
      return TemplateRow(
        skin: skin,
        padding: const EdgeInsets.symmetric(
          horizontal: TemplateSpace.md,
          vertical: TemplateSpace.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TemplateSpace.md,
          children: [
            logo(),
            // 窄屏也把描述与统计收进文字列：左边缘与标题对齐，不要「描述从 logo 底下穿过去」
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TemplateSpace.sm,
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
                  badges(),
                  Text(
                    mod.desc,
                    style: TemplateType.caption.copyWith(
                      color: skin.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  meta(),
                  Row(children: [const Spacer(), download()]),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return TemplateRow(
      skin: skin,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: TemplateSpace.md,
        children: [
          logo(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.xs,
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
                  style: TemplateType.micro.copyWith(color: skin.textTertiary),
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
                meta(),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: TemplateSpace.xs,
            children: [
              download(),
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
    );
  }

  Widget _stat(TemplateSkin skin, IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.xs,
      children: [
        Icon(icon, size: 14, color: skin.textTertiary),
        Text(
          value,
          style: TemplateType.micro.copyWith(color: skin.textTertiary),
        ),
      ],
    );
  }

  /// 适配范围 + 兼容 / 不兼容
  Widget _compat(TemplateSkin skin, _ModItem mod) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.xs,
      children: [
        Icon(
          mod.compatible ? Icons.check_circle_outline : Icons.info_outline,
          size: 14,
          color: skin.textTertiary,
        ),
        Text(
          '适配 ${mod.range}',
          style: TemplateType.micro.copyWith(color: skin.textTertiary),
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
            spacing: TemplateSpace.sm,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: skin.sunken,
                  borderRadius: BorderRadius.circular(TemplateRadius.control),
                ),
                child: Icon(
                  mod.java ? Icons.coffee_outlined : Icons.extension_outlined,
                  size: 22,
                  color: skin.textSecondary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.xxs,
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
                  ],
                ),
              ),
              if (mod.installed)
                TemplateBadge(
                  skin: skin,
                  label: '已安装',
                  tone: TemplateBadgeTone.success,
                ),
            ],
          ),
          Text(
            mod.desc,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _stat(skin, Icons.download, mod.downloads),
              _stat(skin, Icons.star_outline, mod.stars),
              _compat(skin, mod),
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
              TemplateButton(
                skin: skin,
                label: mod.installed ? '已安装' : '下载',
                icon: mod.installed ? Icons.check : Icons.download,
                kind: mod.installed
                    ? TemplateButtonKind.quiet
                    : TemplateButtonKind.plain,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}
