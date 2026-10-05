import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

const designSettingReworkPageRouteKey = '/design/example/setting';

/// 设计规范 · 实例页 · 设置页重做
///
/// 素材是 `ui/pages/overview/version_setting.dart` 的「设置」分项（启动选项 / 游戏内存 /
/// 高级选项）：原实现仍在原位跑，这一页**用参考模版的皮肤重做**，并把
/// 「同一件事几种做法」的地方点名
class DesignSettingReworkPage extends StatefulWidget {
  const DesignSettingReworkPage({super.key});

  @override
  State<DesignSettingReworkPage> createState() =>
      _DesignSettingReworkPageState();
}

class _DesignSettingReworkPageState extends State<DesignSettingReworkPage> {
  double _hue = TemplateHues.copper;

  // ── 演示状态 ──
  bool _isolation = true;
  int _java = 0;
  int _memoryMode = 1;
  double _memory = 0.6;
  int _gpu = 0;

  final _jvmController = TextEditingController(text: '-XX:+UseG1GC');

  /// 要规范的地方：位置 / 现象 / 建议
  static const _problems = <({String where, String problem, String fix})>[
    (
      where: '内存分配 / 使用高性能显卡（两个三选一）',
      problem:
          '用 `CheckboxSettingBar` + 三个 `ReboundCheckbox` 手拼出**单选**语义，还自带一段独有描边盒；两处各抄一遍 `onChange` + `config.save()`',
      fix: '改用分段选择（原有的 `SegmentSettingBar`，或模版里的 `TemplateSegment`），两处统一',
    ),
    (
      where: 'Steam 分支的只读行',
      problem: '同一件「标签 + 固定值」这里写 `SettingBarRow`、「关于」页写页面内联的 `buildInfo()`',
      fix: '统一走键值行组件（模版里是 `TemplateKeyRow`）',
    ),
    (
      where: '游戏 Java 的下拉选项文字',
      problem:
          '选项 label 把版本与实际路径拼在一行（`Java 17 ( "C:\\…\\bin\\java.exe" )`），主次不分且很长',
      fix: '选项只给「Java 17」；路径放提示或行下说明，别塞进选项',
    ),
    (
      where: '内存滑条的标题',
      problem: '`title: \'内存 6.0GB\'` —— 把实时值写进标题，与 `label` 重复，行的语义随拖动跳',
      fix: '标题固定为「内存上限」，实时值只给右侧的 label（模版的 `TemplateSliderRow` 就是这么做）',
    ),
    (
      where: '各处的间距',
      problem:
          '`Column(spacing: 8)` 与 `SizedBox(height: 8)` 混用，8 硬写；`SizedBox()` 空占位读不出意图',
      fix: '取令牌；空占位用 `SizedBox.shrink()`',
    ),
    (
      where: '内存信息那几行',
      problem: '`Expanded(child: SizedBox())` 当占位、两行数值用双空格凑对齐、样式走默认 Text',
      fix: '用 `Spacer()` 与两个槽对齐；数值行取 `caption` + `textSecondary`',
    ),
  ];

  TemplateSkin get _skin => TemplateSkin.of(
    hue: _hue,
    dark: Theme.of(context).brightness == Brightness.dark,
  );

  @override
  void dispose() {
    _jvmController.dispose();
    super.dispose();
  }

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
        _buildLaunchOptions(skin),
        _buildMemory(skin),
        _buildAdvanced(skin),
        _buildProblems(skin),
      ],
    );
  }

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
      child: Text(
        '素材是 `version_setting.dart` 的「设置」分项，用参考模版的皮肤重做；'
        '原实现仍在原位跑，下面每一块都对应它的一块',
        style: TemplateType.caption.copyWith(color: skin.textSecondary),
      ),
    );
  }

  // ════════ 1 启动选项 ════════

  Widget _buildLaunchOptions(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '1 启动选项',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          TemplateSwitchRow(
            skin: skin,
            title: '游戏存档隔离',
            desc: '存档与模组放在版本目录里，与别处那份分开',
            value: _isolation,
            onTap: () => setState(() => _isolation = !_isolation),
          ),
          // 原实现这里是个下拉，模版还没有下拉组件 ⇒ 先用分段把「少选项」的情形表达出来
          TemplateRow(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                TemplateTwoLine(
                  skin: skin,
                  title: '游戏 Java',
                  desc: '原实现是下拉，选项里还塞了完整路径',
                ),
                TemplateSegment(
                  skin: skin,
                  options: const ['跟随系统', 'Java 25', 'Java 17'],
                  value: _java,
                  onTap: (index) => setState(() => _java = index),
                ),
              ],
            ),
          ),
          TemplateKeyRow(
            skin: skin,
            title: 'Steam 版存档',
            value: '由 Steam 管理（固定）',
          ),
        ],
      ),
    );
  }

  // ════════ 2 游戏内存 ════════

  Widget _buildMemory(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '2 游戏内存',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          TemplateRow(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                TemplateTwoLine(skin: skin, title: '内存分配'),
                TemplateSegment(
                  skin: skin,
                  options: const ['跟随全局', '自动分配', '自定义'],
                  value: _memoryMode,
                  onTap: (index) => setState(() => _memoryMode = index),
                ),
              ],
            ),
          ),
          // 只有选了自定义才出现滑条
          if (_memoryMode == 2)
            TemplateSliderRow(
              skin: skin,
              title: '内存上限',
              label: '${(_memory * 12).toStringAsFixed(1)} GB',
              value: _memory,
              onChanged: (value) => setState(() => _memory = value),
            ),
          TemplateRow(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                TemplateProgressBar(skin: skin, value: 0.37, height: 8),
                Row(
                  children: [
                    Text(
                      '当前占用',
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '12.0 / 32.0 GB（37.5%）',
                      style: TemplateType.caption.copyWith(
                        color: skin.textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '将为游戏分配',
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '6.0 GB',
                      style: TemplateType.caption.copyWith(
                        color: skin.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════ 3 高级选项 ════════

  Widget _buildAdvanced(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '3 高级选项',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          TemplateRow(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                TemplateTwoLine(skin: skin, title: '使用高性能显卡'),
                TemplateSegment(
                  skin: skin,
                  options: const ['跟随全局', '关闭', '开启'],
                  value: _gpu,
                  onTap: (index) => setState(() => _gpu = index),
                ),
              ],
            ),
          ),
          TemplateInputRow(
            skin: skin,
            title: 'jvm 虚拟机参数',
            controller: _jvmController,
            hint: '-XX:+UseG1GC',
          ),
        ],
      ),
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
