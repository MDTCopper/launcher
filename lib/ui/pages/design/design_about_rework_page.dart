import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

const designAboutReworkPageRouteKey = '/design/example/about';

/// 设计规范 · 实例页 · 关于页重做
///
/// 素材是 `ui/pages/overview/version_setting.dart` 的「关于」分项（版本信息 / 快捷方式 /
/// 新建变体 / 导入资源 / 导出资源）：原实现仍在原位跑，这一页**用参考模版的皮肤把同样的
/// 内容重做一遍**，用来对比同一批内容的观感
class DesignAboutReworkPage extends StatefulWidget {
  const DesignAboutReworkPage({super.key});

  @override
  State<DesignAboutReworkPage> createState() => _DesignAboutReworkPageState();
}

class _DesignAboutReworkPageState extends State<DesignAboutReworkPage> {
  double _hue = TemplateHues.copper;
  bool _favorite = false;

  static const _shortcuts = <({IconData icon, String label})>[
    (icon: Icons.save, label: '存档文件夹'),
    (icon: Icons.map_outlined, label: '地图文件夹'),
    (icon: Icons.paste, label: '蓝图文件夹'),
    (icon: Icons.extension_outlined, label: '模组文件夹'),
    (icon: Icons.file_copy, label: '导出崩溃日志'),
    (icon: Icons.broken_image_outlined, label: '查看崩溃日志'),
    (icon: Icons.download_for_offline_outlined, label: '导入本机存档'),
  ];

  TemplateSkin get _skin => TemplateSkin.of(
    hue: _hue,
    dark: Theme.of(context).brightness == Brightness.dark,
  );

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
        _buildVersionInfo(skin),
        _buildShortcuts(skin),
        _buildVariant(skin),
        _buildImport(skin),
        _buildExport(skin),
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

  // ════════ 版本信息 ════════

  Widget _buildVersionInfo(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '版本信息',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          HintLayer(
            hint: '点击重命名该版本',
            child: TemplateRow(
              skin: skin,
              onTap: () {},
              padding: const EdgeInsets.all(TemplateSpace.md),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: skin.accentTint,
                      borderRadius: BorderRadius.circular(TemplateRadius.card),
                    ),
                    child: Icon(
                      Icons.memory,
                      size: 28,
                      color: skin.onAccentTint,
                    ),
                  ),
                  const SizedBox(width: TemplateSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: TemplateSpace.xs,
                      children: [
                        Text(
                          'v160.5',
                          style: TemplateType.page.copyWith(
                            color: skin.textPrimary,
                          ),
                        ),
                        Text(
                          '桌面版 · 已隔离数据目录',
                          style: TemplateType.caption.copyWith(
                            color: skin.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          TemplateKeyRow(skin: skin, title: '添加时间', value: '2026-10-05 13:54'),
          TemplateKeyRow(
            skin: skin,
            title: '模组加载器',
            value: 'Copper Loader 0.2.0',
          ),
          // 动作按重量排：这一块没有主行动，破坏性的那个用 danger 推到最右
          TemplateRow(
            skin: skin,
            child: Row(
              spacing: TemplateSpace.md,
              children: [
                TemplateButton(
                  skin: skin,
                  label: _favorite ? '已收藏' : '未收藏',
                  icon: _favorite ? Icons.star : Icons.star_outline,
                  kind: TemplateButtonKind.quiet,
                  onTap: () => setState(() => _favorite = !_favorite),
                ),
                TemplateButton(
                  skin: skin,
                  label: '生成启动脚本',
                  icon: Icons.build_circle,
                  kind: TemplateButtonKind.quiet,
                ),
                TemplateButton(
                  skin: skin,
                  label: '补齐加载器',
                  icon: Icons.build_circle_outlined,
                  kind: TemplateButtonKind.quiet,
                ),
                const Spacer(),
                TemplateButton(
                  skin: skin,
                  label: '删除版本',
                  icon: Icons.delete_outline,
                  kind: TemplateButtonKind.danger,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════ 快捷方式 ════════

  Widget _buildShortcuts(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '快捷方式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          Text(
            '快速打开对应文件夹',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              for (final item in _shortcuts)
                TemplateShortcut(
                  skin: skin,
                  icon: item.icon,
                  label: item.label,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════ 新建变体 ════════

  Widget _buildVariant(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '新建变体',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          Text(
            '以当前版本为模板新建一个版本：游戏本体共用（不复制），新版本默认开启存档隔离；'
            '模组 / 存档 / 地图 / 蓝图 / 游戏设置可以分别勾选继承',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          Row(
            spacing: TemplateSpace.md,
            children: [
              TemplateButton(
                skin: skin,
                label: '新建变体',
                icon: Icons.copy_all,
                kind: TemplateButtonKind.plain,
              ),
              TemplateButton(
                skin: skin,
                label: '换启动器新建',
                icon: Icons.extension_outlined,
                kind: TemplateButtonKind.plain,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════ 导入资源 ════════

  Widget _buildImport(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '导入资源',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          Text(
            '支持导入游戏地图、蓝图和模组',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          Row(
            spacing: TemplateSpace.md,
            children: [
              TemplateButton(
                skin: skin,
                label: '导入资源',
                icon: Icons.layers_outlined,
                kind: TemplateButtonKind.plain,
              ),
              TemplateButton(
                skin: skin,
                label: '批量导入',
                icon: Icons.folder_outlined,
                kind: TemplateButtonKind.plain,
              ),
            ],
          ),
          TemplateNotice(skin: skin, text: 'tip：可以将资源或游戏本体拖进 Copper 直接导入'),
        ],
      ),
    );
  }

  // ════════ 导出资源 ════════

  Widget _buildExport(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '导出资源',
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          TemplateButton(
            skin: skin,
            label: '存档',
            icon: Icons.save,
            kind: TemplateButtonKind.plain,
          ),
          TemplateButton(
            skin: skin,
            label: '地图',
            icon: Icons.map_outlined,
            kind: TemplateButtonKind.plain,
          ),
          TemplateButton(
            skin: skin,
            label: '模组',
            icon: Icons.extension_outlined,
            kind: TemplateButtonKind.plain,
          ),
          TemplateButton(
            skin: skin,
            label: '蓝图',
            icon: Icons.paste,
            kind: TemplateButtonKind.plain,
          ),
        ],
      ),
    );
  }
}
