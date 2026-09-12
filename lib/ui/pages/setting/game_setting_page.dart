import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/mindustry_settings.dart';
import 'package:copper_launcher/data/setting_adapter.dart';
import 'package:copper_launcher/data/setting_metadata.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_checkbox.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/animation/switcher_builder.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/material.dart';

/// 游戏内设置页（数据驱动）。
///
/// 顶部选版本（自动=当前选中版本）+ 分类导航；按选中版本的 build 读
/// `setting_adapter/<min>-<max>.json` 决定显示哪些设置，分类点击切换显示，
/// 避免列表过长。值读写统一走 [MindustrySettingsPatch.getValue/setValue]。
class GameSettingPage extends StatefulWidget {
  const GameSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _GameSettingPageState();
}

class _GameSettingPageState extends State<GameSettingPage> {
  MindustrySettingsPatch get settings => config.setting.mindustrySettings;

  bool get settingsOverride => config.setting.mindustrySettingsOverride;

  /// 当前编辑的版本；null = 跟随选中版本
  Mindustry? _version;

  /// 当前显示的可设置列表
  List<SettingSpec> _specs = mindustrySettingCatalog;

  SettingCategory _category = SettingCategory.common;

  /// 整数滑块在「未覆盖」时展示的缓存值
  final Map<String, int> _intCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 按当前版本的 build 加载适配设置；无适配文件则用完整目录。
  Future<void> _load() async {
    final version = _version ?? config.versionOptions.selectedVersion;
    final build = version?.releaseInt;
    List<SettingSpec>? specs;
    if (build != null) {
      specs = await SettingAdapter.loadForBuild(build);
    }
    if (!mounted) return;
    setState(() {
      _specs = specs ?? mindustrySettingCatalog;
      //切到第一个仍有设置的分类
      final present = _specs.map((s) => s.category).toSet();
      if (!present.contains(_category)) {
        _category = present.isEmpty ? SettingCategory.common : present.first;
      }
    });
  }

  List<SettingSpec> get _categorySpecs =>
      _specs.where((s) => s.category == _category).toList();

  List<SettingCategory> get _presentCategories => SettingCategory.values
      .where((c) => _specs.any((s) => s.category == c))
      .toList();

  // ── 写回 ──

  void _setValue(SettingSpec spec, dynamic value) {
    setState(() => settings.setValue(spec.key, value));
    config.save();
  }

  // ── 控件 ──

  Widget _buildBoolBar(SettingSpec spec) {
    final value = settings.getValue(spec.key) as bool?;
    return Row(
      spacing: 8,
      children: [
        Text(spec.title),
        Expanded(child: SizedBox()),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.fromBorderSide(
              Theme.of(context).inputDecorationTheme.border?.borderSide ??
                  BorderSide(),
            ),
          ),
          child: Row(
            spacing: 4,
            children: [
              ReboundCheckbox(
                padding: const EdgeInsets.all(6),
                icon: Icons.close,
                value: value == false,
                onChange: (_) => _setValue(spec, false),
              ),
              ReboundCheckbox(
                padding: const EdgeInsets.all(6),
                icon: Icons.check,
                value: value == true,
                onChange: (_) => _setValue(spec, true),
              ),
              ReboundCheckbox(
                padding: const EdgeInsets.all(6),
                icon: Icons.settings,
                value: value == null,
                onChange: (_) => _setValue(spec, null),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatIntDisplay(int value, SettingSpec spec) {
    final shown = value * spec.displayRatio;
    final text = shown == shown.roundToDouble()
        ? shown.toStringAsFixed(0)
        : shown.toStringAsFixed(2);
    return spec.unit.isEmpty ? text : '$text${spec.unit}';
  }

  Widget _buildIntBar(SettingSpec spec) {
    final min = spec.min!;
    final max = spec.max!;
    final step = spec.step ?? 1;
    final divisions = ((max - min) / step).round();

    final field = settings.getValue(spec.key) as int?;
    if (field != null) _intCache[spec.key] = field;
    final display = field ?? _intCache[spec.key] ?? min;
    final override = field != null;
    final sliderValue = ((display - min) / (max - min)).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(width: 170, child: Text(spec.title)),
        SizedBox(
          width: 90,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              key: ValueKey(override),
              override ? _formatIntDisplay(display, spec) : '不变',
            ),
          ),
        ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(vertical: 8),
            value: sliderValue,
            divisions: divisions,
            min: 0.0,
            label: _formatIntDisplay(display, spec),
            onChanged: override
                ? (v) => setState(() {
                    final raw = v * (max - min) + min;
                    final stepped = ((raw - min) / step).round() * step + min;
                    final newVal = stepped.clamp(min, max);
                    _intCache[spec.key] = newVal;
                    settings.setValue(spec.key, newVal);
                    config.save();
                  })
                : null,
          ),
        ),
        SizedBox(width: 8),
        _buildOverrideIcon(
          !override,
          (v) => setState(() {
            if (v) {
              settings.setValue(spec.key, null);
            } else {
              settings.setValue(spec.key, _intCache[spec.key] ?? min);
            }
            config.save();
          }),
        ),
        const SizedBox(width: 5),
      ],
    );
  }

