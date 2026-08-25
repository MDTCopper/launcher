import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 列表项（类似 ListTile），基于 [ReboundContainer]。
///
/// - 有选中态：[selected] 驱动背景 / 前景的过渡动画（双模式背景同 [ActionButton]）
/// - 有禁用态：[enable] 为 false 时不可点击、无浮出、前景置灰
/// - 结构：leading / title / subtitle / trailing
class ReboundListTile extends StatefulWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final bool selected;
  final bool enable;
  final double elevation;
  final double hoverElevation;
  final double pressedScale;
  final Color? baseColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double itemSpacing;

  const ReboundListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongTap,
    this.selected = false,
    this.enable = true,
    this.elevation = 1,
    this.hoverElevation = 6,
    this.baseColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.margin,
    this.borderRadius,
    this.itemSpacing = 8,
    this.pressedScale = 0.95,
  });

  @override
  State<StatefulWidget> createState() => _ReboundListTileState();
}

class _ReboundListTileState extends State<ReboundListTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _trailingKey = GlobalKey();

  double _trailingWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.selected) _controller.value = 1.0;
    _measureTrailingWidth();
  }

  void _measureTrailingWidth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _trailingKey.currentContext;
      final width = context?.size?.width ?? 0;
      if (width != _trailingWidth) {
        setState(() => _trailingWidth = width);
      }
      _measureTrailingWidth();
    });
  }

  @override
  void didUpdateWidget(covariant ReboundListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (widget.selected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = widget.baseColor ?? colors.cardBackground;
    final enabled = widget.enable;

    final beginBackground = baseColor;
    final endBackground = isDark
        ? colors.interactive.withAlpha(100)
        : Color.alphaBlend(colors.interactive.withAlpha(100), baseColor);
    final backgroundT = ColorTween(
      begin: beginBackground,
      end: endBackground,
    ).animate(_controller);

    // 前景：禁用置灰；未选中 itemPrimary → 选中 interactive
    final foregroundT = ColorTween(
      begin: enabled ? colors.itemPrimary : colors.itemHint,
      end: enabled ? colors.interactive : colors.itemHint,
    ).animate(_controller);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final foreground = foregroundT.value;
        return ReboundContainer(
          pressedScale: widget.pressedScale,
          elevation: widget.elevation,
          hoverElevation: enabled ? widget.hoverElevation : widget.elevation,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          padding: widget.padding,
          margin: widget.margin,
          backgroundColor: backgroundT.value,
          onTap: enabled ? widget.onTap : null,
          onLongTap: enabled ? widget.onLongTap : null,
          // trailing 进 surfaceChild：交互隔离
          // 挂在 GlobalKey 上帧后实测宽度，行内按 _trailingWidth 预留占位
          surfaceChild: widget.trailing == null
              ? null
              : KeyedSubtree(key: _trailingKey, child: widget.trailing!),
          surfaceAlignment: Alignment.centerRight,
          child: IconTheme(
            data: IconTheme.of(context).copyWith(color: foreground),
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  SizedBox(width: widget.itemSpacing),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: theme.textTheme.titleMedium!.copyWith(
                          color: foreground,
                        ),
                        child: widget.title ?? const SizedBox.shrink(),
                      ),
                      if (widget.subtitle != null)
                        DefaultTextStyle(
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.itemSecondary,
                          ),
                          child: widget.subtitle!,
                        ),
                    ],
                  ),
                ),
                if (_trailingWidth > 0) SizedBox(width: _trailingWidth),
              ],
            ),
          ),
        );
      },
    );
  }
}
