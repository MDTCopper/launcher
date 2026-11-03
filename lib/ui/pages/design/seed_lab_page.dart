import 'package:copper_launcher/ui/components/copper_card.dart';
import 'package:copper_launcher/ui/components/input/color_picker.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/hct/hct.dart';

/// 种子配色调试页（`kDebugMode` 才有，路由 `/seed_lab`）
///
/// 拿一个种子色生成整套皮肤，右边实时看组件长什么样；调完把顶部那行参数抄下来
class SeedLabPage extends StatefulWidget {
  const SeedLabPage({super.key});

  @override
  State<SeedLabPage> createState() => _SeedLabPageState();
}

class _SeedLabPageState extends State<SeedLabPage> {
  // 默认值 = 用户调定的那套（TemplateSkin.tuned），从这里继续微调
  Color _seed = const Color(0xFFD89148);
  double _hueOffset = 0;
  double _chromaScale = 1;
  double _neutralChroma = 2.6;
  double _accentShift = -5;
  bool _dark = false;

  // 预览里的演示状态
  bool _switchOn = true;
  int _segment = 0;
  double _slider = 0.55;
  final _input = TextEditingController(text: '-XX:+UseG1GC');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  TemplateSkin get _skin {
    final seeded = Hct.fromInt(_seed.toARGB32());
    return TemplateSkin.of(
      hue: (seeded.hue + _hueOffset) % 360,
      chroma: (seeded.chroma * _chromaScale).clamp(0, 120),
      dark: _dark,
      neutralChroma: _neutralChroma,
      // 实心照种子本身的明度出，不再为白字压暗
      accentTone: seeded.tone,
      // 实心与卡面的最小对比度：2 才保得住亮黄那种金色（3 会压成琥珀）
      accentCardContrast: 2,
      // 实心：亮色加亮 N 档、暗色压暗 N 档
      accentModeShift: _accentShift,
    );
  }

  String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final skin = _skin;
    final seeded = Hct.fromInt(_seed.toARGB32());

