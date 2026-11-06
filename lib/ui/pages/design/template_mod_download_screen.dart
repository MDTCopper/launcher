import 'package:copper_launcher/ui/pages/design/template_menu.dart';
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
  final _moreKey = GlobalKey();

  int _tab = 0;
  int _filter = 0;
  int _page = 1;

  /// 占位版本数据：`(版本, 日期, 体积, 下载量, 是否兼容当前版本)`
  static const _versions = [
    ('v2.1.4', '2026-11-04', '12.4 MB', '1.2k', true),
    ('v2.1.3', '2026-10-21', '12.1 MB', '980', true),
    ('v2.1.0', '2026-09-30', '11.8 MB', '2.4k', false),
  ];

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);

    return ColoredBox(
      color: skin.page,
      child: TemplateScrollView(
        skin: skin,
        padding: const EdgeInsets.all(TemplateSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TemplateSpace.lg,
          children: [
            _buildHead(skin),
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
              _ => _buildVersions(skin),
            },
          ],
        ),
      ),
    );
  }

  // ── 头卡 ──

  Widget _buildHead(TemplateSkin skin) {
    return TemplateCard(
      skin: skin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          // 左侧：图标 + 图标下面的主行动
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.sm,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: skin.accentTint,
                  borderRadius: BorderRadius.circular(TemplateRadius.card),
                ),
                child: Icon(
                  Icons.extension_outlined,
                  size: 34,
                  color: skin.onAccentTint,
                ),
              ),
              Row(
                spacing: TemplateSpace.xs,
                children: [
                  // 主行动：直接下最新「兼容当前选中版本」的那个版本
                  TemplateButton(
                    skin: skin,
                    label: '下载',
                    icon: Icons.download,
                    kind: TemplateButtonKind.solid,
                    onTap: _downloadLatestCompatible,
                  ),
                  Builder(
                    key: _moreKey,
                    builder: (buttonContext) => TemplateIconButton(
                      skin: skin,
                      icon: Icons.more_horiz,
                      tooltip: '更多操作',
                      onTap: () => _openMore(buttonContext),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.sm,
              children: [
                Row(
                  spacing: TemplateSpace.sm,
                  children: [
                    Text(
                      'New Horizon',
                      style: TemplateType.page.copyWith(
                        color: skin.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TemplateBadge(
                      skin: skin,
                      label: 'Java 模组',
                      tone: TemplateBadgeTone.accent,
                    ),
                    TemplateBadge(skin: skin, label: '已安装'),
                  ],
                ),
                Text(
                  'Yuria-Shikibe / NewHorizonMod · ★ 1.2k · 更新于 3 天前',
                  style: TemplateType.caption.copyWith(
                    color: skin.textSecondary,
                  ),
                ),
                Text(
                  '把 Mindustry 的玩法推到极限：新的科技树、单位与建筑，配套的星球与战役。'
                  '需要 Copper Loader 0.2.1 以上；与部分整合包的核心模组冲突。',
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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

  void _openMore(BuildContext buttonContext) {
    final skin = TemplateSkin.ofContext(context);
    final box = buttonContext.findRenderObject() as RenderBox?;
    final position = box == null
        ? const Offset(120, 120)
        : box.localToGlobal(Offset.zero) + Offset(0, box.size.height + 4);
    showTemplateMenu(
      context,
      skin: skin,
      globalPosition: position,
      items: [
        TemplateMenuItem(label: '模组详情', icon: Icons.info_outline, onTap: () {}),
        TemplateMenuItem(
          label: 'README',
          icon: Icons.description_outlined,
          onTap: () => setState(() => _tab = 2),
        ),
        TemplateMenuItem(label: '源码仓库', icon: Icons.folder_open, onTap: () {}),
        TemplateMenuItem(
          label: '作者主页',
          icon: Icons.person_outline,
          onTap: () {},
        ),
      ],
    );
  }

  // ── 版本列表 ──

  Widget _buildVersions(TemplateSkin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.md,
      children: [
        TemplateCard(
          skin: skin,
          padding: const EdgeInsets.symmetric(vertical: TemplateSpace.xs),
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
                      width: 180,
                      child: TemplateSegment(
                        skin: skin,
                        options: const ['全部', '仅兼容'],
                        value: _filter,
                        onTap: (index) => setState(() => _filter = index),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '仅兼容 = 支持当前选中版本的最新几个',
                        style: TemplateType.caption.copyWith(
                          color: skin.textTertiary,
                        ),
                      ),
                    ),
                    TemplateButton(
                      skin: skin,
                      label: '重新读取',
                      icon: Icons.refresh,
                      kind: TemplateButtonKind.quiet,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              _buildColumnHeader(skin),
              for (var i = 0; i < _versions.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: TemplateSpace.xs,
                    ),
                    color: skin.border,
                  ),
                _buildVersionRow(skin, _versions[i]),
              ],
              _buildPager(skin),
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
    Widget cell(double width, String label) => SizedBox(
      width: width,
      child: Text(
        label,
        style: TemplateType.micro.copyWith(color: skin.textTertiary),
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
          cell(90, '版本'),
          cell(110, '日期'),
          cell(80, '体积'),
          cell(70, '下载'),
          Expanded(
            child: Text(
              '兼容当前版本',
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
            ),
          ),
          const SizedBox(width: 88),
        ],
      ),
    );
  }

  Widget _buildVersionRow(
    TemplateSkin skin,
    (String, String, String, String, bool) version,
  ) {
    final (tag, date, size, downloads, compatible) = version;
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
            width: 80,
            child: Text(
              size,
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '↓ $downloads',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TemplateBadge(
                skin: skin,
                label: compatible ? '兼容' : '可能不兼容',
                tone: compatible
                    ? TemplateBadgeTone.success
                    : TemplateBadgeTone.warning,
              ),
            ),
          ),
          TemplateButton(
            skin: skin,
            label: '下载',
            icon: Icons.download,
            kind: TemplateButtonKind.plain,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildPager(TemplateSkin skin) {
    return TemplateRow(
      skin: skin,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '第 $_page / 3 页',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          Row(
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
          ),
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
