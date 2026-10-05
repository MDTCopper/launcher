import 'dart:math' as math;

import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

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

/// 皮肤令牌：浅 / 暗两套，只有这里能写死颜色
@immutable
class _Skin {
  const _Skin({
    required this.page,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.accentTint,
    required this.onAccentTint,
    required this.danger,
    required this.onDanger,
    required this.success,
    required this.warning,
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.shadow,
  });

  final Color page;
  final Color surface;
  final Color raised;
  final Color sunken;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// 实心强调：只用来铺底，白字必须压得住
  final Color accent;

  /// 强调色的文字 / 图标形态：与实心分开取值，浅暗各一支
  final Color accentText;
  final Color onAccent;

  /// 软底形态（待定用）：淡主题色底 + 深主题色字，块感更轻
  final Color accentTint;
  final Color onAccentTint;

  /// 破坏性：同样是「实心」与「文字」两种形态
  final Color danger;
  final Color onDanger;
  final Color success;
  final Color warning;
  final Color hover;
  final Color pressed;
  final Color selected;
  final Color shadow;

  static const light = _Skin(
    page: Color(0xFFF4F3F1),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFE4E1DD),
    border: Color(0xFFDCD8D2),
    borderStrong: Color(0xFFBFB9B1),
    textPrimary: Color(0xFF1F1D1B),
    textSecondary: Color(0xFF5C5852),
    textTertiary: Color(0xFF797369),
    // 浅色实心：从 #8F5A26 提亮到这一档（白字 4.82:1，仍达标；旧值对白卡 5.74 显得过重）
    accent: Color(0xFF9C6327),
    accentText: Color(0xFF9C6327),
    onAccent: Color(0xFFFFFBF7),
    accentTint: Color(0xFFE8CBA8),
    onAccentTint: Color(0xFF5E3711),
    danger: Color(0xFFA83232),
    onDanger: Color(0xFFFFFBF7),
    success: Color(0xFF2F6B3A),
    warning: Color(0xFF8A5A00),
    hover: Color(0x0F000000),
    pressed: Color(0x1A000000),
    selected: Color(0x178F5A26),
    shadow: Color(0x14000000),
  );

  static const dark = _Skin(
    page: Color(0xFF171614),
    surface: Color(0xFF201F1D),
    raised: Color(0xFF2A2825),
    sunken: Color(0xFF141311),
    border: Color(0xFF3A3733),
    borderStrong: Color(0xFF514D47),
    textPrimary: Color(0xFFF0EDE9),
    textSecondary: Color(0xFFB4AEA6),
    textTertiary: Color(0xFF8E8981),
    // 暗色的实心比旧的 copper600 深一档：对卡片 3.3:1（旧值 6.3:1，太跳）
    accent: Color(0xFF9A6229),
    accentText: Color(0xFFD9A76B),
    onAccent: Color(0xFFFFFBF7),
    accentTint: Color(0xFF4A3620),
    onAccentTint: Color(0xFFE3BE8F),
    danger: Color(0xFFBA4C4C),
    onDanger: Color(0xFFFFFBF7),
    success: Color(0xFF7FBF8A),
    warning: Color(0xFFD8A657),
    hover: Color(0x14FFFFFF),
    pressed: Color(0x1FFFFFFF),
    selected: Color(0x2E9A6229),
    shadow: Color(0x66000000),
  );
}

/// 文字层级：桌面密度，靠字重不靠把尺寸吹大
class _Type {
  static const page = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const section = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );
  static const item = TextStyle(fontSize: 14, height: 20 / 14);
  static const caption = TextStyle(fontSize: 12, height: 16 / 12);
  static const micro = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );
}

/// 几何：4 的倍数，4 / 8 / 12 / 16 / 24 / 32
class _Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class _Radius {
  static const control = 6.0;
  static const card = 10.0;
  static const pill = 999.0;
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

  _Skin get _skin => Theme.of(context).brightness == Brightness.dark
      ? _Skin.dark
      : _Skin.light;

  // ── 交互 ──

  void _noop() {}