    final params =
        '种子 ${_hex(_seed)} · hue ${seeded.hue.toStringAsFixed(1)} '
        '${_hueOffset >= 0 ? '+' : ''}${_hueOffset.toStringAsFixed(0)} · '
        'chroma ${seeded.chroma.toStringAsFixed(1)} × ${_chromaScale.toStringAsFixed(2)} · '
        '表面色度 ${_neutralChroma.toStringAsFixed(1)} · '
        '实心偏移 ±${_accentShift.toStringAsFixed(0)} · ${_dark ? '暗色' : '亮色'}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = _buildControls(context, skin, params);
        final preview = _buildPreview(skin);
        final narrow = constraints.maxWidth < 1000;
        final padded = Padding(
          padding: const EdgeInsets.all(AppSpacing.block),
          child: narrow
              ? SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.block,
                    children: [
                      controls,
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(width: 760, child: preview),
                      ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.block,
                  children: [
                    SizedBox(width: 400, child: controls),
                    Expanded(child: SingleChildScrollView(child: preview)),
                  ],
                ),
        );
        return padded;
      },
    );
  }

  Widget _buildControls(
    BuildContext context,
    TemplateSkin skin,
    String params,
  ) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    Widget slider({
      required String label,
      required double value,
      required double min,
      required double max,
      required ValueChanged<double> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.tight,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: text.bodySmall),
              Text(value.toStringAsFixed(2), style: text.bodySmall),
            ],
          ),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.group,
        children: [
          CopperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.tight,
              children: [
                Text('种子色', style: text.titleSmall),
                SizedBox(
                  height: 260,
                  child: ColorPicker(
                    color: _seed,
                    showAlpha: false,
                    onChanged: (color) => setState(() => _seed = color),
                  ),
                ),
              ],
            ),
          ),
          CopperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.tight,
              children: [
                slider(
                  label: '色相偏移',
                  value: _hueOffset,
                  min: -10,
                  max: 10,
                  onChanged: (value) => setState(() => _hueOffset = value),
                ),
                slider(
                  label: '色度缩放',
                  value: _chromaScale,
                  min: 0.4,
                  max: 1.6,
                  onChanged: (value) => setState(() => _chromaScale = value),
                ),
                slider(
                  label: '表面色度（0 = 纯灰）',
                  value: _neutralChroma,
                  min: 0,
                  max: 6,
                  onChanged: (value) => setState(() => _neutralChroma = value),
                ),
                slider(
                  label: '实心偏移（负 = 反向：亮更暗 / 暗更亮）',
                  value: _accentShift,
                  min: -10,
                  max: 14,
                  onChanged: (value) => setState(() => _accentShift = value),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('暗色预览', style: text.bodyMedium),
                    Switch(
                      value: _dark,
                      onChanged: (value) => setState(() => _dark = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          CopperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.tight,
              children: [
                Text('参数（调完把这行发我）', style: text.titleSmall),
                SelectableText(params, style: text.bodySmall),
                SelectableText(
                  '生成值：实心 ${_hex(skin.accent)} · 页底 ${_hex(skin.page)} · '
                  '卡面 ${_hex(skin.surface)} · 凹槽 ${_hex(skin.sunken)}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(TemplateSkin skin) {
    Widget swatch(String label, Color color) {
      return Column(
        spacing: AppSpacing.tight,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: skin.border),
            ),
          ),
          Text(
            '$label ${_hex(color)}',
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
          ),
        ],
      );
    }

    Widget section(String title, Widget child) {
      return TemplateSection(skin: skin, title: title, child: child);
    }

    return Container(
      color: skin.page,
      padding: const EdgeInsets.all(TemplateSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.lg,
        children: [
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              swatch('页底', skin.page),
              swatch('卡面', skin.surface),
              swatch('凹槽', skin.sunken),
              swatch('实心', skin.accent),
              swatch('边界', skin.controlBorder),
              // 选中底是半透明叠层，按压到卡面上的合成结果展示
              swatch('选中底', Color.alphaBlend(skin.selected, skin.surface)),
            ],
          ),
          section(
            '按钮',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                Wrap(
                  spacing: TemplateSpace.md,
                  runSpacing: TemplateSpace.md,
                  children: [
                    TemplateButton(
                      skin: skin,
                      label: '启动游戏',
                      icon: Icons.play_arrow,
                      kind: TemplateButtonKind.solid,
                      onTap: () {},
                    ),
                    TemplateButton(
                      skin: skin,
                      label: '打开文件夹',
                      icon: Icons.folder_open,
                      kind: TemplateButtonKind.plain,
                      onTap: () {},
                    ),
                    TemplateButton(
                      skin: skin,
                      label: '取消',
                      icon: Icons.close,
                      kind: TemplateButtonKind.quiet,
                      onTap: () {},
                    ),
                    TemplateButton(
                      skin: skin,
                      label: '删除',
                      icon: Icons.delete_outline,
                      kind: TemplateButtonKind.danger,
                      onTap: () {},
                    ),
                  ],
                ),
                Wrap(
                  spacing: TemplateSpace.md,
                  runSpacing: TemplateSpace.md,
                  children: [
                    for (final (kind, label) in const [
                      (TemplateButtonKind.solid, '实心'),
                      (TemplateButtonKind.plain, '标准'),
                      (TemplateButtonKind.quiet, '安静'),
                      (TemplateButtonKind.danger, '破坏'),
                    ])
                      TemplateButton(
                        skin: skin,
                        label: label,
                        icon: Icons.block,
                        kind: kind,
                        enabled: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
          section(
            '设置',
            Column(
              spacing: 2,
              children: [
                TemplateSwitchRow(
                  skin: skin,
                  title: '游戏存档隔离',
                  desc: '存档与模组放在版本目录里',
                  value: _switchOn,
                  onTap: () => setState(() => _switchOn = !_switchOn),
                ),
                TemplateSwitchRow(
                  skin: skin,
                  title: '仅已同步时可用',
                  desc: '禁用态',
                  value: true,
                  onTap: () {},
                  enabled: false,
                ),
                TemplateSelectRow(
                  skin: skin,
                  title: '游戏Java',
                  value: 'Java 17',
                  onTap: () {},
                ),
                TemplateSettingTile(
                  skin: skin,
                  title: '自动检查启动器更新',
                  onTap: () {},
                  trailing: TemplateSwitch(
                    skin: skin,
                    value: _switchOn,
                    onTap: () => setState(() => _switchOn = !_switchOn),
                  ),
                ),
              ],
            ),
          ),
          section(
            '控件',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.md,
              children: [
                TemplateSegment(
                  skin: skin,
                  options: const ['跟随全局', '自动分配', '自定义'],
                  value: _segment,
                  onTap: (index) => setState(() => _segment = index),
                ),
                TemplateSliderRow(
                  skin: skin,
                  title: '内存上限',
                  label: '${(_slider * 12).toStringAsFixed(1)} GB',
                  value: _slider,
                  onChanged: (value) => setState(() => _slider = value),
                ),
                TemplateProgressBar(skin: skin, value: 0.62),
                TemplateInputRow(
                  skin: skin,
                  title: 'jvm虚拟机参数',
                  controller: _input,
                  hint: '-XX:+UseG1GC',
                ),
                TemplateNotice(skin: skin, text: '可以把资源或游戏本体拖进 Copper 直接导入'),
              ],
            ),
          ),
          section(
            '文字',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.xs,
              children: [
                Text(
                  '正文：版本 146 · 已就绪',
                  style: TemplateType.item.copyWith(color: skin.textPrimary),
                ),
                Text(
                  '次要：上次启动 2 小时前',
                  style: TemplateType.caption.copyWith(
                    color: skin.textSecondary,
                  ),
                ),
                Text(
                  '三级：E:\\Mindustry\\Copper',
                  style: TemplateType.micro.copyWith(color: skin.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
