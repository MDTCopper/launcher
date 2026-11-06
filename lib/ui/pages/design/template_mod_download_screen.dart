import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_entry.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_state.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 模组下载页（设计层版本，App 内可打开：`/template_mod_download`，仅 debug 可见）
///
/// 布局是 2026-11-06 跟用户一起定的那一版：
/// - 头卡：左侧图标 + 图标下面的「下载 / 更多」，右侧名称、徽标、作者信息、描述
/// - 下面一级分类切换：版本列表 / 模组介绍 / Readme
/// - 版本列表：过滤 + 表格式列 + 翻页；获取受 GitHub API 限制，先按页读
///
/// 数据还没接：先用一组占位数据把版式定下来，接入时替换 `_versions` 等即可
class TemplateModDownloadScreen extends StatefulWidget {
  const TemplateModDownloadScreen({super.key});

  @override
  State<TemplateModDownloadScreen> createState() =>
      _TemplateModDownloadScreenState();
}

class _TemplateModDownloadScreenState extends State<TemplateModDownloadScreen> {
  int _tab = 0;
  int _filter = 0;
  int _page = 1;

  /// 占位版本数据：`(版本, 日期, 体积, 下载量, 是否兼容当前版本)`
  static const _versions = [
    ('v2.1.4', '2026-11-04', '12.4 MB', '10.2k', true),
    ('v2.1.3', '2026-10-21', '12.1 MB', '1499', true),
    ('v2.1.0', '2026-09-30', '11.8 MB', '25.4k', false),
  ];

  static const _desc =
      '把 Mindustry 的玩法推到极限：新的科技树、单位与建筑，配套的星球与战役。'
      '需要 Copper Loader 0.2.1 以上；与部分整合包的核心模组冲突。'
      '目前模组处于beta阶段，部分功能可能不稳定，战役流程也在持续更新中。敬请期待后续版本。';

  // 窄屏阈值走 `TemplateBreakpoints`（标准设计宽度 = 最小窗口 760）：不再各写一个数

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = TemplateBreakpoints.isCompact(constraints.maxWidth);
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
                _buildHead(skin, compact: compact),
                TemplateTabBar(
                  skin: skin,
                  tabs: const ['版本列表', '模组介绍', 'Readme'],
                  value: _tab,
                  onTap: (index) => setState(() => _tab = index),
                  trailing: _tab == 0
                      ? Text(
                          '共 ${_versions.length} 个版本',
                          style: TemplateType.caption.copyWith(
                            color: skin.textTertiary,
                          ),
                        )
                      : null,
                ),
                switch (_tab) {
                  1 => _buildIntro(skin),
                  2 => _buildReadme(skin),
                  _ => _buildVersions(skin, compact: compact),
                },
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 头卡 ──

