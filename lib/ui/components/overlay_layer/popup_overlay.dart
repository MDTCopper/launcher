import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 浮层相对锚点的方位（用于动画方向适配）。
enum PopupOverlayAnchorPosition { bottomRight, bottomLeft, topRight, topLeft }

/// 定位数据：浮层布局完成后生成，传给动画接口，让动画能感知最终位置。
class PopupOverlayPlacement {
  const PopupOverlayPlacement({
    required this.anchorRect,
    required this.position,
    required this.overlaySize,
    required this.childSize,
    required this.anchorOffset,
  });

  /// 锚点矩形（overlay 坐标）。
  final Rect anchorRect;

  /// 浮层左上角在 overlay 中的位置。
  final Offset position;

  /// overlay 尺寸。
  final Size overlaySize;

  /// 浮层尺寸。
  final Size childSize;

  /// 锚点内偏移（打开时传入的 position，如鼠标相对锚点的位置）。
  final Offset anchorOffset;

  /// 浮层相对锚点的方位。
  PopupOverlayAnchorPosition get anchorPosition {
    final rightOfAnchor = position.dx >= anchorRect.center.dx;
    final belowAnchor = position.dy >= anchorRect.center.dy;
    if (rightOfAnchor) {
      return belowAnchor
          ? PopupOverlayAnchorPosition.bottomRight
          : PopupOverlayAnchorPosition.topRight;
    }
    return belowAnchor
        ? PopupOverlayAnchorPosition.bottomLeft
        : PopupOverlayAnchorPosition.topLeft;
  }

  /// 锚点（鼠标）在浮层内的位置转缩放锚点：
  /// 浮层无论因翻转 / 贴边偏移多远，缩放都从锚点位置生长。
  Alignment get anchorAlignment {
    final local = anchorRect.topLeft + anchorOffset - position;
    final dx = childSize.width <= 0
        ? 0.0
        : ((local.dx / childSize.width) * 2 - 1).clamp(-1.0, 1.0);
    final dy = childSize.height <= 0
        ? 0.0
        : ((local.dy / childSize.height) * 2 - 1).clamp(-1.0, 1.0);
    return Alignment(dx, dy);
  }
}

/// 浮层动画接口。
///
/// 接收动画进度与定位数据 [placement]，可按实际方位适配
/// （如缩放的锚点、滑动的方向）。[placement] 在浮层布局完成后才确定。
typedef PopupOverlayAnimationBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Widget child,
      PopupOverlayPlacement? placement,
    );

/// 淡入淡出（PopupOverlay 默认动画）。
Widget _fadeAnimation(
  BuildContext context,
  Animation<double> animation,
  Widget child,
  PopupOverlayPlacement? placement,
) {
  return FadeTransition(opacity: animation, child: child);
}

/// 浮层位置策略：决定浮层相对锚点摆放在哪里。
///
/// 在布局阶段调用，[childSize] 由布局管道提供，无需预测量。
abstract class PopupOverlayPositionDelegate {
  const PopupOverlayPositionDelegate();

  /// 计算浮层位置（overlay 坐标）。
  ///
  /// [position] 为打开时传入的锚点内偏移（可能为 null）。
  Offset getPosition({
    required Rect anchorRect,
    required Offset? position,
    required Size overlaySize,
    required Size childSize,
    required EdgeInsets padding,
  });

  /// 位置策略是否发生变化（对应 shouldRelayout）。
  bool shouldReposition(PopupOverlayPositionDelegate oldDelegate);
}

/// 默认位置策略：以锚点内偏移（或锚点右下角）为起点展开，
/// 超出屏幕边界自动翻转，兜底贴安全边距内。
class AnchorFlipPositionDelegate extends PopupOverlayPositionDelegate {
  const AnchorFlipPositionDelegate();

  @override
  Offset getPosition({
    required Rect anchorRect,
    required Offset? position,
    required Size overlaySize,
    required Size childSize,
    required EdgeInsets padding,
  }) {
    final anchorOrigin = anchorRect.topLeft;

    // 起点：优先用传入的锚点内偏移（鼠标 / 长按位置），否则锚点右下角
    var left = (position?.dx ?? anchorRect.width) + anchorOrigin.dx;
    var top = (position?.dy ?? anchorRect.height) + anchorOrigin.dy;

    // 水平翻转：放不下则收回到屏幕内
    if (left + childSize.width > overlaySize.width - padding.right) {
      left = overlaySize.width - padding.right - childSize.width;
    }
    // 垂直翻转：放不下则上移（先尝试锚点上方，仍放不下则贴底）
    if (top + childSize.height > overlaySize.height - padding.bottom) {
      top = anchorOrigin.dy - childSize.height;
      if (top < padding.top) {
        top = overlaySize.height - padding.bottom - childSize.height;
      }
    }

    // 兜底：保证不越出安全边距（浮层比屏幕大时贴边显示）
    left = left
        .clamp(
          padding.left,
          math.max(
            padding.left,
            overlaySize.width - padding.right - childSize.width,
          ),
        )
        .toDouble();
    top = top
        .clamp(
          padding.top,
          math.max(
            padding.top,
            overlaySize.height - padding.bottom - childSize.height,
          ),
        )
        .toDouble();

    return Offset(left, top);
  }

