import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/material.dart';

/// 分段按钮组：多段互斥 / 多选，选中段有背景 + 前景过渡动画。
///
/// copper 风格双模式：
/// - 暗色：玻璃感——透明背景，选中态叠一层半透明主题色
/// - 浅色：云母片——不透明背景，选中态用 alphaBlend 模拟半透明主题色
class SegmentedReboundButton<T> extends StatefulWidget {
  const SegmentedReboundButton({
    super.key,
    required this.segments,
    this.multiSelectionEnabled = false,
    required this.onChange,
    required this.selected,
  });

  final List<ReboundButtonSegment<T>> segments;
  final bool multiSelectionEnabled;
  final void Function(Set<T>) onChange;
  final Set<T> selected;

  @override
  State<StatefulWidget> createState() => _SegmentedReboundButtonState<T>();
}

class _SegmentedReboundButtonState<T> extends State<SegmentedReboundButton<T>> {
  void _onTap(T value) {
    if (widget.multiSelectionEnabled) {
      final set = widget.selected.toSet();
      if (set.contains(value)) {
        set.remove(value);
      } else {
        set.add(value);
      }
      widget.onChange.call(set);
    } else {
      widget.onChange.call({value});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.contentBorder),
        color: colors.inputBackground,
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: widget.segments.map<Widget>((it) {
          return SegmentedReboundSingleButton<T>(
            selected: widget.selected.contains(it.value),
            onTap: () => _onTap(it.value),
            child: Row(
              spacing: 4,
              children: [
                if (it.icon != null) it.icon!,
                if (it.content != null) Text(it.content!),
                if (it.label != null) it.label!,
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 分段数据描述：值 + 可选的内容 / 图标 / 自定义 label
class ReboundButtonSegment<T> {
  ReboundButtonSegment({
    required this.value,
    this.content,
    this.icon,
    this.label,
    this.enabled = true,
  }) : assert(content != null || label != null);

  final T value;
  final String? content;
  final Widget? icon;
  final Widget? label;
  final bool enabled;
}

/// 单个分段按钮：自持 [AnimationController]，选中/取消由 [selected] 驱动过渡
class SegmentedReboundSingleButton<T> extends StatefulWidget {
  const SegmentedReboundSingleButton({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Widget child;
  final VoidCallback onTap;

  @override
  State<StatefulWidget> createState() => _SegmentedReboundSingleButtonState();
}

class _SegmentedReboundSingleButtonState<T>
    extends State<SegmentedReboundSingleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: animationDuration);
    if (widget.selected) controller.animateTo(1.0);
  }

  @override
  void didUpdateWidget(covariant SegmentedReboundSingleButton oldWidget) {
    if (widget.selected) {
      if (!controller.isForwardOrCompleted) {
        controller.forward();
      }
    } else {
      if (controller.isForwardOrCompleted) {
        controller.reverse();
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBackground = colors.cardBackground;

    final beginBackground = isDark
        ? colors.interactive.withAlpha(0)
        : cardBackground;

    final endBackground = isDark
        ? colors.interactive.withAlpha(45)
        : Color.alphaBlend(colors.interactive.withAlpha(45), cardBackground);
    final backgroundT = ColorTween(
      begin: beginBackground,
      end: endBackground,
    ).animate(controller);

    // 前景：未选中 itemPrimary → 选中 interactiveHigh
    final foregroundT = ColorTween(
      begin: colors.itemPrimary,
      end: colors.interactive,
    ).animate(controller);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return ReboundContainer(
          pressedScale: 0.9,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          hoverElevation: 2,
          elevation: 0,
          backgroundColor: backgroundT.value,
          borderRadius: BorderRadius.circular(4),
          onTap: widget.onTap,
          child: DefaultTextStyle(
            style:
                theme.textTheme.bodyLarge?.copyWith(color: foregroundT.value) ??
                const TextStyle(),
            child: IconTheme(
              data: theme.iconTheme.copyWith(color: foregroundT.value),
              child: child!,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
