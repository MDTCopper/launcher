import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// HSV 取色器：饱和/明度二维面板 + 色相渐变条 + 透明度渐变条（可关）
///
/// 自绘（不引第三方拾色件）。尺寸**跟着父级走**——二维面板用 [Expanded] 吃掉
/// 剩余高度，所以放进弹层 / 设置页 / 抽屉都能自适应，不用给定尺寸。
///
/// 受控用法：外部改 [color] 时会跟随（点了预设色 → 面板跟着跳）；
/// 自己派发出去的更新不会被打断（饱和/明度归 0 时色相是未定义的，重算会跳色相）。
class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.showAlpha = true,
    this.showReadout = true,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  /// 是否显示透明度条
  final bool showAlpha;

  /// 是否显示顶部预览圆点 + hex
  final bool showReadout;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);
  late double _alpha = _alphaOf(widget.color);

  /// 上一次由本组件派发出去的颜色：外部值与之相同就是「自己发出去的」，不重算色相
  Color? _emitted;

  static double _alphaOf(Color color) =>
      ((color.toARGB32() >> 24) & 0xFF) / 255;

  @override
  void didUpdateWidget(covariant ColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color && widget.color != _emitted) {
      _hsv = HSVColor.fromColor(widget.color);
      _alpha = _alphaOf(widget.color);
    }
  }

  void _emit() {
    final color = _hsv.withAlpha(_alpha).toColor();
    _emitted = color;
    widget.onChanged(color);
  }

  String get _hex =>
      '#${(_hsv.withAlpha(1).toColor().toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final opaque = _hsv.withAlpha(1).toColor();

    return Column(
      // stretch：二维面板 / 渐变条都是无 child 的 CustomPaint，宽度必须是紧约束，
      // 否则按 preferredSize（Size.zero）塌成 0 宽，什么都看不见
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (widget.showReadout)
          Row(
            spacing: 12,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: opaque.withAlpha((_alpha * 255).round()),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border),
                ),
              ),
              Text(
                widget.showAlpha
                    ? '$_hex  ${(_alpha * 100).round()}%'
                    : _hex,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        // 二维面板吃掉剩余空间（父级有线高时才能 Expanded）
        Expanded(
          child: _SvPanel(
            hue: _hsv.hue,
            saturation: _hsv.saturation,
            value: _hsv.value,
            onChanged: (saturation, value) => setState(() {
              _hsv = _hsv.withSaturation(saturation).withValue(value);
              _emit();
            }),
          ),
        ),
        SizedBox(
          height: 22,
          child: _GradientBar(
            colors: const [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
            value: _hsv.hue / 360,
            thumbColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
            onChanged: (v) => setState(() {
              _hsv = _hsv.withHue((v * 360).clamp(0, 359.99));
              _emit();
            }),
          ),
        ),
        if (widget.showAlpha)
          SizedBox(
            height: 22,
            child: _GradientBar(
              colors: [opaque.withAlpha(0), opaque],
              value: _alpha,
              thumbColor: opaque,
              onChanged: (v) => setState(() {
                _alpha = v;
                _emit();
              }),
            ),
          ),
      ],
    );
  }
}

/// 弹一个取色弹层，返回选中的颜色；取消返回 null
Future<Color?> showColorPickerDialog({
  required BuildContext context,
  required Color initialColor,
  bool showAlpha = true,
  String title = '选择颜色',
}) => showAnimatedDialog<Color>(
  context: context,
  pageBuilder: (_, _, _) => _ColorPickerDialog(
    initialColor: initialColor,
    showAlpha: showAlpha,
    title: title,
  ),
);

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initialColor,
    required this.showAlpha,
    required this.title,
  });

  final Color initialColor;
  final bool showAlpha;
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _color = widget.initialColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final screen = MediaQuery.of(context).size;

    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          // 有线高的尺寸：剩下的高度都归取色面板
          width: (screen.width * 0.45).clamp(280.0, 420.0).toDouble(),
          height: (screen.height * 0.7).clamp(320.0, 520.0).toDouble(),
          constraints: BoxConstraints(
            maxWidth: screen.width * 0.8,
            maxHeight: screen.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              top: BorderSide(color: colors.border, width: 1.5),
              left: BorderSide(color: colors.border, width: 0.75),
              right: BorderSide(color: colors.border, width: 0.75),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              Expanded(
                child: ColorPicker(
                  color: _color,
                  showAlpha: widget.showAlpha,
                  onChanged: (color) => setState(() => _color = color),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消',
                    onTap: () => Navigator.pop(context),
                  ),
                  IconTextButton(
                    icon: Icons.check,
                    content: '确定',
                    onTap: () => Navigator.pop(context, _color),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 饱和 / 明度面板：横轴饱和（白 → 纯色相）、纵轴明度（透明 → 黑），拖点选色
class _SvPanel extends StatelessWidget {
  const _SvPanel({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        void handle(Offset position) {
          onChanged(
            (position.dx / width).clamp(0.0, 1.0),
            (1 - position.dy / height).clamp(0.0, 1.0),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => handle(details.localPosition),
          onPanUpdate: (details) => handle(details.localPosition),
          child: CustomPaint(
            painter: _SvPainter(hue: hue, saturation: saturation, value: value),
          ),
        );
      },
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));

    // 横轴：白 → 纯色相
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    // 纵轴：透明 → 黑
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    // 当前点：白圈 + 黑细边，任何底色上都看得见
    final center = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black54,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvPainter oldDelegate) =>
      oldDelegate.hue != hue ||
      oldDelegate.saturation != saturation ||
      oldDelegate.value != value;
}

/// 渐变滑条：圆角渐变底 + 可拖的竖向滑块（色相 / 透明度共用）
class _GradientBar extends StatelessWidget {
  const _GradientBar({
    required this.colors,
    required this.value,
    required this.thumbColor,
    required this.onChanged,
  });

  final List<Color> colors;

  /// 0~1
  final double value;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        void handle(Offset position) =>
            onChanged((position.dx / width).clamp(0.0, 1.0));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => handle(details.localPosition),
          onPanUpdate: (details) => handle(details.localPosition),
          child: CustomPaint(
            painter: _GradientBarPainter(
              colors: colors,
              value: value,
              thumbColor: thumbColor,
            ),
          ),
        );
      },
    );
  }
}

class _GradientBarPainter extends CustomPainter {
  _GradientBarPainter({
    required this.colors,
    required this.value,
    required this.thumbColor,
  });

  final List<Color> colors;
  final double value;
  final Color thumbColor;

  static const _thumbWidth = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );

    final x = value.clamp(0.0, 1.0) * (size.width - _thumbWidth);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, -2, _thumbWidth, size.height + 4),
      const Radius.circular(3),
    );
    canvas.drawRRect(thumb, Paint()..color = Colors.white);
    canvas.drawRRect(
      thumb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = thumbColor,
    );
    canvas.drawRRect(
      thumb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black38,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientBarPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.thumbColor != thumbColor ||
      oldDelegate.colors != colors;
}
