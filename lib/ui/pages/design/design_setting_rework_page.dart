import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/input_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/option_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/segment_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/setting_bar_row.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/components/button/segment_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

const designSettingReworkPageRouteKey = '/design/example/setting';

/// 设计规范 · 实例页 · 设置页重做
///
/// 第二个真实素材：`ui/pages/overview/version_setting.dart` 的「设置」分项
/// （启动选项 / 游戏内存 / 高级选项）。原实现仍在原位跑，这里按规范重做一版，
/// 并把「同一件事几种做法」的地方点名
class DesignSettingReworkPage extends StatefulWidget {
  const DesignSettingReworkPage({super.key});

  @override
  State<DesignSettingReworkPage> createState() =>
      _DesignSettingReworkPageState();
}

class _DesignSettingReworkPageState extends State<DesignSettingReworkPage> {
  // ── 演示状态 ──
  bool _isolation = true;
  String _java = 'system';
  String _memoryMode = 'auto';
  double _memory = 0.6;
  String _gpu = 'follow';

  final _jvmController = TextEditingController(text: '-XX:+UseG1GC');

  static const _javaOptions = [
    DropdownOption(value: 'system', label: '跟随系统'),
    DropdownOption(value: 'jdk17', label: 'Java 17'),
    DropdownOption(value: 'jdk25', label: 'Java 25'),
  ];

  /// 要规范的地方：位置 / 现象 / 建议
  static const _problems = <({String where, String problem, String fix})>[
    (
      where: '内存分配 / 使用高性能显卡（两个三选一）',
      problem:
          '用 `CheckboxSettingBar` + 三个 `ReboundCheckbox` 手拼出**单选**语义（跟随全局 / 自动 / 自定义），'
          '还要自带那段独有描边盒；两处各抄一遍 `onChange` + `config.save()`',
      fix: '改用 `SegmentSettingBar`（项目里已有，天然单选），两处统一',
    ),
    (
      where: 'Steam 分支的只读行',
      problem:
          '同一件「标签 + 固定值」在这里写成 `SettingBarRow`，在「关于」页又写成页面内联的 `buildInfo()`',
      fix: '统一走 `SettingBarRow`（关于页重做里已这么做）',
    ),
    (
      where: '游戏 Java 的下拉选项文字',
      problem:
          '选项 label 把版本与实际路径拼在一行（`Java 17 ( "C:\\…\\bin\\java.exe" )`），主次不分且很长',
      fix: '选项只给「Java 17」；路径放 `HintLayer` 或行下的说明，别塞进选项',
    ),
    (
      where: '内存滑条的标题',
      problem: '`title: \'内存 6.0GB\'` —— 把实时值写进标题，与 `label` 重复，行的语义随拖动跳',
      fix: '标题固定为「内存上限」，实时值只给 label',
    ),
    (
      where: '各处的间距',
      problem:
          '`Column(spacing: 8)` 与 `SizedBox(height: 8)` 混用，8 硬写；`SizedBox()` 空占位读不出意图',
      fix: '取 `AppSpacing.related`；空占位用 `SizedBox.shrink()`',
    ),
    (
      where: '内存信息那几行',
      problem:
          '`Expanded(child: SizedBox())` 当占位符；两行数值用双空格凑对齐（当前占用 / 将为游戏分配），样式走默认 Text',
      fix:
          '用 `Spacer()`；数值行取 `bodySmall` + `itemSecondary`，靠 `Row` 的两个槽对齐而不是空格',
    ),
  ];

