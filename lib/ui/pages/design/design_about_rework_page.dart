import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

const designAboutReworkPageRouteKey = '/design/example/about';

/// 设计规范 · 实例页 · 关于页重做
///
/// 素材是 `ui/pages/overview/version_setting.dart` 的「关于」分项：原实现仍在原位跑，
/// 这里**用参考模版的皮肤重做一版**（`TemplateSkin` + `template_widgets.dart`），
/// 并把原实现暴露出来的「用途不明确 / 参数神出鬼没」逐条点名
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

  /// 要规范的地方：位置 / 现象 / 建议
  static const _problems = <({String where, String problem, String fix})>[
    (
      where: '版本信息的两条信息行',
      problem:
          '页面内联的 `buildInfo()` 局部函数（labelLarge + Spacer + 默认 Text 样式），没有对应组件',
      fix: '用 `SettingBarRow`（或模版里的 `TemplateKeyRow`），别在页面里再写一份',
    ),
    (
      where: '版本瓦片',
      problem:
          '`ReboundListTile(borderRadius: circular(4), padding: all(4))` —— 圆角与内衬硬写在调用处',
      fix: '取令牌（模版里是 `TemplateRadius.control` / `TemplateSpace.md`）',
    ),
    (
      where: '动作行（收藏 / 生成脚本 / 补齐加载器 / 删除版本）',
      problem: '四个动作全是默认重量，破坏性的「删除版本」与「收藏」一样重',
      fix: '按重量分级，删除类用 `TemplateButtonKind.danger`（重做版已用上）',
    ),
    (
      where: '快捷方式',
      problem: '`Wrap(spacing: 8, runSpacing: 8)` 与每个按钮的 `width: 136` 都硬写在调用处',
      fix: '间距取令牌；改用 `TemplateShortcut`（自适应宽度，不再逐处定宽）',
    ),
    (
      where: '导入资源的 tip 条',
      problem:
          '手写的 `Container(lowBackgroundOnCard, radius 4)`，而项目里早有 `buildWarningBar`',
      fix:
          '收成一个提示条组件（模版里是 `TemplateNotice`）；**关闭态那套写 `customSetting` 的逻辑还没接**，等组件收编',
    ),
    (
      where: '各区块说明文字',
      problem: '直接用 `theme.textTheme.labelMedium` 当说明（label 一族本该给标签 / 徽标）',
      fix: '说明用 `TemplateType.caption` + `textTertiary`（模版里已如此）',
    ),
    (
      where: '模组文件夹按钮（`_ModsFolderButton`）',
      problem: '与普通按钮并排但行为不同（先解析路径再打开），从名字与外观上看不出来',
      fix: '组件说明里写清用途与参数；或收成一个更通用的「按类型打开目录」组件',
    ),
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
        _buildIntro(skin),
        _buildVersionInfo(skin),
        _buildShortcuts(skin),
        _buildNotice(skin),
        _buildProblems(skin),
      ],
    );
  }

  // ════════ 色相开关：同一份内容，四个主题色各看一遍 ════════

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Text(
            '素材是 `version_setting.dart` 的「关于」分项。原实现还在原位跑，这一页有两层意思：'
            '① 按规范把内容重做一遍 ② 把原实现暴露出来的问题逐条点名',
            style: TemplateType.caption.copyWith(color: skin.textSecondary),
          ),
          Text(
            '上半页就是重做版 —— 它现在用的是参考模版的皮肤（`TemplateSkin` + `template_widgets.dart`），'
            '所有颜色都由色相解出来，不读 AppColors',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  // ════════ 1 版本信息 ════════

  Widget _buildVersionInfo(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '1 版本信息',
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

  // ════════ 2 快捷方式 ════════

  Widget _buildShortcuts(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '2 快捷方式',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Wrap(
        spacing: TemplateSpace.md,
        runSpacing: TemplateSpace.md,
        children: [
          for (final item in _shortcuts)
            TemplateShortcut(skin: skin, icon: item.icon, label: item.label),
        ],
      ),
    );
  }

  // ════════ 3 提示条 ════════

  Widget _buildNotice(TemplateSkin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.md,
      children: [
        TemplateNotice(skin: skin, text: 'tip：可以把资源或游戏本体拖进 Copper 直接导入'),
        Text(
          '原实现里这条是手写的 Container，而且带「关掉就不再显示」的逻辑（写 `customSetting`）；'
          '模版的 `TemplateNotice` 还没有这层交互，等组件收编时一起接',
          style: TemplateType.caption.copyWith(color: skin.textTertiary),
        ),
        const SizedBox(height: TemplateSpace.lg),
      ],
    );
  }

  // ════════ 4 要规范的地方 ════════

  Widget _buildProblems(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '4 要规范的地方（组件库的输入）',
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