  @override
  bool shouldReposition(PopupOverlayPositionDelegate oldDelegate) =>
      oldDelegate is! AnchorFlipPositionDelegate;
}

/// 弹出浮层控制器。
///
/// 由 [PopupOverlay] 关联（传入 `controller` 或让 [PopupOverlay] 内部创建），
/// 用于控制浮层的打开 / 关闭。
class PopupOverlayController {
  _PopupOverlayState? _state;

  /// 浮层当前是否显示。
  bool get isShowing => _state?._overlayController.isShowing ?? false;

  void _attach(_PopupOverlayState state) => _state = state;
  void _detach() => _state = null;

  /// 打开浮层。
  ///
  /// [position] 为相对锚点（[PopupOverlay.child] 区域）的偏移，
  /// 通常传入手势事件的 `localPosition`，即可从精确的鼠标 / 长按位置弹出。
  void open({Offset? position}) => _state?._open(position: position);

  /// 关闭浮层（播放退场动画后移除）。
  ///
  /// [immediate] 为 true 时立即隐藏，不播放退场动画。
  Future<void> dismiss({bool immediate = false}) =>
      _state?._dismiss(immediate: immediate) ?? Future.value();
}

/// 在指定位置弹出浮层窗口，自动挑选合适位置，非对话框（无遮罩）。
///
/// 基于 [OverlayPortal] + [CustomSingleChildLayout] 实现：
/// - 锚点矩形由 [OverlayPortal.overlayChildLayoutBuilder] 的变换矩阵给出，无需手动测量
/// - 浮层尺寸由布局管道自然产生，无需 Offstage 预测量
/// - 入场 / 退场动画完整：打开时浮层为新实例播放入场，关闭时先播放退场再移除
///
/// 动画默认为淡入淡出，可通过 [animation] 注入自定义动画（能感知定位数据）；
/// 位置策略默认为 [AnchorFlipPositionDelegate]（点锚定 + 翻转），
/// 可通过 [positionDelegate] 替换（如 HintLayer 的环绕定位）。
class PopupOverlay extends StatefulWidget {
  /// 锚点组件：浮层相对此组件定位，[PopupOverlayController.open] 的 `position`
  /// 即相对此组件左上角的偏移。
  final Widget child;

  /// 浮层内容构建器，[anchorRect] 为锚点矩形（overlay 坐标），
  /// 可用于让浮层宽度对齐锚点（如下拉菜单）。
  final Widget Function(BuildContext context, Rect anchorRect)
  overlayChildBuilder;

  /// 外部控制器；为空时内部自动创建一个。
  final PopupOverlayController? controller;

  /// 浮层动画。默认为淡入淡出。
  final PopupOverlayAnimationBuilder? animation;

  /// 位置策略。默认为 [AnchorFlipPositionDelegate]。
  final PopupOverlayPositionDelegate? positionDelegate;

  /// 是否点击浮层外部关闭。
  final bool dismissOnTapOutside;

  /// 是否按 Esc 关闭。
  final bool dismissOnEsc;

  /// 浮层关闭后回调（点击外部 / Esc / 手动 dismiss 都会触发）。
  final VoidCallback? onClose;

  /// dismiss 开始（退场动画播放前）立即回调。
  ///
  /// 用于在关闭瞬间同步外部状态（如下拉菜单立即复位箭头 / 高亮），
  /// 而不必等退场动画结束。
  final VoidCallback? onDismissStart;

  /// 滚动外部（滚轮）是否自动关闭浮层。
  ///
  /// 开启后在浮层外的滚轮滚动会触发 dismiss。
  /// 注意：浮层打开时外部滚动被浮层层拦截（与点击外部一致），
  /// 关闭浮层后滚动恢复。
  final bool dismissOnScrollOutside;

  /// 浮层距屏幕边缘的最小安全距离。
  final EdgeInsets screenPadding;

  /// 入场 / 退场动画时长。
  final Duration animationDuration;

  const PopupOverlay({
    super.key,
    required this.child,
    required this.overlayChildBuilder,
    this.controller,
    this.animation,
    this.positionDelegate,
    this.dismissOnTapOutside = true,
    this.dismissOnEsc = true,
    this.onClose,
    this.onDismissStart,
    this.dismissOnScrollOutside = false,
    this.screenPadding = const EdgeInsets.all(8),
    this.animationDuration = const Duration(milliseconds: 150),
  });