  Widget _buildHead(TemplateSkin skin, {required bool compact}) {
    final logoSize = compact ? 64.0 : 96.0;

    Widget logo() => Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        color: skin.accentTint,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
      ),
      child: Icon(
        Icons.extension_outlined,
        size: logoSize * 0.36,
        color: skin.onAccentTint,
      ),
    );

    Widget titleRow() => Row(
      spacing: TemplateSpace.sm,
      children: [
        Flexible(
          child: Text(
            'New Horizon',
            style: TemplateType.page.copyWith(
              color: skin.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!compact) ...[
          const Spacer(),
          Icon(Icons.download, size: 18, color: skin.textSecondary),
          Text(
            '126.9M',
            style: TemplateType.caption.copyWith(color: skin.textSecondary),
          ),
          const SizedBox(width: TemplateSpace.sm),
          Icon(Icons.star, size: 18, color: skin.textSecondary),
          Text(
            '1.2k',
            style: TemplateType.caption.copyWith(color: skin.textSecondary),
          ),
        ],
      ],
    );

    Widget badges() => Wrap(
      spacing: TemplateSpace.sm,
      runSpacing: TemplateSpace.xs,
      children: [
        TemplateBadge(
          skin: skin,
          icon: Icons.coffee_outlined,
          label: 'Java 模组',
          tone: TemplateBadgeTone.danger,
        ),
        TemplateBadge(
          skin: skin,
          label: 'Beta',
          tone: TemplateBadgeTone.warning,
        ),
        TemplateBadge(
          skin: skin,
          label: '社区维护标签',
          tone: TemplateBadgeTone.neutral,
        ),
      ],
    );

    Widget author() => Text(
      'Yuria-Shikibe / NewHorizonMod',
      style: TemplateType.caption.copyWith(color: skin.textSecondary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    // 主行动：直接下最新「兼容当前选中版本」的那个版本；「更多」走项目现有菜单
    Widget download() => TemplateButton(
      skin: skin,
      label: '下载',
      icon: Icons.download,
      kind: TemplateButtonKind.solid,
      expanded: compact,
      onTap: _downloadLatestCompatible,
    );

    Widget more() => Builder(
      builder: (moreContext) => TemplateButton(
        skin: skin,
        label: '更多',
        icon: Icons.more_horiz,
        kind: TemplateButtonKind.quiet,
        onTap: () => _openMore(moreContext),
      ),
    );

    if (compact) {
      // 窄屏：图标 + 标题一行，描述单独一行，按钮在底部通栏 —— 抽屉 / 竖屏里也放得下
      return TemplateCard(
        skin: skin,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TemplateSpace.md,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                logo(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: TemplateSpace.xs,
                    children: [titleRow(), author(), badges()],
                  ),
                ),
              ],
            ),
            Text(
              _desc,
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              spacing: TemplateSpace.sm,
              children: [
                Expanded(child: download()),
                more(),
              ],
            ),
          ],
        ),
      );
    }

    return TemplateCard(
      skin: skin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          logo(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.xs,
              children: [
                titleRow(),
                author(),
                Text(
                  _desc,
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                  ),
                  // 正常态（760 基准）给两行：只给一行会在最小窗口里截成「需要 Co…」
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(),
                badges(),
              ],
            ),
          ),
          Column(
            spacing: TemplateSpace.sm,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [download(), more()],
          ),
        ],
      ),
    );
  }

  /// 主行动：按当前选中版本，挑「支持当前版本的最新 release」下载
  ///
  /// 具体实现等接入真实数据后补：需要先知道当前版本号，再在已加载的版本里
  /// 从新到旧找第一个兼容项；没加载到的分页要按需往后读（GitHub API 限制）
  void _downloadLatestCompatible() {
    // TODO(设计层): 接入 ModOfficialListEntry / ModRelease 后实现
  }

  /// 更多操作：用**当前项目里的** `ContextMenu`（样式跟现有右键菜单一致）
  void _openMore(BuildContext buttonContext) {
    ContextMenu.showBelow(
      context: buttonContext,
      entries: [
        ContextMenuAction(
          icon: Icons.info_outline,
          label: '模组详情',
          onSelected: () {},
        ),
        ContextMenuAction(
          icon: Icons.description_outlined,
          label: 'README',
          onSelected: () => setState(() => _tab = 2),
        ),
        ContextMenuAction(
          icon: Icons.folder_open,
          label: '源码仓库',
          onSelected: () {},
        ),
        ContextMenuAction(
          icon: Icons.person_outline,
          label: '作者主页',
          onSelected: () {},
        ),
      ],
    );
  }

  // ── 版本列表 ──

  Widget _buildVersions(TemplateSkin skin, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.md,
      children: [
        TemplateCard(
          skin: skin,
          padding: const EdgeInsets.symmetric(
            vertical: TemplateSpace.sm,
            horizontal: TemplateSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.xs,
            children: [
              // 过滤 + 排序入口
              TemplateRow(
                skin: skin,
                padding: const EdgeInsets.symmetric(
                  horizontal: TemplateSpace.xs,
                  vertical: TemplateSpace.xs,
                ),
                child: Row(
                  spacing: TemplateSpace.md,
                  children: [
                    SizedBox(
                      width: compact ? 168 : 180,
                      child: TemplateSegment(
                        skin: skin,
                        options: const ['全部', '仅兼容'],
                        value: _filter,
                        onTap: (index) => setState(() => _filter = index),
                      ),
                    ),
                    Expanded(child: SizedBox()),

                    TemplateButton(
                      skin: skin,
                      label: '刷新',
                      icon: Icons.refresh,
                      kind: TemplateButtonKind.quiet,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              // 窄屏不摆表头，列名落到每行第二排
              if (!compact) _buildColumnHeader(skin),
              for (var i = 0; i < _versions.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: TemplateSpace.xs,
                    ),
                    color: skin.border,
                  ),
                _buildVersionRow(skin, _versions[i], compact: compact),
              ],
              _buildPager(skin, compact: compact),
            ],
          ),
        ),
        TemplateNotice(
          skin: skin,
          tone: TemplateNoticeTone.warning,
          title: '版本读取受限',
          text:
              'GitHub 匿名访问有 60 次/小时 的限制，版本列表按页读取；'
              '打开过的模组会缓存，也可以在设置里填 GitHub token',
          onClose: () {},
        ),
      ],
    );
  }

  Widget _buildColumnHeader(TemplateSkin skin) {
    Widget cell(double width, String label, IconData icon) => SizedBox(
      width: width,
      child: Row(
        spacing: TemplateSpace.xs,
        children: [
          Icon(icon, size: 16, color: skin.textTertiary),
          Text(
            label,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.xs,
      ),
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          cell(90, '版本', Icons.info_outline),
          cell(110, '发布时间', Icons.calendar_today),
          cell(150, '支持版本', Icons.check_circle),
          cell(80, '体积', Icons.storage),
          cell(70, '下载量', Icons.download),
        ],
      ),
    );
  }

  Widget _buildVersionRow(
    TemplateSkin skin,
    (String, String, String, String, bool) version, {
    required bool compact,
  }) {
    final (tag, date, size, downloads, compatible) = version;

    final compatBadge = TemplateBadge(
      skin: skin,
      label: compatible ? '兼容' : '不兼容',
      tone: compatible ? .success : .warning,
    );

    if (compact) {
      // 窄屏：第一排 版本 + 兼容徽标 + 日期，第二排 支持范围 / 体积 / 下载量
      return TemplateRow(
        skin: skin,
        padding: const EdgeInsets.symmetric(
          horizontal: TemplateSpace.md,
          vertical: TemplateSpace.sm,
        ),
        onTap: () {},
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TemplateSpace.xs,
          children: [
            Row(
              spacing: TemplateSpace.sm,
              children: [
                Text(
                  tag,
                  style: TemplateType.item.copyWith(
                    color: skin.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                compatBadge,
                const Spacer(),
                Text(
                  date,
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                  ),
                ),
              ],
            ),
            Text(
              '支持 v146-v153 · $size · 下载 $downloads',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return TemplateRow(
      skin: skin,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.sm,
      ),
      onTap: () {},
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              tag,
              style: TemplateType.item.copyWith(
                color: skin.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              date,
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          SizedBox(
            width: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.sm,
              children: [
                Text(
                  'v146-v153', //支持版本范围，由mingameversion翻译
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                  ),
                ),
                compatBadge,
              ],
            ),
          ),

          SizedBox(
            width: 80,
            child: Text(
              size,
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              downloads,
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: SizedBox()),
          ),
        ],
      ),
    );
  }

  Widget _buildPager(TemplateSkin skin, {required bool compact}) {
    final info = Text(
      '第 $_page / 3 页',
      style: TemplateType.caption.copyWith(color: skin.textTertiary),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TemplateSpace.sm,
      children: [
        TemplateButton(
          skin: skin,
          label: '上一页',
          icon: Icons.chevron_left,
          kind: TemplateButtonKind.quiet,
          enabled: _page > 1,
          onTap: () => setState(() => _page--),
        ),
        TemplateButton(
          skin: skin,
          label: '下一页',
          icon: Icons.chevron_right,
          kind: TemplateButtonKind.quiet,
          onTap: () => setState(() => _page = _page < 3 ? _page + 1 : 3),
        ),
      ],
    );
    return TemplateRow(
      skin: skin,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.xs,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.xs,
              children: [
                info,
                Align(alignment: Alignment.centerRight, child: buttons),
              ],
            )
          : Row(
              children: [
                Expanded(child: info),
                buttons,
              ],
            ),
    );
  }

  // ── 模组介绍（社区维护，大部分模组没有）──

  Widget _buildIntro(TemplateSkin skin) {
    return TemplateCard(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          Text(
            '模组介绍由社区维护，作者或社区成员提交后会显示在这里',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          TemplateEmptyState(
            skin: skin,
            icon: Icons.menu_book_outlined,
            title: '这个模组还没有介绍',
            message: '可以先看右侧 README，或到社区仓库补充一份介绍',
            action: TemplateButton(
              skin: skin,
              label: '去社区补充',
              icon: Icons.edit_outlined,
              kind: TemplateButtonKind.plain,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  // ── Readme ──

  Widget _buildReadme(TemplateSkin skin) {
    Widget heading(String text) => Text(
      text,
      style: TemplateType.item.copyWith(
        color: skin.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    Widget paragraph(String text) => Text(
      text,
      style: TemplateType.caption.copyWith(color: skin.textSecondary),
    );

    return TemplateCard(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Expanded(
                child: Text(
                  'README',
                  style: TemplateType.page.copyWith(color: skin.textPrimary),
                ),
              ),
              TemplateButton(
                skin: skin,
                label: '在 GitHub 打开',
                icon: Icons.open_in_new,
                kind: TemplateButtonKind.quiet,
                onTap: () {},
              ),
            ],
          ),
          heading('New Horizon'),
          paragraph(
            '一个把 Mindustry 往「大后期」推的内容模组：新增科技层级、'
            '单位与建筑，以及配套的星球与战役流程。',
          ),
          paragraph('· 建议搭配 Copper Loader 0.2.1 及以上版本'),
          paragraph('· 与部分整合包的核心模组存在冲突，装之前先看说明'),
          heading('配置片段'),
          Container(
            padding: const EdgeInsets.all(TemplateSpace.md),
            decoration: BoxDecoration(
              color: skin.sunken,
              borderRadius: BorderRadius.circular(TemplateRadius.control),
              border: Border.all(color: skin.border),
            ),
            child: Text(
              '"minGameVersion": "146",\n"java": true,\n"hidden": false',
              style: TemplateType.caption.copyWith(color: skin.textSecondary),
            ),
          ),
          paragraph('更多内容见仓库里的 README.md（这里只展示摘要）。'),
        ],
      ),
    );
  }
}
