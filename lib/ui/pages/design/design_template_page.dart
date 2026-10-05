import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';

const designTemplatePageRouteKey = '/design/example/template';

/// 参考模版：一套**脱离现有 AppColors** 的完整皮肤提案
///
/// 只保留 Copper 的 rebound 交互（[ReboundContainer] / [ReboundButton] 的回弹与悬停），
/// 颜色 / 文字层级 / 表面阶梯 / 间距全部由本文件自定义 ——
/// 目的：先做出一版「好看」的参考，再决定怎么套回 Copper。
/// 页面底部有一张现算的对比度表，谁都能复核
class DesignTemplatePage extends StatefulWidget {
  const DesignTemplatePage({super.key});

  @override
  State<DesignTemplatePage> createState() => _DesignTemplatePageState();
}

class _DesignTemplatePageState extends State<DesignTemplatePage> {
  bool _isolate = true;
  bool _autoUpdate = false;
  int _segment = 0;
  String? _selectedItem;

  static const _items = [
    (name: 'NewHorizon', desc: 'v2.1.4 · 大型模组 · 已启用'),
    (name: 'Endless', desc: 'v1.0.7 · 小游戏 · 已启用'),
    (name: 'Pac-Man', desc: 'v0.4.2 · 小游戏 · 已禁用'),
  ];

  /// 模版自己的主题色相（对应 Copper 的四个主题色），只影响这一页；
  /// 换色相就能看出「中性色跟着走」带来的色温差异
  double _hue = 33;

  // ── 模拟页的演示状态 ──
  int _downloadFilter = 0;
  final Set<String> _selectedVersions = {'v159.7'};

  static const _downloadVersions =
      <({String tag, String desc, double progress})>[
        (tag: 'v160.5', desc: '正式版 · 2026-09-28 · 62.4 MB', progress: 1),
        (tag: 'v160.4', desc: '正式版 · 2026-08-30 · 61.9 MB', progress: 0.62),
        (tag: 'v159.7', desc: '正式版 · 2026-07-12 · 60.1 MB', progress: 0),
        (tag: 'v158', desc: '正式版 · 2026-05-02 · 58.7 MB', progress: 0),
      ];

  static const _hues = <({String name, double hue})>[
    (name: '铜', hue: 33),
    (name: '钛', hue: 210),
    (name: '钍', hue: 305),
    (name: '塑钢', hue: 97),
  ];

  TemplateSkin get _skin => TemplateSkin.of(
    hue: _hue,
    dark: Theme.of(context).brightness == Brightness.dark,
  );

  // ── 交互 ──