  @override
  State<PopupOverlay> createState() => _PopupOverlayState();
}

class _PopupOverlayState extends State<PopupOverlay> {
  late final PopupOverlayController _internalController =
      PopupOverlayController();
  late final OverlayPortalController _overlayController =
      OverlayPortalController();

  final GlobalKey<_PopupOverlayAnimationState> _animationKey = GlobalKey();

  /// 布局完成后生成的定位数据，供动画接口使用。
  final ValueNotifier<PopupOverlayPlacement?> _placement = ValueNotifier(null);

  /// 打开时的锚点内偏移（相对 [widget.child] 区域）。
  Offset? _position;

  /// 打开时的锚点矩形快照，用于检测锚点移动（滚动 / 页面切换）自动关闭。
  Rect? _anchorSnapshot;
  Size? _overlaySnapshot;

  /// 打开代数：每次 [open] 递增；[dismiss] 完成时若代数未变
  /// （期间未被重新打开），才真正隐藏浮层。
  int _generation = 0;

  /// 布局最大尺寸跟踪（每次打开重置）。
  final _SizeTracker _sizeTracker = _SizeTracker();

  PopupOverlayController get _effectiveController =>
      widget.controller ?? _internalController;

  void _open({Offset? position}) {
    _anchorSnapshot = null;
    _overlaySnapshot = null;
    _sizeTracker.max = null;
    _generation++;
    if (mounted) {
      setState(() => _position = position);
    }
    _overlayController.show();
    // 退场中再次 open（如 hint 快速进出）：中断退场并重新播放入场
    _animationKey.currentState?.restart();
  }

  Future<void> _dismiss({bool immediate = false}) async {
    widget.onDismissStart?.call();
    _anchorSnapshot = null;
    _overlaySnapshot = null;
    final gen = _generation;
    final anim = _animationKey.currentState;
    if (!immediate) {
      await anim?.playReverse();
    }
    // 退场期间被重新打开（代数已变）→ 不隐藏，保持显示
    if (mounted && gen == _generation) {
      _overlayController.hide();
      _placement.value = null;
      widget.onClose?.call();
    }
  }

  /// 每次布局回调：锚点被滚动或视图变化时自动关闭浮层，
  /// 避免浮层与锚点脱节（与 MenuAnchor 行为一致）。
  void _onAnchorChanged(Rect anchorRect, Size overlaySize) {
    if (_anchorSnapshot == null) {
      _anchorSnapshot = anchorRect;
      _overlaySnapshot = overlaySize;
      return;
    }
    if (anchorRect != _anchorSnapshot || overlaySize != _overlaySnapshot) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dismiss();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _effectiveController._attach(this);
  }

