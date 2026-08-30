import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:flutter/material.dart';

class NavigationTile extends StatefulWidget {
  final Icon icon;
  final String content;
  final String? lable;
  final String? hint;
  final VoidCallback onTap;
  final bool selected;
  final bool collapse;
  final HintPosition hintPosition;

  const NavigationTile({
    super.key,
    required this.icon,
    required this.content,
    this.lable,
    this.hint,
    required this.onTap,
    this.selected = false,
    this.collapse = false,
    this.hintPosition = .auto,
  });
  @override
  State<StatefulWidget> createState() => NavigationTileState();
}

class NavigationTileState extends State<NavigationTile>
    with TickerProviderStateMixin {
  late final AnimationController controller;

  /// 收纳动画：宽度 + 透明度，由 tile 自身 State 持有。
  /// 不依赖 AnimatedSize 的渲染状态（组成更新导致其元素重建时会重置、瞬间跳变），
  /// controller 值在 State 里不丢，收纳动画稳定。
  late final AnimationController collapseController;
  late final Animation<double> collapseAnim;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..value = widget.selected ? 1.0 : .0;

    collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..value = widget.collapse ? 0.0 : 1.0;
    collapseAnim = collapseController.drive(CurveTween(curve: Curves.ease));
  }

  @override
  void dispose() {
    controller.dispose();
    collapseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected) {
      controller.forward();
    } else {
      controller.reverse();
    }
    if (widget.collapse) {
      collapseController.reverse();
    } else {
      collapseController.forward();
    }
  }

  Widget _buildTile() {
    final theme = Theme.of(context);

    Widget child;
    if (widget.lable != null) {
      child = Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text(widget.content, overflow: .ellipsis),
          DefaultTextStyle(
            style: theme.textTheme.labelSmall ?? TextStyle(),
            maxLines: 1,
            overflow: .ellipsis,
            child: Text(widget.lable!),
          ),
        ],
      );
    } else {
      child = Text(widget.content);
    }

    return child;
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context);
    final theme = Theme.of(context);
    final backgroundColorT = ColorTween(
      begin: color.interactive.withAlpha(0),
      end: color.interactive.withAlpha(45),
    ).animate(controller);
    final itemColorT = ColorTween(
      begin: color.itemPrimary,
      end: color.interactive,
    ).animate(controller);

    Widget child = AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final itemColor = itemColorT.value;
        final backgroundColor = backgroundColorT.value;
        return ReboundButton(
          pressedScale: 0.9,
          elevation: 0.0,
          hoverElevation: 0.0,
          padding: EdgeInsets.all(8),
          borderRadius: BorderRadius.circular(8),
          backgroundColor: backgroundColor,
          onTap: widget.onTap,
          child: IconTheme(
            data: IconTheme.of(context).copyWith(color: itemColor),
            child: DefaultTextStyle(
              maxLines: 1,
              style: theme.textTheme.labelLarge!.copyWith(
                color: itemColor,
                overflow: .ellipsis,
                fontWeight: widget.selected
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              child: child!,
            ),
          ),
        );
      },
      child: Row(
        children: [
          widget.icon,
          Expanded(
            child: Padding(
              padding: EdgeInsetsGeometry.only(left: 8),
              // 收纳：文字被裁剪、同时暗淡下去。
              // 用自身 collapseController 驱动：Expanded(紧) 铺满、ConstrainedBox(maxWidth)
              // 收敛文本宽度（超出被文本 ellipsis / ClipRect 裁掉）、Opacity 暗淡。
              // 不依赖 AnimatedSize 的渲染状态，组成更新时 controller 值不丢、不跳变
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedBuilder(
                    animation: collapseAnim,
                    builder: (context, child) => ClipRect(
                      child: Opacity(
                        opacity: collapseAnim.value,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * collapseAnim.value,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                    child: _buildTile(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );

    child = HintLayer(
      hint: widget.collapse ? (widget.hint ?? widget.content) : null,
      child: child,
    );

    return child;
  }
}