  @override
  Widget build(BuildContext context) {
    final skin = _skin;

    return ListContentPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: _Space.xxl,
        vertical: _Space.xl,
      ),
      items: [
        _buildHeader(skin),
        _buildSection(
          skin,
          title: '运行环境',
          padding: const EdgeInsets.all(_Space.sm),
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
            spacing: _Space.lg,
            children: [
              _buildSegment(
                skin,
                options: const ['跟随全局', '自动分配', '自定义'],
                value: _segment,
                onTap: (i) => setState(() => _segment = i),
              ),
              Text(
                _segment == 2 ? '按滑杆指定上限，超了游戏会被系统杀掉' : '按物理内存的比例自动估算，一般不用改',
                style: _Type.caption.copyWith(color: skin.textTertiary),
              ),
            ],
          ),
        ),
        _buildSection(
          skin,
          title: '已安装的模组',
          padding: const EdgeInsets.all(_Space.sm),
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
      ],
    );
  }

  // ════════ 页头：一个视图只留一个实心主行动 ════════

  Widget _buildHeader(_Skin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _Space.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: _Space.xs,
              children: [
                Text(
                  '运行环境',
                  style: _Type.page.copyWith(color: skin.textPrimary),
                ),
                Text(
                  '与游戏版本无关，装一次所有版本共用',
                  style: _Type.caption.copyWith(color: skin.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: _Space.lg),
          _buildButton(
            skin,
            label: '重新检测',
            icon: Icons.refresh,
            kind: _Kind.quiet,
          ),
          const SizedBox(width: _Space.sm),
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

  Widget _buildSection(
    _Skin skin, {
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(_Space.lg),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _Space.sm,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: _Space.xs),
            child: Text(
              title,
              style: _Type.section.copyWith(color: skin.textSecondary),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(_Radius.card),
              border: Border.all(color: skin.border),
              boxShadow: [
                BoxShadow(
                  color: skin.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }

  // 行内不再画分隔线：线会和 rebound 的圆角悬停块打架（用户 2026-10-05 指出的）
  // ⇒ 行之间靠 2px 间距 + 每行自己的圆角高亮来分，见 _buildRow

  // ════════ 行：开关行 / 键值行 / 列表项 ════════

  Widget _buildSwitchRow(
    _Skin skin, {
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
          const SizedBox(width: _Space.lg),
          _buildSwitch(skin, value: value, onTap: onTap),
        ],
      ),
    );
  }

  Widget _buildKeyRow(_Skin skin, String title, String value) {
    return _buildRow(
      skin,
      child: Row(
        children: [
          Expanded(child: _buildTwoLine(skin, title, null)),
          const SizedBox(width: _Space.lg),
          Flexible(
            child: Text(
              value,
              style: _Type.item.copyWith(color: skin.textTertiary),
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
    _Skin skin,
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
              borderRadius: BorderRadius.circular(_Radius.control),
            ),
            child: Icon(
              Icons.extension_outlined,
              size: 20,
              color: skin.textSecondary,
            ),
          ),
          const SizedBox(width: _Space.md),
          Expanded(child: _buildTwoLine(skin, item.name, item.desc)),
          if (selected) Icon(Icons.check, size: 18, color: skin.accentText),
        ],
      ),
    );
  }

  /// 行外壳：走 rebound 的回弹与悬停，底色按状态给
  Widget _buildRow(
    _Skin skin, {
    required Widget child,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(_Radius.control),
      backgroundColor: selected ? skin.selected : Colors.transparent,
      hoverColor: skin.hover,
      padding: const EdgeInsets.symmetric(
        horizontal: _Space.md,
        vertical: _Space.md,
      ),
      child: child,
    );
  }

  Widget _buildTwoLine(_Skin skin, String title, String? desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          title,
          style: _Type.item.copyWith(color: skin.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (desc != null)
          Text(
            desc,
            style: _Type.caption.copyWith(color: skin.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  // ════════ 控件：开关 / 分段 ════════

  Widget _buildSwitch(
    _Skin skin, {
    required bool value,
    required VoidCallback onTap,
  }) {
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(_Radius.pill),
      backgroundColor: value ? skin.accent : skin.sunken,
      hoverColor: skin.hover,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 40,
        height: 22,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
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
    _Skin skin, {
    required List<String> options,
    required int value,
    required void Function(int index) onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(_Space.xs),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(_Radius.control + _Space.xs),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: ReboundContainer(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(_Radius.control),
                backgroundColor: value == i ? skin.surface : Colors.transparent,
                hoverColor: skin.hover,
                padding: const EdgeInsets.symmetric(vertical: _Space.sm),
                child: Text(
                  options[i],
                  textAlign: TextAlign.center,
                  style: _Type.item.copyWith(
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
    _Skin skin, {
    required String label,
    required IconData icon,
    required _Kind kind,
  }) {
    final (background, foreground) = switch (kind) {
      _Kind.solid => (skin.accent, skin.onAccent),
      _Kind.plain => (skin.raised, skin.textPrimary),
      _Kind.quiet => (Colors.transparent, skin.textSecondary),
    };

    return ReboundButton(
      onTap: _noop,
      backgroundColor: background,
      hoverColor: skin.hover,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(_Radius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: _Space.lg,
        vertical: _Space.sm + 1,
      ),
      child: DefaultTextStyle(
        style: _Type.item.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
        child: IconTheme(
          data: IconThemeData(color: foreground, size: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: _Space.sm,
            children: [Icon(icon), Text(label)],
          ),
        ),
      ),
    );
  }

  // ════════ 空态：标题写正面、说清下一步、给一个主行动 ════════

  Widget _buildEmpty(_Skin skin) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _Space.md,
        children: [
          Icon(Icons.inbox_outlined, size: 28, color: skin.textTertiary),
          Text(
            '从社区挑一个装进来',
            style: _Type.section.copyWith(color: skin.textPrimary),
          ),
          SizedBox(
            width: 360,
            child: Text(
              '装好后会出现在上面那份列表里，可以随时启用或禁用；'
              '不想联网的话，把 .jar 拖进窗口也行',
              style: _Type.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          Row(
            spacing: _Space.sm,
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

  Widget _buildNotice(_Skin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _Space.xl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: skin.sunken,
          borderRadius: BorderRadius.circular(_Radius.card),
          border: Border(left: BorderSide(color: skin.accent, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _Space.lg,
            vertical: _Space.md,
          ),
          child: Row(
            spacing: _Space.md,
            children: [
              Icon(Icons.info_outline, size: 18, color: skin.accentText),
              Expanded(
                child: Text(
                  '提示：资源或游戏本体可以直接拖进窗口导入',
                  style: _Type.caption.copyWith(color: skin.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════ 对照表：色值 + 现算的对比度 + 实物小样 ════════

  Widget _buildPaletteTable(_Skin skin) {
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
        need: '≥ 4.5',
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
              padding: const EdgeInsets.symmetric(vertical: _Space.sm),
              child: Row(
                spacing: _Space.md,
                children: [
                  // 实物：把前景色真的画在背景色上，比值对不对一眼能看
                  Container(
                    width: 56,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: row.bg,
                      borderRadius: BorderRadius.circular(_Radius.control),
                      border: Border.all(color: skin.border),
                    ),
                    child: Text(
                      'Aa',
                      style: _Type.section.copyWith(color: row.fg),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          row.name,
                          style: _Type.item.copyWith(color: skin.textPrimary),
                        ),
                        Text(
                          row.need,
                          style: _Type.micro.copyWith(color: skin.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_contrast(row.fg, row.bg).toStringAsFixed(2)}:1',
                    style: _Type.section.copyWith(color: skin.accentText),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ════════ 待定：主行动的两种形态 ════════

  Widget _buildPrimaryShapeChoice(_Skin skin) {
    final solid = _contrast(skin.onAccent, skin.accent);
    final tint = _contrast(skin.onAccentTint, skin.accentTint);

    return _buildSection(
      skin,
      title: '待定：主行动的两种形态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _Space.lg,
        children: [
          Row(
            spacing: _Space.md,
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
            style: _Type.caption.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildTintedButton(
    _Skin skin, {
    required Color background,
    required Color foreground,
    required String label,
  }) {
    return ReboundButton(
      onTap: _noop,
      backgroundColor: background,
      hoverColor: skin.hover,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(_Radius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: _Space.lg,
        vertical: _Space.sm + 1,
      ),
      child: DefaultTextStyle(
        style: _Type.item.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label)]),
      ),
    );
  }

  // ════════ 和 Copper 现状逐对比：颜色看着像，差的是这几处对比 ════════

  Widget _buildCompareWithCopper(_Skin skin) {
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
              padding: const EdgeInsets.symmetric(vertical: _Space.sm),
              child: Row(
                spacing: _Space.md,
                children: [
                  _buildSwatch(
                    fg: row.oldFg,
                    bg: row.oldBg,
                    border: skin.border,
                  ),
                  Text(
                    '${_contrast(row.oldFg, row.oldBg).toStringAsFixed(2)}:1',
                    style: _Type.micro.copyWith(color: skin.textTertiary),
                  ),
                  Icon(Icons.arrow_forward, size: 14, color: skin.textTertiary),
                  _buildSwatch(
                    fg: row.newFg,
                    bg: row.newBg,
                    border: skin.border,
                  ),
                  Text(
                    '${_contrast(row.newFg, row.newBg).toStringAsFixed(2)}:1',
                    style: _Type.micro.copyWith(color: skin.accentText),
                  ),
                  Expanded(
                    child: Text(
                      row.name,
                      textAlign: TextAlign.right,
                      style: _Type.micro.copyWith(color: skin.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: _Space.md),
            child: Text(
              '前三行是这次真正改掉的（旧值里三级小字 3.39、实心按钮上的字 2.95 都不达标）；'
              '最后一行两边一样低 —— 卡面与页底的明度差从来不是「抬起」的手段，'
              '那一格看不出区别是对的，抬起靠的是 1px 描边与那层暖色阴影',
              style: _Type.caption.copyWith(color: skin.textTertiary),
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
        borderRadius: BorderRadius.circular(_Radius.control),
        border: Border.all(color: border),
      ),
      child: Text('Aa', style: _Type.section.copyWith(color: fg)),
    );
  }
}

/// 按钮的三种量级
enum _Kind { solid, plain, quiet }

/// WCAG 对比度：(亮的相对明度 + 0.05) / (暗的 + 0.05)
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