  @override
  void dispose() {
    _effectiveController._detach();
    _placement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlayChild,
      child: widget.child,
    );
  }

  Widget _buildOverlayChild(BuildContext context, OverlayChildLayoutInfo info) {
    // 锚点矩形：由变换矩阵映射，锚点被旋转 / 缩放 / 滚动也能正确定位
    final anchorRect = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );

    Widget content = Stack(
      children: [
        // 透明关闭层：点击浮层外部关闭，无视觉遮罩
        if (widget.dismissOnTapOutside)
          Positioned.fill(
            child: Listener(
              // 滚轮滚动外部时自动关闭（与点击外部一致）
              onPointerSignal: widget.dismissOnScrollOutside
                  ? (e) {
                      if (e is PointerScrollEvent) _dismiss();
                    }
                  : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _dismiss(),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        Positioned.fill(
          child: ConstrainedBox(
            constraints: BoxConstraints.loose(info.overlaySize),
            child: CustomSingleChildLayout(
              delegate: _PopupOverlayLayout(
                delegate:
                    widget.positionDelegate ??
                    const AnchorFlipPositionDelegate(),
                anchorRect: anchorRect,
                position: _position,
                padding: widget.screenPadding,
                sizeTracker: _sizeTracker,
                onAnchorChanged: _onAnchorChanged,
                onPlaced: (placement) {
                  // 布局阶段不能触发通知（ValueListenableBuilder 会 setState），
                  // 延迟到 post-frame，动画 / 监听者此时更新是安全的。
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _placement.value = placement;
                  });
                },
              ),
              child: _PopupOverlayAnimation(
                key: _animationKey,
                duration: widget.animationDuration,
                animation: widget.animation ?? _fadeAnimation,
                placement: _placement,
                child: Builder(
                  builder: (ctx) => widget.overlayChildBuilder(ctx, anchorRect),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.dismissOnEsc) {
      content = Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _dismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: content,
      );
    }

    return content;
  }
}

/// 内部定位委托：适配 [PopupOverlayPositionDelegate] 到 [SingleChildLayoutDelegate]，
/// 并在定位完成后产出 [PopupOverlayPlacement]。
/// 布局尺寸跟踪：记录历次布局的最大 childSize。
/// 展开动画中 childSize 渐增（如高度展开），定位始终基于最大（完整）尺寸，
/// 避免动画过程位置漂移（展开结束偏移、收纳时偏移回去）。
class _SizeTracker {
  Size? max;
}

class _PopupOverlayLayout extends SingleChildLayoutDelegate {
  final PopupOverlayPositionDelegate delegate;
  final Rect anchorRect;
  final Offset? position;
  final EdgeInsets padding;
  final ValueChanged<PopupOverlayPlacement> onPlaced;

  /// 每次布局时回调当前锚点矩形与 overlay 尺寸，用于检测锚点移动。
  final void Function(Rect anchorRect, Size overlaySize)? onAnchorChanged;

  /// 跨布局共享的最大尺寸跟踪（动画尺寸渐增时定位稳定）。
  final _SizeTracker sizeTracker;

  const _PopupOverlayLayout({
    required this.delegate,
    required this.anchorRect,
    required this.position,
    required this.padding,
    required this.onPlaced,
    required this.sizeTracker,
    this.onAnchorChanged,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // 高度限制在 overlay 内（配合内容滚动，防止超窗）；
    // 宽度放开，让浮层收缩到内容宽度——否则 SizeTransition 内部的
    // Align（widthFactor 为 null）会在有限宽度约束下撑满，导致定位失真。
    final maxHeight = constraints.loosen().deflate(padding).maxHeight;
    return BoxConstraints(
      maxWidth: double.infinity,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    onAnchorChanged?.call(anchorRect, size);
    // 定位基于最大（完整）尺寸：动画中 childSize 渐增，位置不随动画漂移
    final prev = sizeTracker.max;
    if (prev == null ||
        childSize.height > prev.height ||
        childSize.width > prev.width) {
      sizeTracker.max = childSize;
    }
    final effective = sizeTracker.max ?? childSize;
    final offset = delegate.getPosition(
      anchorRect: anchorRect,
      position: position,
      overlaySize: size,
      childSize: effective,
      padding: padding,
    );
    onPlaced(
      PopupOverlayPlacement(
        anchorRect: anchorRect,
        position: offset,
        overlaySize: size,
        childSize: childSize,
        anchorOffset: position ?? Offset(anchorRect.width, anchorRect.height),
      ),
    );
    return offset;
  }

  @override
  bool shouldRelayout(_PopupOverlayLayout oldDelegate) =>
      oldDelegate.anchorRect != anchorRect ||
      oldDelegate.position != position ||
      oldDelegate.padding != padding ||
      delegate.shouldReposition(oldDelegate.delegate);
}

/// 浮层动画层：打开时播放入场，关闭时由 [playReverse] 播放退场。
class _PopupOverlayAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final PopupOverlayAnimationBuilder animation;
  final ValueListenable<PopupOverlayPlacement?> placement;

  const _PopupOverlayAnimation({
    super.key,
    required this.child,
    required this.duration,
    required this.animation,
    required this.placement,
  });

  @override
  State<_PopupOverlayAnimation> createState() => _PopupOverlayAnimationState();
}

class _PopupOverlayAnimationState extends State<_PopupOverlayAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    // 入场动画等 placement（布局后的定位数据）就绪后再播放：
    // - 确保动画接口能拿到正确的锚点信息（如 HintLayer 的实际方位）
    // - 延迟到 post-frame，避免在 build / 布局期间启动动画
    widget.placement.addListener(_onPlacementReady);
  }

  void _onPlacementReady() {
    if (widget.placement.value == null || !_controller.isDismissed) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.placement.value != null &&
          _controller.isDismissed) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    widget.placement.removeListener(_onPlacementReady);
    _controller.dispose();
    super.dispose();
  }

  /// 播放退场动画，返回时动画已完成。
  Future<void> playReverse() async {
    if (_controller.value > 0) {
      await _controller.reverse();
    }
  }

  /// 退场 / 入场中重新打开：反转入场——从当前退场位置倒回显示，
  /// 动画连贯（不从头重放）。placement 未就绪（首次打开）时由
  /// [_onPlacementReady] 处理。
  void restart() {
    if (widget.placement.value == null) return;
    if (!_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PopupOverlayPlacement?>(
      valueListenable: widget.placement,
      builder: (context, placement, _) {
        final curve = CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return widget.animation(context, curve, widget.child, placement);
      },
    );
  }
}