  Widget _buildOptionsBar(SettingSpec spec) {
    final value = settings.getValue(spec.key) as String?;
    final override = value != null;
    return Row(
      spacing: 8,
      children: [
        Text(spec.title),
        Expanded(child: SizedBox()),
        DropdownButton<String>(
          value: value ?? 'default',
          underline: const SizedBox(),
          items: [
            const DropdownMenuItem(value: 'default', child: Text('游戏默认')),
            for (final option in spec.options ?? const <String>[])
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: override ? (v) => _setValue(spec, v) : null,
        ),
        SizedBox(width: 8),
        _buildOverrideIcon(
          !override,
          (v) => setState(() {
            settings.setValue(spec.key, v ? null : 'default');
            config.save();
          }),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildOverrideIcon(bool value, void Function(bool)? onChange) {
    return ReboundCheckbox(
      value: value,
      padding: const EdgeInsets.all(6),
      icon: Icons.settings,
      onChange: onChange,
    );
  }

  Widget _buildSpecBar(SettingSpec spec) {
    switch (spec.type) {
      case SettingType.bool:
        return _buildBoolBar(spec);
      case SettingType.int:
        return _buildIntBar(spec);
      case SettingType.options:
        return _buildOptionsBar(spec);
    }
  }

  // ── 头部：版本选择 + 分类导航 ──

  Widget _buildHeader() {
    final colors = AppColors.of(context);
    final versions = <Mindustry>[
      for (final fold in config.versionOptions.versionFolds) ...fold.versions,
    ];

    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 8,
          children: [
            Text('编辑版本 '),
            DropdownLayer<Mindustry?>(
              width: 220,
              initialValue: _version,
              hintText: '跟随选中版本',
              onSelect: (v) {
                setState(() => _version = v);
                _load();
              },
              options: [
                const DropdownOption<Mindustry?>(value: null, label: '跟随选中版本'),
                for (final v in versions)
                  DropdownOption<Mindustry?>(value: v, label: v.tag),
              ],
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in _presentCategories)
              ReboundContainer(
                borderRadius: BorderRadius.circular(16),
                backgroundColor: _category == category
                    ? colors.interactive.withAlpha(40)
                    : null,
                onTap: () => setState(() => _category = category),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      category.title,
                      style: TextStyle(
                        color: _category == category
                            ? colors.interactive
                            : colors.itemPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '覆盖',
          child: Column(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchSettingBar(
                wide: 220,
                title: '启动时覆盖游戏内部设置',
                value: settingsOverride,
                onChanged: (v) => setState(() {
                  config.setting.mindustrySettingsOverride = v;
                  config.save();
                }),
              ),
              _buildHeader(),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: SwitcherBuilders.fadeSlide(),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: .topCenter,
            children: [...previousChildren, ?currentChild],
          ),
          child: KeyedSubtree(
            key: ValueKey(_category.title),
            child: ContentPanelModule(
              title: _category.title,
              child: Column(
                spacing: 8,
                children: [
                  for (final spec in _categorySpecs) _buildSpecBar(spec),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