  void _noop() {}

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
        _buildHeader(skin),
        _buildSection(
          skin,
          title: '运行环境',
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Column(
            spacing: 2,
            children: [
              _buildSwitchRow(
                skin,
                title: '隔离游戏数据目录',
                desc: '存档与模组放在版本目录里，与 Steam 那份分开',
                value: _isolate,
                onTap: () => setState(() => _isolate = !_isolate),
              ),
              _buildKeyRow(skin, '游戏 Java', 'Java 25 · /opt/jdk-25'),
              _buildSwitchRow(
                skin,
                title: '启动时检查更新',
                desc: '启动器有新版本时提示一次',
                value: _autoUpdate,
                onTap: () => setState(() => _autoUpdate = !_autoUpdate),
              ),
            ],
          ),
        ),
        _buildSection(
          skin,
          title: '内存分配',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.lg,
            children: [
              _buildSegment(
                skin,
                options: const ['跟随全局', '自动分配', '自定义'],
                value: _segment,
                onTap: (i) => setState(() => _segment = i),
              ),
              Text(
                _segment == 2 ? '按滑杆指定上限，超了游戏会被系统杀掉' : '按物理内存的比例自动估算，一般不用改',
                style: TemplateType.caption.copyWith(color: skin.textTertiary),
              ),
            ],
          ),
        ),
        _buildSection(
          skin,
          title: '已安装的模组',
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Column(
            spacing: 2,
            children: [
              for (final item in _items)
                _buildItemRow(skin, item, selected: _selectedItem == item.name),
            ],
          ),
        ),
        _buildSection(skin, title: '还没有安装的模组', child: _buildEmpty(skin)),
        _buildNotice(skin),
        _buildPrimaryShapeChoice(skin),
        _buildCompareWithCopper(skin),
        _buildPaletteTable(skin),
        _buildMockLaunch(skin),
        _buildMockDownload(skin),
        _buildMockCloud(skin),
      ],
    );
  }

  // ════════ 色相开关：同一套推导，四个主题色各来一遍 ════════

  Widget _buildHueSwitch(TemplateSkin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.lg),
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          Text(
            '主题色相（色温）',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          SizedBox(
            width: 320,
            child: _buildSegment(
              skin,
              options: [for (final item in _hues) item.name],
              value: _hues.indexWhere((item) => item.hue == _hue),
              onTap: (index) => setState(() => _hue = _hues[index].hue),
            ),
          ),
          Text(
            '换一个色相，整套中性色与强调色都会跟着重算',
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  // ════════ 页头：一个视图只留一个实心主行动 ════════

  Widget _buildHeader(TemplateSkin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.xs,
              children: [
                Text(
                  '运行环境',
                  style: TemplateType.page.copyWith(color: skin.textPrimary),
                ),
                Text(
                  '与游戏版本无关，装一次所有版本共用',
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: TemplateSpace.lg),
          _buildButton(
            skin,
            label: '重新检测',
            icon: Icons.refresh,
            kind: _Kind.quiet,
          ),
          const SizedBox(width: TemplateSpace.sm),
          _buildButton(
            skin,
            label: '一键装齐',
            icon: Icons.download,
            kind: _Kind.solid,
          ),
        ],
      ),
    );
  }

  // ════════ 分组卡：标题在卡内、小字、中性色 ════════

  /// 分组卡：标题**在卡内**；标题不给就是一张纯内容卡
  ///
  /// **内容一律落在卡面上** —— 行直接贴在页面底上时，静止状态看不出这一组从哪到哪，
  /// 只有悬停才显形；卡面提供的是「共同区域」这条最省力的分组手段（2026-10-05 用户指出）。
  /// **卡默认占满宽度**（卡宽跟着内容走会让同一页的卡宽窄参差）；**标题融入卡内**
  /// —— 与共享层 `TemplateSection` 的规则一致，两边要一起改
  Widget _buildSection(
    TemplateSkin skin, {
    String? title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(TemplateSpace.lg),
  }) {
    // 卡间距：这里只给 12，`ListContentPanel` 默认再给 12 ⇒ 合计 24（组间）。
    // 别只改这里，两组加起来 36 会显得空（2026-10-05 用户指出过大）
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(TemplateRadius.card),
          border: Border.all(color: skin.border),
          boxShadow: [
            BoxShadow(
              color: skin.shadow,
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.md,
            children: [
              if (title != null)
                Text(
                  title,
                  style: TemplateType.section.copyWith(color: skin.textPrimary),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }

  // 行内不再画分隔线：线会和 rebound 的圆角悬停块打架（用户 2026-10-05 指出的）
  // ⇒ 行之间靠 2px 间距 + 每行自己的圆角高亮来分，见 _buildRow

  // ════════ 行：开关行 / 键值行 / 列表项 ════════

  Widget _buildSwitchRow(
    TemplateSkin skin, {
    required String title,
    required String desc,
    required bool value,
    required VoidCallback onTap,
  }) {
    return _buildRow(
      skin,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: _buildTwoLine(skin, title, desc)),
          const SizedBox(width: TemplateSpace.lg),
          _buildSwitch(skin, value: value, onTap: onTap),
        ],
      ),
    );
  }

  Widget _buildKeyRow(TemplateSkin skin, String title, String value) {
    return _buildRow(
      skin,
      child: Row(
        children: [
          Expanded(child: _buildTwoLine(skin, title, null)),
          const SizedBox(width: TemplateSpace.lg),
          Flexible(
            child: Text(
              value,
              style: TemplateType.item.copyWith(color: skin.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(
    TemplateSkin skin,
    ({String name, String desc}) item, {
    required bool selected,
  }) {
    return _buildRow(
      skin,
      selected: selected,
      onTap: () => setState(() => _selectedItem = selected ? null : item.name),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: skin.sunken,
              borderRadius: BorderRadius.circular(TemplateRadius.control),
            ),
            child: Icon(
              Icons.extension_outlined,
              size: 20,
              color: skin.textSecondary,
            ),
          ),
          const SizedBox(width: TemplateSpace.md),
          Expanded(child: _buildTwoLine(skin, item.name, item.desc)),
          if (selected) Icon(Icons.check, size: 18, color: skin.accentText),
        ],
      ),
    );
  }

  /// 行外壳：走 rebound 的回弹与悬停，底色按状态给
  Widget _buildRow(
    TemplateSkin skin, {
    required Widget child,
    VoidCallback? onTap,
    bool selected = false,
    EdgeInsetsGeometry? padding,
  }) {
    final background = selected ? skin.selected : Colors.transparent;
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: background,
      hoverColor: skin.hoverOn(background),
      highlightColor: skin.pressedOn(background),
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: TemplateSpace.md,
            vertical: TemplateSpace.md,
          ),
      child: child,
    );
  }

  Widget _buildTwoLine(TemplateSkin skin, String title, String? desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          title,
          style: TemplateType.item.copyWith(color: skin.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (desc != null)
          Text(
            desc,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  // ════════ 控件：开关 / 分段 ════════

  Widget _buildSwitch(
    TemplateSkin skin, {
    required bool value,
    required VoidCallback onTap,
  }) {
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(TemplateRadius.pill),
      backgroundColor: value ? skin.accent : skin.sunken,
      hoverColor: skin.hoverOn(value ? skin.accent : skin.sunken),
      highlightColor: skin.pressedOn(value ? skin.accent : skin.sunken),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 40,
        height: 22,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TemplateRadius.pill),
          // 关着的时候轨道也要认得出来（1.4.11 那条 3:1）
          border: value ? null : Border.all(color: skin.controlBorder),
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: value ? skin.onAccent : skin.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(
    TemplateSkin skin, {
    required List<String> options,
    required int value,
    required void Function(int index) onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(TemplateSpace.xs),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(
          TemplateRadius.control + TemplateSpace.xs,
        ),
        border: Border.all(color: skin.controlBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: ReboundContainer(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                backgroundColor: value == i ? skin.surface : Colors.transparent,
                hoverColor: skin.hoverOn(
                  value == i ? skin.surface : Colors.transparent,
                ),
                highlightColor: skin.pressedOn(
                  value == i ? skin.surface : Colors.transparent,
                ),
                padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
                child: Text(
                  options[i],
                  textAlign: TextAlign.center,
                  style: TemplateType.item.copyWith(
                    color: value == i ? skin.textPrimary : skin.textSecondary,
                    fontWeight: value == i ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════ 按钮：实心一个、中性若干、安静若干 ════════

  Widget _buildButton(
    TemplateSkin skin, {
    required String label,
    required IconData icon,
    required _Kind kind,
  }) {
    final (background, foreground) = switch (kind) {
      _Kind.solid => (skin.accent, skin.onAccent),
      _Kind.plain => (skin.raised, skin.textPrimary),
      _Kind.quiet => (Colors.transparent, skin.textSecondary),
      _Kind.danger => (Colors.transparent, skin.dangerText),
    };

    return ReboundButton(
      onTap: _noop,
      backgroundColor: background,
      hoverColor: skin.hoverOn(background),
      highlightColor: skin.pressedOn(background),
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.sm + 1,
      ),
      child: DefaultTextStyle(
        style: TemplateType.item.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
        child: IconTheme(
          data: IconThemeData(color: foreground, size: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: TemplateSpace.sm,
            children: [Icon(icon), Text(label)],
          ),
        ),
      ),
    );
  }

  // ════════ 空态：标题写正面、说清下一步、给一个主行动 ════════

  Widget _buildEmpty(TemplateSkin skin) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Icon(Icons.inbox_outlined, size: 28, color: skin.textTertiary),
          Text(
            '从社区挑一个装进来',
            style: TemplateType.section.copyWith(color: skin.textPrimary),
          ),
          SizedBox(
            width: 360,
            child: Text(
              '装好后会出现在上面那份列表里，可以随时启用或禁用；'
              '不想联网的话，把 .jar 拖进窗口也行',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          Row(
            spacing: TemplateSpace.sm,
            children: [
              _buildButton(
                skin,
                label: '去浏览社区',
                icon: Icons.explore_outlined,
                kind: _Kind.solid,
              ),
              _buildButton(
                skin,
                label: '导入本地文件',
                icon: Icons.folder_open,
                kind: _Kind.quiet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════ 提示条：靠底色与左边一道强调线，不靠描边圈住 ════════

  Widget _buildNotice(TemplateSkin skin) {
    // 不再自带边距：它是卡里的一项，间距由 `_buildSection` 的 spacing 管
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
        border: Border(left: BorderSide(color: skin.accent, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TemplateSpace.lg,
          vertical: TemplateSpace.md,
        ),
        child: Row(
          spacing: TemplateSpace.md,
          children: [
            Icon(Icons.info_outline, size: 18, color: skin.accentText),
            Expanded(
              child: Text(
                '提示：资源或游戏本体可以直接拖进窗口导入',
                style: TemplateType.caption.copyWith(color: skin.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════ 对照表：色值 + 现算的对比度 + 实物小样 ════════

  Widget _buildPaletteTable(TemplateSkin skin) {
    final rows = <({String name, Color fg, Color bg, String need})>[
      (name: '正文 / 卡面', fg: skin.textPrimary, bg: skin.surface, need: '≥ 4.5'),
      (
        name: '次要文字 / 卡面',
        fg: skin.textSecondary,
        bg: skin.surface,
        need: '≥ 4.5',
      ),
      (
        name: '三级文字 / 卡面',
        fg: skin.textTertiary,
        bg: skin.surface,
        need: '≥ 5.5：字号越小门槛越高，这一档几乎不带色',
      ),
      (
        name: '控件边界 / 卡面',
        fg: skin.controlBorder,
        bg: skin.surface,
        need: '≥ 3（WCAG 1.4.11，输入框 / 分段 / 开关这类靠它认出来）',
      ),
      (name: '实心按钮上的字', fg: skin.onAccent, bg: skin.accent, need: '≥ 4.5'),
      (
        name: '强调色文字 / 卡面',
        fg: skin.accentText,
        bg: skin.surface,
        need: '≥ 4.5',
      ),
      (name: '破坏性实心上的字', fg: skin.onDanger, bg: skin.danger, need: '≥ 4.5'),
      (
        name: '破坏性文字 / 卡面',
        fg: skin.dangerText,
        bg: skin.surface,
        need: '≥ 4.5：「删除」这类文字按钮用这一档，与实心那档分开解',
      ),
      (
        name: '实心块 / 卡面',
        fg: skin.accent,
        bg: skin.surface,
        need: '主行动跳出来即可，越暗越闷',
      ),
      (
        name: '卡面 / 页面底',
        fg: skin.surface,
        bg: skin.page,
        need: '这一对本来就低，抬起靠描边与阴影',
      ),
      (name: '凹槽 / 卡面', fg: skin.sunken, bg: skin.surface, need: '低，看得出凹就行'),
      (name: '描边 / 卡面', fg: skin.border, bg: skin.surface, need: '低，1px 够用'),
    ];

    return _buildSection(
      skin,
      title: '这套皮肤的实测对比度（现算，左边就是实物）',
      child: Column(
        spacing: 2,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
              child: Row(
                spacing: TemplateSpace.md,
                children: [
                  // 实物：把前景色真的画在背景色上，比值对不对一眼能看
                  Container(
                    width: 56,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: row.bg,
                      borderRadius: BorderRadius.circular(
                        TemplateRadius.control,
                      ),
                      border: Border.all(color: skin.border),
                    ),
                    child: Text(
                      'Aa',
                      style: TemplateType.section.copyWith(color: row.fg),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          row.name,
                          style: TemplateType.item.copyWith(
                            color: skin.textPrimary,
                          ),
                        ),
                        Text(
                          row.need,
                          style: TemplateType.micro.copyWith(
                            color: skin.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${templateContrast(row.fg, row.bg).toStringAsFixed(2)}:1',
                    style: TemplateType.section.copyWith(
                      color: skin.accentText,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ════════ 待定：主行动的两种形态 ════════

  Widget _buildPrimaryShapeChoice(TemplateSkin skin) {
    final solid = templateContrast(skin.onAccent, skin.accent);
    final tint = templateContrast(skin.onAccentTint, skin.accentTint);

    return _buildSection(
      skin,
      title: '待定：主行动的两种形态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          Row(
            spacing: TemplateSpace.md,
            children: [
              _buildTintedButton(
                skin,
                background: skin.accent,
                foreground: skin.onAccent,
                label: '实心 · 字 ${solid.toStringAsFixed(2)}:1',
              ),
              _buildTintedButton(
                skin,
                background: skin.accentTint,
                foreground: skin.onAccentTint,
                label: '软底 · 字 ${tint.toStringAsFixed(2)}:1',
              ),
            ],
          ),
          Text(
            '实心那块面积大、颜色深，在大留白的版面上容易显重（用户 2026-10-05 的反馈）；'
            '软底是「淡主题色底 + 深主题色字」，块感轻得多、字还更清楚，'
            '代价是它在卡面上只比背景重一点（浅色 1.55:1），靠的那点「有色」而不是「有明度」',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildTintedButton(
    TemplateSkin skin, {
    required Color background,
    required Color foreground,
    required String label,
  }) {
    return ReboundButton(
      onTap: _noop,
      backgroundColor: background,
      hoverColor: skin.hoverOn(background),
      highlightColor: skin.pressedOn(background),
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.sm + 1,
      ),
      child: DefaultTextStyle(
        style: TemplateType.item.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label)]),
      ),
    );
  }

  // ════════ 和 Copper 现状逐对比：颜色看着像，差的是这几处对比 ════════

  Widget _buildCompareWithCopper(TemplateSkin skin) {
    // Copper 现状的色值（浅色主题），写在这里方便并排看
    const oldSurface = Color(0xFFE9E9E9);
    const oldPage = Color(0xFFD4D4D4);
    const oldTextPrimary = Color(0xFF4C4C4C);
    const oldTextHint = Color(0xFF7D7D7D);
    const oldAccent = Color(0xFFB8863E);
    const oldOnAccent = Color(0xFFF5F5F5);

    final rows =
        <({String name, Color oldFg, Color oldBg, Color newFg, Color newBg})>[
          (
            name: '正文文字',
            oldFg: oldTextPrimary,
            oldBg: oldSurface,
            newFg: skin.textPrimary,
            newBg: skin.surface,
          ),
          (
            name: '三级小字',
            oldFg: oldTextHint,
            oldBg: oldSurface,
            newFg: skin.textTertiary,
            newBg: skin.surface,
          ),
          (
            name: '实心按钮上的字',
            oldFg: oldOnAccent,
            oldBg: oldAccent,
            newFg: skin.onAccent,
            newBg: skin.accent,
          ),
          (
            name: '卡面 / 页面底',
            oldFg: oldSurface,
            oldBg: oldPage,
            newFg: skin.surface,
            newBg: skin.page,
          ),
        ];

    return _buildSection(
      skin,
      title: '和 Copper 现状逐对比（左旧右新，比值都是现算）',
      child: Column(
        spacing: 2,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
              child: Row(
                spacing: TemplateSpace.md,
                children: [
                  _buildSwatch(
                    fg: row.oldFg,
                    bg: row.oldBg,
                    border: skin.border,
                  ),
                  Text(
                    '${templateContrast(row.oldFg, row.oldBg).toStringAsFixed(2)}:1',
                    style: TemplateType.micro.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 14, color: skin.textTertiary),
                  _buildSwatch(
                    fg: row.newFg,
                    bg: row.newBg,
                    border: skin.border,
                  ),
                  Text(
                    '${templateContrast(row.newFg, row.newBg).toStringAsFixed(2)}:1',
                    style: TemplateType.micro.copyWith(color: skin.accentText),
                  ),
                  Expanded(
                    child: Text(
                      row.name,
                      textAlign: TextAlign.right,
                      style: TemplateType.micro.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: TemplateSpace.md),
            child: Text(
              '前三行是这次真正改掉的（旧值里三级小字 3.39、实心按钮上的字 2.95 都不达标）；'
              '最后一行两边一样低 —— 卡面与页底的明度差从来不是「抬起」的手段，'
              '那一格看不出区别是对的，抬起靠的是 1px 描边与那层暖色阴影',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwatch({
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      width: 48,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        border: Border.all(color: border),
      ),
      child: Text('Aa', style: TemplateType.section.copyWith(color: fg)),
    );
  }

  // ════════ 真场景模拟：主页 / 下载页 / 云存档页 ════════
  //
  // 三个模拟页各自是独立的一屏，所以每屏各有一个实心主行动；
  // 这里为对照竖着排在一起，真实使用时不会同时出现

  Widget _buildMockLaunch(TemplateSkin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _buildMockLabel(skin, '模拟页：主页'),
        // 当前版本：一张卡面 + 唯一的实心主行动
        _buildSection(
          skin,
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Column(
            spacing: 2,
            children: [
              _buildRow(
                skin,
                padding: const EdgeInsets.all(TemplateSpace.md),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: skin.accentTint,
                        borderRadius: BorderRadius.circular(
                          TemplateRadius.card,
                        ),
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
                            '桌面版 · Copper 加载器 · 已隔离数据目录',
                            style: TemplateType.caption.copyWith(
                              color: skin.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: TemplateSpace.lg),
                    _buildButton(
                      skin,
                      label: '启动游戏',
                      icon: Icons.play_arrow,
                      kind: _Kind.solid,
                    ),
                  ],
                ),
              ),
              _buildRow(
                skin,
                child: Row(
                  spacing: TemplateSpace.md,
                  children: [
                    _buildButton(
                      skin,
                      label: '版本设置',
                      icon: Icons.tune,
                      kind: _Kind.plain,
                    ),
                    _buildButton(
                      skin,
                      label: '打开数据目录',
                      icon: Icons.folder_open,
                      kind: _Kind.quiet,
                    ),
                    const Spacer(),
                    Text(
                      '上次启动 2 小时前',
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
        _buildSection(
          skin,
          title: '快捷入口',
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              for (final item in const [
                (icon: Icons.save, label: '存档'),
                (icon: Icons.map_outlined, label: '地图'),
                (icon: Icons.paste, label: '蓝图'),
                (icon: Icons.extension_outlined, label: '模组'),
              ])
                _buildShortcut(skin, icon: item.icon, label: item.label),
            ],
          ),
        ),
        _buildNotice(skin),
      ],
    );
  }

  Widget _buildMockDownload(TemplateSkin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _buildMockLabel(skin, '模拟页：下载页'),
        // 控件也落在卡面上：搜索框 + 筛选
        _buildSection(
          skin,
          padding: const EdgeInsets.all(TemplateSpace.lg),
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
                    Text(
                      '搜索版本号，如 160.5 / v8',
                      style: TemplateType.item.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              _buildSegment(
                skin,
                options: const ['全部', '正式版', '预览版', 'BE'],
                value: _downloadFilter,
                onTap: (index) => setState(() => _downloadFilter = index),
              ),
            ],
          ),
        ),
        _buildSection(
          skin,
          title: '版本列表（${_downloadVersions.length}）',
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Column(
            spacing: 2,
            children: [
              for (final item in _downloadVersions)
                _buildRow(
                  skin,
                  selected: _selectedVersions.contains(item.tag),
                  onTap: () => setState(() {
                    if (!_selectedVersions.remove(item.tag)) {
                      _selectedVersions.add(item.tag);
                    }
                  }),
                  child: _buildDownloadRow(skin, item),
                ),
            ],
          ),
        ),
        // 选中后浮出的操作栏（这里不浮，直接排在下面，也是一张卡）
        _buildSection(
          skin,
          padding: const EdgeInsets.symmetric(
            horizontal: TemplateSpace.lg,
            vertical: TemplateSpace.md,
          ),
          child: Row(
            spacing: TemplateSpace.md,
            children: [
              Text(
                '已选 ${_selectedVersions.length}',
                style: TemplateType.caption.copyWith(color: skin.textTertiary),
              ),
              const Spacer(),
              _buildButton(
                skin,
                label: '下载',
                icon: Icons.download,
                kind: _Kind.plain,
              ),
              _buildButton(
                skin,
                label: '删除',
                icon: Icons.delete_outline,
                kind: _Kind.danger,
              ),
              _buildButton(
                skin,
                label: '取消选择',
                icon: Icons.close,
                kind: _Kind.quiet,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadRow(
    TemplateSkin skin,
    ({String tag, String desc, double progress}) item,
  ) {
    final downloading = item.progress > 0 && item.progress < 1;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.xs,
            children: [
              Text(
                item.tag,
                style: TemplateType.item.copyWith(
                  color: skin.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                item.desc,
                style: TemplateType.caption.copyWith(color: skin.textTertiary),
              ),
              if (downloading) ...[
                const SizedBox(height: TemplateSpace.xs),
                // 进度：细轨 + 实心填充，不靠主题色文字去喊
                ClipRRect(
                  borderRadius: BorderRadius.circular(TemplateRadius.pill),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        ColoredBox(
                          color: skin.sunken,
                          child: const SizedBox.expand(),
                        ),
                        FractionallySizedBox(
                          widthFactor: item.progress,
                          child: ColoredBox(color: skin.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: TemplateSpace.lg),
        if (downloading)
          Text(
            '${(item.progress * 100).round()}%',
            style: TemplateType.caption.copyWith(color: skin.accentText),
          )
        else if (item.progress == 1)
          Text(
            '已下载',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          )
        else
          _buildButton(
            skin,
            label: '下载',
            icon: Icons.download,
            kind: _Kind.quiet,
          ),
      ],
    );
  }

  Widget _buildMockCloud(TemplateSkin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _buildMockLabel(skin, '模拟页：云存档页'),
        _buildSection(
          skin,
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: _buildRow(
            skin,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: skin.accentTint,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '雨',
                    style: TemplateType.item.copyWith(color: skin.onAccentTint),
                  ),
                ),
                const SizedBox(width: TemplateSpace.md),
                Expanded(
                  child: _buildTwoLine(skin, 'rainfall', '已登录 · 配额 200 MB'),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: skin.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: TemplateSpace.sm),
                Text(
                  '已同步',
                  style: TemplateType.caption.copyWith(
                    color: skin.textSecondary,
                  ),
                ),
                const SizedBox(width: TemplateSpace.lg),
                _buildButton(
                  skin,
                  label: '退出登录',
                  icon: Icons.logout,
                  kind: _Kind.quiet,
                ),
              ],
            ),
          ),
        ),
        _buildSection(
          skin,
          title: 'Android · v160.5',
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Column(
            spacing: 2,
            children: [
              _buildKeyRow(skin, '上次同步', '2026-10-05 13:54 · 16.6 MB'),
              _buildKeyRow(skin, '快照', '4 份 · 最近一份 2 小时前'),
              Padding(
                padding: const EdgeInsets.all(TemplateSpace.md),
                child: Row(
                  spacing: TemplateSpace.md,
                  children: [
                    _buildButton(
                      skin,
                      label: '上传到云端',
                      icon: Icons.cloud_upload_outlined,
                      kind: _Kind.solid,
                    ),
                    _buildButton(
                      skin,
                      label: '从云端恢复',
                      icon: Icons.cloud_download_outlined,
                      kind: _Kind.plain,
                    ),
                    const Spacer(),
                    _buildButton(
                      skin,
                      label: '删除云端包',
                      icon: Icons.delete_outline,
                      kind: _Kind.danger,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildSection(
          skin,
          title: '快照历史',
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Column(
            spacing: 2,
            children: [
              for (final item in const [
                (time: '今天 13:54', size: '16.6 MB', pinned: true),
                (time: '昨天 21:02', size: '16.4 MB', pinned: false),
                (time: '10-03 19:20', size: '15.9 MB', pinned: false),
              ])
                _buildRow(
                  skin,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTwoLine(skin, item.time, item.size),
                      ),
                      if (item.pinned) ...[
                        Icon(
                          Icons.push_pin_outlined,
                          size: 16,
                          color: skin.accentText,
                        ),
                        const SizedBox(width: TemplateSpace.sm),
                        Text(
                          '已固定',
                          style: TemplateType.caption.copyWith(
                            color: skin.accentText,
                          ),
                        ),
                      ] else
                        _buildButton(
                          skin,
                          label: '恢复',
                          icon: Icons.restore,
                          kind: _Kind.quiet,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 快捷入口小方块：并列入口，中性重量
  Widget _buildShortcut(
    TemplateSkin skin, {
    required IconData icon,
    required String label,
  }) {
    return ReboundContainer(
      onTap: _noop,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: skin.sunken,
      hoverColor: skin.hoverOn(skin.sunken),
      highlightColor: skin.pressedOn(skin.sunken),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TemplateSpace.sm,
        children: [
          Icon(icon, size: 18, color: skin.textSecondary),
          Text(
            label,
            style: TemplateType.item.copyWith(color: skin.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 模拟页的分隔标签：说清这是另一屏，不是当前页的一部分
  Widget _buildMockLabel(TemplateSkin skin, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.sm,
      children: [
        Divider(height: 1, thickness: 1, color: skin.borderStrong),
        Padding(
          padding: const EdgeInsets.only(top: TemplateSpace.md),
          child: Text(
            '$text（各自独立的一屏，每屏各有一个实心主行动）',
            style: TemplateType.section.copyWith(color: skin.accentText),
          ),
        ),
      ],
    );
  }
}

/// 按钮的四种量级：实心主行动 / 中性 / 安静 / 破坏性
enum _Kind { solid, plain, quiet, danger }