  @override
  void dispose() {
    _jvmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.block,
        vertical: AppSpacing.related,
      ),
      items: [
        _buildIntroModule(),
        _buildLaunchOptionModule(),
        _buildMemoryModule(),
        _buildAdvancedModule(),
        _buildProblemsModule(),
      ],
    );
  }

  Widget _buildIntroModule() {
    return ContentPanelModule(
      title: '这是什么',
      child: Text(
        '素材是 `version_setting.dart` 的「设置」分项（启动选项 / 游戏内存 / 高级选项）；'
        '原实现仍在原位跑，这一页是重做版 + 问题清单',
        style: _hintStyle(),
      ),
    );
  }

  // ════════ 1 启动选项（重做） ════════

  Widget _buildLaunchOptionModule() {
    return ContentPanelModule(
      title: '1 启动选项（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          SwitchSettingBar(
            title: '游戏存档隔离',
            value: _isolation,
            onChanged: (value) => setState(() => _isolation = value),
          ),
          OptionSettingBar<String>(
            title: '游戏Java',
            initialValue: _java,
            hintText: '跟随系统',
            options: _javaOptions,
            onSelect: (value) => setState(() => _java = value),
          ),
          // Steam 版那一支：值固定，用只读行
          SettingBarRow(
            title: '游戏存档隔离',
            control: Align(
              alignment: Alignment.centerRight,
              child: Text('由 Steam 管理（固定）', style: _valueStyle()),
            ),
          ),
          Text(
            '选项文字只写「Java 17」，路径不进选项；只读行统一用 SettingBarRow；'
            '行与行之间取 AppSpacing.related（原来硬写 8）',
            style: _hintStyle(),
          ),
        ],
      ),
    );
  }

  // ════════ 2 游戏内存（重做） ════════

  Widget _buildMemoryModule() {
    return ContentPanelModule(
      title: '2 游戏内存（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          SegmentSettingBar<String>(
            title: '内存分配',
            selected: {_memoryMode},
            segments: [
              ReboundButtonSegment(value: 'follow', label: Text('跟随全局')),
              ReboundButtonSegment(value: 'auto', label: Text('自动分配')),
              ReboundButtonSegment(value: 'custom', label: Text('自定义')),
            ],
            onChange: (set) => setState(() => _memoryMode = set.first),
          ),
          // 只有选了自定义才出现滑条，收起时不占位
          if (_memoryMode == 'custom')
            SliderSettingBar(
              title: '内存上限',
              label: '${(_memory * 8).toStringAsFixed(1)} GB',
              value: _memory,
              onChanged: (value) => setState(() => _memory = value),
            ),
          PercentBar(
            total: 32,
            dataList: [PercentBarData(value: 12), PercentBarData(value: 6)],
          ),
          Row(
            children: [
              Text('当前占用', style: _hintStyle()),
              const Spacer(),
              Text('12.0 / 32.0 GB（37.5%）', style: _valueStyle()),
            ],
          ),
          Row(
            children: [
              Text('将为游戏分配', style: _hintStyle()),
              const Spacer(),
              Text('6.0 GB', style: _valueStyle()),
            ],
          ),
          Text(
            '三选一改用 SegmentSettingBar（原来用三个复选框手拼单选取）；'
            '滑条标题固定成「内存上限」、实时值只给 label；'
            '两条信息行左右各一个槽，不靠空格凑对齐',
            style: _hintStyle(),
          ),
        ],
      ),
    );
  }

  // ════════ 3 高级选项（重做） ════════

  Widget _buildAdvancedModule() {
    return ContentPanelModule(
      title: '3 高级选项（重做）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          SegmentSettingBar<String>(
            title: '使用高性能显卡',
            selected: {_gpu},
            segments: [
              ReboundButtonSegment(value: 'follow', label: Text('跟随全局')),
              ReboundButtonSegment(value: 'off', label: Text('关闭')),
              ReboundButtonSegment(value: 'on', label: Text('开启')),
            ],
            onChange: (set) => setState(() => _gpu = set.first),
          ),
          InputSettingBar(
            title: 'jvm 虚拟机参数',
            controller: _jvmController,
            onEditingComplete: () => setState(() {}),
          ),
          Text('同一页里两个三选一现在长得一样、改法一样；输入行的行为不变（编辑完成才保存）', style: _hintStyle()),
        ],
      ),
    );
  }

  // ════════ 4 要规范的地方 ════════

  Widget _buildProblemsModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '4 要规范的地方（组件库的输入）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.group,
        children: [
          for (final item in _problems)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.tight,
              children: [
                Text(item.where, style: theme.textTheme.titleSmall),
                Text(item.problem, style: theme.textTheme.bodySmall),
                Text(
                  '→ ${item.fix}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.of(context).interactive,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 键值行右边的值（A 类：正文用 bodyMedium + itemPrimary）
  TextStyle? _valueStyle() => Theme.of(context).textTheme.bodyMedium;

  /// 页内说明文字（A 类：说明用 bodySmall + itemSecondary）
  TextStyle? _hintStyle() => Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: AppColors.of(context).itemSecondary);
}
