import 'package:copper_launcher/ui/components/core/copper_pressable.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 兼容外壳：历史调用点很多，内部已改成 [CopperPressable]（变色、不缩放）
///
/// 2026-11-09 起按压反馈统一为「变色」：整块缩放会导致行内分隔线跟着缩、
/// 密集列表排版不稳，所以 [pressedScale] / [hoverElevation] / [elevation] /
/// [hoverDuration] 只做兼容，不再生效；需要轻微回弹的独立按钮由上层单独处理。
///
/// 其余参数语义保持不变：
/// - [backgroundColor] 底色（null 取卡片底色）
/// - [hoverColor] 悬停叠加色，[splashColor] 按下色
/// - [surfaceChild] 交互隔离层，叠在表面，点击不触发本层 [onTap]
/// - [shapeBorder] 形状（与 [borderRadius] 二选一）
class ReboundContainer extends StatelessWidget {
  final double? pressedScale;
  final Duration? duration; // 兼容保留，不再生效
  final Widget? child;

  /// 交互隔离层：叠在按钮表面，其中的组件接收自己的交互，
  /// 点击不会透传到 [onTap]
  final Widget? surfaceChild;

  /// [surfaceChild] 在按钮区域内的对齐方式
  final AlignmentGeometry surfaceAlignment;

  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongTap;

  final BorderRadius? borderRadius;
  final ShapeBorder? shapeBorder;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  final double hoverElevation;
  final double elevation;
  final Color? hoverColor;

  final Color? splashColor;
  final Color? highlightColor;
  final Color? backgroundColor;
  final Color? shadowColor;

  /// 兼容保留，不再生效
  final Duration hoverDuration;

  const ReboundContainer({
    super.key,
    this.pressedScale = 0.90,
    this.duration = const Duration(milliseconds: 160),
    this.child,
    this.surfaceChild,
    this.surfaceAlignment = Alignment.center,
    this.onTap,
    this.onLongTap,
    this.shapeBorder,
    this.borderRadius,
    this.hoverColor,
    this.splashColor,
    this.highlightColor,
    this.backgroundColor,
    this.shadowColor,
    this.hoverElevation = 0.0,
    this.elevation = 0.0,
    this.padding,
    this.margin,
    this.hoverDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final background = backgroundColor ?? colors.cardBackground;

    Widget content = child ?? const SizedBox.shrink();
    if (surfaceChild != null) {
      content = Stack(
        alignment: Alignment.center,
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned.fill(
            child: Align(alignment: surfaceAlignment, child: surfaceChild),
          ),
        ],
      );
    }

    Widget pressable = CopperPressable(
      onTap: onTap,
      onLongTap: onLongTap,
      borderRadius: borderRadius,
      padding: padding,
      margin: margin,
      backgroundColor: shapeBorder == null ? background : Colors.transparent,
      hoverColor: hoverColor,
      pressedColor: splashColor ?? highlightColor,
      child: content,
    );

    if (shapeBorder == null) return pressable;

    return DecoratedBox(
      decoration: ShapeDecoration(color: background, shape: shapeBorder!),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shapeBorder!),
        child: pressable,
      ),
    );
  }
}
