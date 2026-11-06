import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 预设色点（16 个）：与现有 App 的颜色选择弹窗同一批
const templatePresetColors = <Color>[
  Color(0xFFB8863E),
  Color(0xFFD89148),
  Color(0xFFE5A05B),
  Color(0xFFC46A3C),
  Color(0xFFB8453E),
  Color(0xFFD9534F),
  Color(0xFFC74C8A),
  Color(0xFF8E5BC9),
  Color(0xFF5A6FD8),
  Color(0xFF3D8EC4),
  Color(0xFF2F9E8F),
  Color(0xFF4CA64C),
  Color(0xFF8B9C2F),
  Color(0xFF6E6E6E),
  Color(0xFF9E9E9E),
  Color(0xFFD8D8D8),
];

/// 单个色点：选中打勾，勾色按底色亮度自动取黑 / 白
class TemplateColorSwatch extends StatelessWidget {
  const TemplateColorSwatch({
    super.key,
    required this.skin,
    required this.color,
    this.selected = false,
    this.size = 26,
    this.onTap,
  });

  final TemplateSkin skin;
  final Color color;
  final bool selected;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final checkColor = templateLuminance(color) > 0.5
        ? const Color(0xFF1A1A1A)
        : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? skin.textPrimary : skin.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: size * 0.6, color: checkColor)
            : null,
      ),
    );
  }
}

/// 16 个预置色点（8 列 × 2 行）
class TemplateColorPalette extends StatelessWidget {
  const TemplateColorPalette({
    super.key,
    required this.skin,
    required this.value,
    this.onSelected,
    this.columns = 8,
    this.swatchSize = 26,
  });

  final TemplateSkin skin;
  final Color? value;
  final ValueChanged<Color>? onSelected;
  final int columns;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: TemplateSpace.sm,
      runSpacing: TemplateSpace.sm,
      children: [
        for (final color in templatePresetColors)
          TemplateColorSwatch(
            skin: skin,
            color: color,
            size: swatchSize,
            selected: value?.toARGB32() == color.toARGB32(),
            onTap: onSelected == null ? null : () => onSelected!(color),
          ),
      ],
    );
  }
}

/// 色相条：0~1 → 0~360，轨道是彩虹渐变，把手是一根白边竖杆
class TemplateHueSlider extends StatelessWidget {
  const TemplateHueSlider({
    super.key,
    required this.skin,
    required this.value,
    this.onChanged,
    this.height = 12,
  });

  final TemplateSkin skin;

  /// 0~1
  final double value;
  final ValueChanged<double>? onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        void update(double dx) {
          if (onChanged == null || width <= 0) return;
          onChanged!((dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => update(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => update(details.localPosition.dx),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height / 2),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (width * value.clamp(0.0, 1.0) - 3).clamp(
                    0.0,
                    (width - 6).clamp(0.0, width),
                  ),
                  child: Container(
                    width: 6,
                    height: 22,
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: skin.borderStrong),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 饱和度 / 明度面板：横轴加白、纵轴加黑，把手是白边小圆
class TemplateSaturationValuePanel extends StatelessWidget {
  const TemplateSaturationValuePanel({
    super.key,
    required this.skin,
    required this.hue,
    required this.saturation,
    required this.value,
    this.onChanged,
    this.height = 120,
  });

  final TemplateSkin skin;

  /// 0~360
  final double hue;

  /// 0~1
  final double saturation;
  final double value;
  final void Function(double saturation, double value)? onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        void update(Offset position) {
          if (onChanged == null || width <= 0) return;
          final s = (position.dx / width).clamp(0.0, 1.0);
          final v = 1 - (position.dy / height).clamp(0.0, 1.0);
          onChanged!(s, v);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => update(details.localPosition),
          onPanUpdate: (details) => update(details.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TemplateRadius.card),
            child: SizedBox(
              height: height,
              width: width,
              child: Stack(
                children: [
                  // 横向：白 → 纯色；纵向：透明 → 黑
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.white, base]),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (width * saturation - 6).clamp(0.0, width - 12),
                    top: (height * (1 - value) - 6).clamp(0.0, height - 12),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        color: HSVColor.fromAHSV(
                          1,
                          hue,
                          saturation,
                          value,
                        ).toColor(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 颜色选择器：面板 + 色相条 + 16 色点，附带十六进制文字
class TemplateColorPicker extends StatelessWidget {
  const TemplateColorPicker({
    super.key,
    required this.skin,
    required this.color,
    this.onChanged,
    this.showPalette = true,
  });

  final TemplateSkin skin;
  final Color color;
  final ValueChanged<Color>? onChanged;
  final bool showPalette;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.md,
      children: [
        TemplateSaturationValuePanel(
          skin: skin,
          hue: hsv.hue,
          saturation: hsv.saturation,
          value: hsv.value,
          onChanged: onChanged == null
              ? null
              : (s, v) =>
                    onChanged!(HSVColor.fromAHSV(1, hsv.hue, s, v).toColor()),
        ),
        TemplateHueSlider(
          skin: skin,
          value: hsv.hue / 360,
          onChanged: onChanged == null
              ? null
              : (t) => onChanged!(
                  HSVColor.fromAHSV(
                    1,
                    t * 360,
                    hsv.saturation,
                    hsv.value,
                  ).toColor(),
                ),
        ),
        if (showPalette)
          TemplateColorPalette(skin: skin, value: color, onSelected: onChanged),
        Row(
          spacing: TemplateSpace.sm,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                border: Border.all(color: skin.border),
              ),
            ),
            Text(
              hex,
              style: TemplateType.caption.copyWith(color: skin.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}
