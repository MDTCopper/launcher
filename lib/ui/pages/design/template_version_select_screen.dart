import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_state.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 版本选择页（设计层版本，App 内可打开：`/template_version_select`，仅 debug 可见）
///
/// 功能面：当前版本 / 分类浏览与搜索 / 版本列表（选择、设置、删除、变体）/ 目录管理 / 导入
class TemplateVersionSelectScreen extends StatefulWidget {
  const TemplateVersionSelectScreen({super.key});

  @override
  State<TemplateVersionSelectScreen> createState() =>
      _TemplateVersionSelectScreenState();
}

class _TemplateVersionSelectScreenState
    extends State<TemplateVersionSelectScreen> {
  final _search = TextEditingController();

  int _tab = 0;
  String _selectedTag = 'v160.7';

  static const _tabs = ['收藏', '原版', '预览版'];

  static const _versions = [
    (
      tag: 'v160.7',
      name: 'Mindustry 6.0',
      build: 'build 123',
      size: '78.4 MB',
      path: 'versions/160.7',
      favorite: true,
      beta: false,
      variants: 2,
    ),
    (
      tag: 'v159.4',
      name: 'Mindustry 6.0',
      build: 'build 118',
      size: '77.1 MB',
      path: 'versions/159.4',
      favorite: false,
      beta: false,
      variants: 0,
    ),
    (
      tag: 'v158.1',
      name: 'Mindustry 6.0',
      build: 'build 111',
      size: '76.8 MB',
      path: 'versions/158.1',
      favorite: true,
      beta: true,
      variants: 1,
    ),
    (
      tag: 'v157.3',
      name: 'Mindustry 5.0',
      build: 'build 104',
      size: '71.2 MB',
      path: 'versions/157.3',
      favorite: false,
      beta: false,
      variants: 0,
    ),
  ];

  static const _folds = [
    ('默认目录', 'C:\\Users\\ASUS\\AppData\\Roaming\\Mindustry', '4 个版本'),
    ('Mindustry 6.0 preview', 'D:\\Games\\Mindustry\\preview', '2 个版本'),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);
    final compact = TemplateBreakpoints.isCompactWindow(
      MediaQuery.sizeOf(context).width,
    );

    return ColoredBox(
      color: skin.page,
      child: TemplateScrollView(
        skin: skin,
        padding: EdgeInsets.all(compact ? TemplateSpace.md : TemplateSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TemplateSpace.lg,
          children: [
            _currentVersionCard(skin, compact),
            _browseBar(skin, compact),
            _versionList(skin),
            _foldsSection(skin),
            _importSection(skin, compact),
          ],
        ),
      ),
    );
  }

  Widget _currentVersionCard(TemplateSkin skin, bool compact) {
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          Row(
            spacing: TemplateSpace.md,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: skin.sunken,
                  borderRadius: BorderRadius.circular(TemplateRadius.control),
                  border: Border.all(color: skin.border),
                ),
                child: Icon(
                  Icons.view_in_ar,
                  size: 26,
                  color: skin.textTertiary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.xxs,
                  children: [
                    Text(
                      '当前版本 · $_selectedTag',
                      style: TemplateType.section.copyWith(
                        color: skin.textPrimary,
                      ),
                    ),
                    Text(
                      'Mindustry 6.0 · build 123 · 78.4 MB',
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              TemplateButton(
                skin: skin,
                label: '设置',
                icon: Icons.settings_outlined,
                kind: TemplateButtonKind.quiet,
                onTap: () {},
              ),
            ],
          ),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.sm,
              children: [
                _startButton(skin),
                TemplateButton(
                  skin: skin,
                  label: '版本设置',
                  icon: Icons.tune,
                  kind: TemplateButtonKind.plain,
                  expanded: true,
                  onTap: () {},
                ),
              ],
            )
          else
            Row(
              spacing: TemplateSpace.sm,
              children: [
                Expanded(child: _startButton(skin)),
                TemplateButton(
                  skin: skin,
                  label: '版本设置',
                  icon: Icons.tune,
                  kind: TemplateButtonKind.plain,
                  onTap: () {},
                ),
                TemplateButton(
                  skin: skin,
                  label: '打开目录',
                  icon: Icons.folder_open,
                  kind: TemplateButtonKind.quiet,
                  onTap: () {},
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _startButton(TemplateSkin skin) {
    return TemplateButton(
      skin: skin,
      label: '启动游戏',
      icon: Icons.play_arrow,
      kind: TemplateButtonKind.solid,
      expanded: true,
      onTap: () {},
    );
  }

  Widget _browseBar(TemplateSkin skin, bool compact) {
    final tabs = [
      for (var i = 0; i < _tabs.length; i++) '${_tabs[i]}(${_countFor(i)})',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.sm,
      children: [
        TemplateTabBar(
          skin: skin,
          tabs: tabs,
          value: _tab,
          onTap: (index) => setState(() => _tab = index),
        ),
        Row(
          spacing: TemplateSpace.sm,
          children: [
            Expanded(
              child: TemplateTextField(
                skin: skin,
                controller: _search,
                hint: '搜索版本 / build / 目录',
              ),
            ),
            if (!compact)
              TemplateButton(
                skin: skin,
                label: '添加版本',
                icon: Icons.add,
                kind: TemplateButtonKind.plain,
                onTap: () {},
              ),
          ],
        ),
      ],
    );
  }

  int _countFor(int tab) {
    return switch (tab) {
      0 => _versions.where((v) => v.favorite).length,
      2 => _versions.where((v) => v.beta).length,
      _ => _versions.length,
    };
  }

  Widget _versionList(TemplateSkin skin) {
    final versions = _versions.where((version) {
      final matchTab = switch (_tab) {
        0 => version.favorite,
        2 => version.beta,
        _ => true,
      };
      final query = _search.text.trim().toLowerCase();
      final matchQuery =
          query.isEmpty ||
          version.tag.toLowerCase().contains(query) ||
          version.name.toLowerCase().contains(query);
      return matchTab && matchQuery;
    }).toList();

    if (versions.isEmpty) {
      return TemplateSection(
        skin: skin,
        title: '版本',
        child: TemplateEmptyState(
          skin: skin,
          title: '这一类还没有版本',
          message: '在下面的导入区添加本地游戏，或扫描 Steam 版',
          icon: Icons.view_in_ar_outlined,
        ),
      );
    }

    return TemplateSection(
      skin: skin,
      title: '版本（${versions.length}）',
      child: Column(
        spacing: TemplateSpace.xs,
        children: [
          for (final version in versions)
            TemplateListCard(
              skin: skin,
              title: '${version.tag} · ${version.name}',
              subtitle:
                  '${version.build} · ${version.size} · ${version.path}'
                  '${version.variants > 0 ? ' · ${version.variants} 个变体' : ''}',
              icon: Icons.view_in_ar,
              selected: version.tag == _selectedTag,
              badge: version.beta
                  ? Text(
                      '预览',
                      style: TemplateType.micro.copyWith(
                        color: skin.textSecondary,
                      ),
                    )
                  : null,
              onTap: () => setState(() => _selectedTag = version.tag),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: TemplateSpace.xs,
                children: [
                  if (version.tag == _selectedTag)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: skin.accentTint,
                        borderRadius: BorderRadius.circular(
                          TemplateRadius.pill,
                        ),
                      ),
                      child: Text(
                        '当前',
                        style: TemplateType.micro.copyWith(
                          color: skin.onAccentTint,
                        ),
                      ),
                    ),
                  TemplateButton(
                    skin: skin,
                    label: '',
                    icon: Icons.more_horiz,
                    kind: TemplateButtonKind.quiet,
                    onTap: () {},
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _foldsSection(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '游戏目录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.xs,
        children: [
          for (final (name, path, count) in _folds)
            TemplateRow(
              skin: skin,
              child: Row(
                spacing: TemplateSpace.sm,
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: skin.textSecondary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TemplateType.item.copyWith(
                            color: skin.textPrimary,
                          ),
                        ),
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TemplateType.micro.copyWith(
                            color: skin.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    count,
                    style: TemplateType.caption.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
                  TemplateButton(
                    skin: skin,
                    label: '',
                    icon: Icons.drive_file_rename_outline,
                    kind: TemplateButtonKind.quiet,
                    onTap: () {},
                  ),
                  TemplateButton(
                    skin: skin,
                    label: '',
                    icon: Icons.delete_outline,
                    kind: TemplateButtonKind.quiet,
                    danger: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          const SizedBox(height: TemplateSpace.xs),
          Row(
            spacing: TemplateSpace.sm,
            children: [
              TemplateButton(
                skin: skin,
                label: '添加新目录',
                icon: Icons.create_new_folder_outlined,
                kind: TemplateButtonKind.plain,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '新建分类',
                icon: Icons.label_outline,
                kind: TemplateButtonKind.quiet,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _importSection(TemplateSkin skin, bool compact) {
    final buttons = [
      TemplateButton(
        skin: skin,
        label: '导入本地游戏',
        icon: Icons.file_upload_outlined,
        kind: TemplateButtonKind.plain,
        expanded: compact,
        onTap: () {},
      ),
      TemplateButton(
        skin: skin,
        label: '扫描 Steam 版',
        icon: Icons.videogame_asset_outlined,
        kind: TemplateButtonKind.quiet,
        expanded: compact,
        onTap: () {},
      ),
      TemplateButton(
        skin: skin,
        label: '新建变体',
        icon: Icons.call_split,
        kind: TemplateButtonKind.quiet,
        expanded: compact,
        onTap: () {},
      ),
    ];
    return TemplateSection(
      skin: skin,
      title: '导入与新版本',
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.sm,
              children: buttons,
            )
          : Row(
              spacing: TemplateSpace.sm,
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 0),
                  buttons[i],
                ],
              ],
            ),
    );
  }
}
