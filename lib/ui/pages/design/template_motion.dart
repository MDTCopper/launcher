import 'package:copper_launcher/ui/components/animation/appear_item.dart';
import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/components/effect/border_progress.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 动效层：**不重复实现**，把项目里已有的动画组件包一层设计层默认值
///
/// - 交错入场 → [AppearItem]（`ui/components/animation/appear_item.dart`）
/// - 品牌加载 → [DrillLoading]（铜钻头，`ui/components/animation/loop/drill_loading.dart`）
/// - 描边进度 → [BorderProgress]（`ui/components/effect/border_progress.dart`）
/// - 页面转场 → [templatePageRoute]（设计层约定的时长与曲线）
///
/// 组件本身都支持换色 / 参数，这里只补皮肤色与设计层节奏（220ms / easeOutCubic 一类）
class TemplateAppear extends StatelessWidget {
  const TemplateAppear({
    super.key,
    required this.child,
    this.index = 0,
    this.animate = true,
  });

  final Widget child;

  /// 第几项：延迟按 40ms 递增（最多 8 项，免得末尾等太久）
  final int index;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return AppearItem(
      delayMs: (index.clamp(0, 8)) * 40,
      duration: const Duration(milliseconds: 220),
      offset: const Offset(0, 10),
      animate: animate,
      child: child,
    );
  }
}

/// 品牌加载态：铜钻头循环
///
/// 尺寸按场景取：整页加载 56~72，行内 / 按钮内 20~28
class TemplateDrillLoading extends StatelessWidget {
  const TemplateDrillLoading({
    super.key,
    required this.skin,
    this.size = 56,
    this.state = DrillLoadingState.spinning,
    this.cycle,
  });

  final TemplateSkin skin;
  final double size;
  final DrillLoadingState state;

  /// 走一步的时长，默认由组件自己给（1600ms）
  final Duration? cycle;

  @override
  Widget build(BuildContext context) {
    return DrillLoading(
      size: size,
      state: state,
      cycle: cycle ?? const Duration(milliseconds: 1600),
      hubColor: skin.accent,
      errorColor: skin.dangerText,
    );
  }
}

/// 描边进度：沿组件外沿画一圈进度（按钮下载 / 卡片刷新用）
class TemplateBorderProgress extends StatelessWidget {
  const TemplateBorderProgress({
    super.key,
    required this.skin,
    required this.progress,
    required this.child,
    this.borderRadius,
    this.strokeWidth = 2,
  });

  final TemplateSkin skin;

  /// 0~1；null = 不确定态（只画轨道）
  final double? progress;
  final Widget child;
  final BorderRadius? borderRadius;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return BorderProgress(
      progress: progress,
      borderRadius:
          borderRadius ?? BorderRadius.circular(TemplateRadius.control),
      strokeWidth: strokeWidth,
      trackColor: skin.border,
      progressColor: skin.accent,
      child: child,
    );
  }
}

/// 数字滚动：从旧值滑到新值（下载量、计数类展示用）
class TemplateAnimatedCounter extends StatelessWidget {
  const TemplateAnimatedCounter({
    super.key,
    required this.skin,
    required this.value,
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 600),
  });

  final TemplateSkin skin;
  final double value;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => Text(
        '${_format(animated)}$suffix',
        style: style ?? TemplateType.item.copyWith(color: skin.textPrimary),
      ),
    );
  }

  /// 千分位；超过一万就用 `x.x 万`（中文界面里比 `126,900` 好读）
  static String _format(double value) {
    final rounded = value.round();
    if (rounded >= 10000) {
      final wan = value / 10000;
      return '${wan.toStringAsFixed(wan >= 10 ? 1 : 2)} 万';
    }
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// 设计层统一的页面转场：淡入 + 轻微上移（200ms / easeOutCubic，返回 160ms）
Route<T> templatePageRoute<T>(
  WidgetBuilder builder, {
  Duration duration = const Duration(milliseconds: 200),
  Duration reverseDuration = const Duration(milliseconds: 160),
}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
