import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ReboundContainer extends StatefulWidget {
  final double? pressedScale;
  final Duration? duration; // 回弹持续时间
  final Widget? child;

  /// 交互隔离层：叠在按钮表面，其中的组件接收自己的交互，
  /// 点击不会透传到 InkWell，不会触发按钮回弹。
  final Widget? surfaceChild;

  /// [surfaceChild] 在按钮区域内的对齐方式。
  final AlignmentGeometry surfaceAlignment;

  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongTap;

  final BorderRadius? borderRadius;
  final ShapeBorder? shapeBorder; // 高亮覆盖层修饰
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  final double hoverElevation;
  final double elevation;
  final Color? hoverColor;

  final Color? splashColor;
  final Color? highlightColor;
  final Color? backgroundColor;
  final Color? shadowColor;

  /// 悬浮色渐变时长，默认 200ms
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
  State<StatefulWidget> createState() => _ReboundContainer();
}

class _ReboundContainer extends State<ReboundContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _pressScale;

  bool isPressed = false;
  bool isHover = false;

  GestureTapDownCallback? onTapDown;
  GestureTapUpCallback? onTapUp;
  VoidCallback? onTapCancel;
  GestureLongPressCallback? onLongTap;
  ValueChanged<bool>? onHover;

  @override
  void initState() {
    super.initState();

    // 按压回弹
    _pressController =
        AnimationController(vsync: this, duration: widget.duration)
          ..addStatusListener((state) {
            if (!isPressed && !state.isAnimating) {
              _pressController.reverse();
            }
          });
    _pressScale = Tween(
      begin: 1.0,
      // 兜底：调用方可能传 null（如 ReboundButton 未指定 pressedScale）
      end: widget.pressedScale ?? 0.90,
    ).animate(CurvedAnimation(parent: _pressController, curve: Curves.ease));

    // 悬浮监听
    onHover = (hover) {
      setState(() {
        isHover = hover;
      });
    };

    // 按压
    if (widget.onTap != null) {
      onTapDown = (_) {
        setState(() {
          isPressed = true;
          if (!_pressController.isForwardOrCompleted) {
            _pressController.forward();
          }
        });
      };

      onTapUp = (_) {
        setState(() {
          isPressed = false;
          if (!_pressController.isAnimating) {
            _pressController.reverse();
          }
        });
        widget.onTap?.call();
      };

      onTapCancel = () {
        setState(() {
          isPressed = false;
          if (!_pressController.isAnimating) {
            _pressController.reverse();
          }
        });
      };
    }

    if (widget.onLongTap != null) {
      onLongTap = () {
        setState(() {
          isPressed = false;
          if (!_pressController.isForwardOrCompleted) {
            _pressController.forward();
          }
        });
        widget.onLongTap?.call();
      };
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor =
        widget.backgroundColor ?? AppColors.of(context).cardBackground;
    theme.colorScheme.secondaryContainer;

    final hoverColor =
        widget.hoverColor ?? AppColors.of(context).splash.withAlpha(30);

    final light = theme.brightness == Brightness.light;

    final double elevation;

    //亮色且背景不透明情况下触发elevation
    if (light && backgroundColor.a != 255) {
      if (isHover && !isPressed) {
        elevation = widget.hoverElevation;
      } else {
        elevation = widget.elevation;
      }
    } else {
      elevation = 0.0;
    }

    Widget? child = widget.child;
    var surfaceChild = widget.surfaceChild;
    if (widget.padding != null) {
      child = Padding(padding: widget.padding!, child: widget.child);
      surfaceChild = Padding(
        padding: widget.padding!,
        child: widget.surfaceChild,
      );
    }

    child = ScaleTransition(
      alignment: Alignment.center,
      scale: _pressScale,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.passthrough,
        children: [
          Material(
            borderRadius: widget.borderRadius,
            shape: widget.shapeBorder,
            color: backgroundColor,
            shadowColor: widget.shadowColor,
            elevation: elevation,
            child: InkWell(
              autofocus: true,
              borderRadius: widget.borderRadius,
              customBorder: widget.shapeBorder,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: widget.highlightColor,
              splashColor: widget.splashColor,
              onTapDown: onTapDown,
              onTapUp: onTapUp,
              onTapCancel: onTapCancel,
              onLongPress: onLongTap, // 之前漏接：onLongTap 从未接线到 InkWell，长按不生效
              onHover: onHover,
              child: child,
            ),
          ),
          if (surfaceChild != null)
            Positioned.fill(
              child: Align(
                alignment: widget.surfaceAlignment,
                child: surfaceChild,
              ),
            ),
          //todo 墨水层实现脱离，用MaterialInkController操控墨水
          // 悬浮叠加层 —— 用动画控制透明度，暗色模式也能看见
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: widget.hoverDuration,
                curve: Curves.ease,
                decoration: BoxDecoration(
                  color: isHover ? hoverColor : hoverColor.withAlpha(0),
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.margin != null) {
      child = Padding(padding: widget.margin!, child: child);
    }

    return child;
  }
}
