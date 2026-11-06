import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 虚线框画笔：沿圆角矩形画一段段短线
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _strokeWidth = 1.0;
  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect.deflate(_strokeWidth / 2));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// 拖放目标：虚线框（悬停时变成实线 + 主题色底）
///
/// 覆盖度审计 P1-18（全窗口拖入 / 导入资源）；窗口级遮罩用 [TemplateDropOverlay]
class TemplateDropZone extends StatelessWidget {
  const TemplateDropZone({
    super.key,
    required this.skin,
    required this.title,
    this.hint,
    this.icon = Icons.file_download_outlined,
    this.active = false,
    this.height = 132,
    this.onTap,
  });

  final TemplateSkin skin;
  final String title;
  final String? hint;
  final IconData icon;

  /// 指针带着文件悬在窗口上时传 true
  final bool active;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: height,
      decoration: BoxDecoration(
        color: active ? skin.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
      ),
      child: CustomPaint(
        painter: active
            ? null
            : _DashedBorderPainter(
                color: skin.borderStrong,
                radius: TemplateRadius.card,
              ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: TemplateSpace.xs,
            children: [
              Icon(
                icon,
                size: 28,
                color: active ? skin.onAccentTint : skin.textTertiary,
              ),
              Text(
                title,
                style: TemplateType.item.copyWith(
                  color: active ? skin.onAccentTint : skin.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: TemplateType.micro.copyWith(
                    color: active ? skin.onAccentTint : skin.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

/// 窗口级拖放遮罩：拖文件进窗口时铺一层暗底 + 中间的提示框
class TemplateDropOverlay extends StatelessWidget {
  const TemplateDropOverlay({
    super.key,
    required this.skin,
    this.active = true,
    this.title = '松开以导入',
    this.hint = '支持 zip / jar / 游戏本体',
    this.icon = Icons.move_to_inbox_outlined,
  });

  final TemplateSkin skin;
  final bool active;
  final String title;
  final String? hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: skin.barrier.withAlpha(0.55 * 255 ~/ 1),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(TemplateSpace.xl),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(TemplateRadius.card),
                border: Border.all(color: skin.accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: skin.shadow,
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: TemplateSpace.sm,
                children: [
                  Icon(icon, size: 36, color: skin.accentText),
                  Text(
                    title,
                    style: TemplateType.section.copyWith(
                      color: skin.textPrimary,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
