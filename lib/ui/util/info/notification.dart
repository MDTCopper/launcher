import 'dart:async';
import 'dart:ui';

import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

void addNotice({
  IconData? icon,
  String? title,
  String? content,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 3),
}) => NotificationManager.addNotice(
  content: content,
  title: title,
  icon: icon,
  onTap: onTap,
  duration: duration,
);

void addNoticeWidget({
  required Widget widget,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 3),
}) => NotificationManager.addNoticeWidget(
  widget: widget,
  onTap: onTap,
  duration: duration,
);

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._();
  factory NotificationManager() => _instance;
  NotificationManager._(); //保持单例

  static final _globalKey = GlobalKey<_NotificationWidgetState>();
  static final NotificationWidget _widget = NotificationWidget(
    key: _globalKey,
    onDismiss: () {
      try {
        if (_overlayEntry?.mounted ?? false) _overlayEntry?.remove();
      } catch (e) {
        return;
      }
    },
  );

  static OverlayEntry? _overlayEntry;

  static void addNotice({
    BuildContext? context,
    IconData? icon,
    String? title,
    String? content,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 3),
  }) async {
    context ??= PageKeyProvider.shellKey.currentContext;
    await _show(context!).then((_) {
      _globalKey.currentState!.addItem(icon, title, content, onTap, duration);
    });
  }

  static void addNoticeWidget({
    BuildContext? context,
    required Widget widget,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 3),
  }) async {
    context ??= PageKeyProvider.shellKey.currentContext;
    await _show(context!).then((_) {
      _globalKey.currentState!.addItemWidget(widget, onTap, duration);
    });
  }

  static Future<void> _show(BuildContext context) async {
    if (_overlayEntry == null || !(_overlayEntry?.mounted ?? false)) {
      _overlayEntry = OverlayEntry(
        builder: (_) {
          return Positioned(top: 56, left: 0, child: _widget);
        },
      );
      Overlay.of(context).insert(_overlayEntry!);
      await WidgetsBinding.instance.endOfFrame; //等待第一帧加载
    }
  }
}

class NotificationWidget extends StatefulWidget {
  final VoidCallback onDismiss;

  const NotificationWidget({super.key, required this.onDismiss});

  @override
  State<StatefulWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<NotificationWidget> {
  final _uuid = const Uuid();

  final List<_NoticeData> _itemList = [];

  void addItem(
    IconData? icon,
    String? title,
    String? content,
    VoidCallback? onTap,
    Duration duration,
  ) {
    final theme = Theme.of(context);
    Widget widget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(icon, size: 28),
            if (title != null)
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        if (content != null) Text(content, style: theme.textTheme.bodyMedium),
      ],
    );

    widget = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2, tileMode: TileMode.mirror),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
        child: widget,
      ),
    );

    widget = Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 12),
        child: Material(
          color: Colors.transparent,
          elevation: 4,
          clipBehavior: Clip.hardEdge,
          child: widget,
        ),
      ),
    );
    addItemWidget(widget, onTap, duration);
  }

  void addItemWidget(Widget widget, VoidCallback? onTap, Duration duration) {
    setState(() {
      _itemList.add(_NoticeData(_uuid.v4(), widget, onTap, duration));
    });
  }

  /// 移除指定 id 的通知（定时器 / 左滑删除按钮 / 点击共同入口）。
  void _removeById(String id) {
    final index = _itemList.indexWhere((item) => item.id == id);
    if (index < 0) return;
    setState(() {
      _itemList.removeAt(index);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _itemList)
            Align(
              // key 必须放在 Column 直接 children 层：若 key 藏在包装内部，
              // 移除条目后按 index 匹配包装层（Align 无 key），
              // 深层 _NoticeItem 会被重建并重播入场动画。
              key: ValueKey(item.id),
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 12),
                child: _NoticeItem(
                  item: item,
                  onRemove: () => _removeById(item.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 通知条目：自持入场 / 退场动画 + 左滑删除。
///
/// - **入场**：仅 左滑入 + 淡入（无展开动画），播完保持显示
/// - **退场**：分段 —— 点击先缩小（scale 1.0→0.92）→ 停顿 → 划出+淡出 →
///   最后占位收缩（SizeTransition，下方通知才上移）
/// - **左滑删除**：跟手左移，超过 [dismissDistance] 松手即退场删除；
///   未超阈值松手回弹恢复（无删除背景层）
/// - 定时器到期也走同一退场路径，`onRemove` 只在退场动画结束后触发一次
class _NoticeItem extends StatefulWidget {
  final _NoticeData item;
  final VoidCallback onRemove;

  const _NoticeItem({required this.item, required this.onRemove});

  @override
  State<_NoticeItem> createState() => _NoticeItemState();
}

class _NoticeItemState extends State<_NoticeItem>
    with TickerProviderStateMixin {
  static const _kEnterDuration = Duration(milliseconds: 280);
  static const _kPressDuration = Duration(milliseconds: 300);
  static const _kSwipeDuration = Duration(milliseconds: 300);
  static const _kShrinkDuration = Duration(milliseconds: 200);
  static const _kPressWait = Duration(milliseconds: 100);

  // ── 动画曲线（每阶段显式指定，视觉节奏可控）──
  /// 入场滑入：带轻微回弹的 spring 感（从左侧滑入）。
  static const Curve _kEnterPositionCurve = Curves.easeOutBack;
  /// 入场淡入：快速的不透明度提升，避免长时间半透明。
  static const Curve _kEnterOpacityCurve = Curves.easeOutCubic;
  /// 点击缩小（按下感）：快速收拢到 0.92。
  static const Curve _kPressCurve = Curves.easeOutCubic;
  /// 划出 + 淡化：松开后加速飞出（从静止快速离开），有明确的"释放"感。
  static const Curve _kSwipeCurve = Curves.easeInCubic;
  /// 占位收缩：ease 曲线向上收拢，下方通知干净地上移。
  static const Curve _kShrinkCurve = Curves.ease;
  /// 未达阈值归位：spring 式回弹还原。
  static const Curve _kDragBackCurve = Curves.easeOutBack;

  /// 入场控制器（forward 0→1）。
  late final AnimationController _controller;

  /// 退场阶段 1（仅点击）：小幅度缩小，占位不变。
  late final AnimationController _pressController;

  /// 退场阶段 2：划出 + 淡化（占位不动）。
  late final AnimationController _swipeController;

  /// 退场阶段 3：占位收缩（下方上移）。
  late final AnimationController _shrinkController;

  /// 点击缩小完成 → 等待 100ms → 划出淡化。
  Timer? _waitTimer;

  /// 滑动未达阈值时的归位动画（_dragX 从当前位置缓慢回 0）。
  late final AnimationController _dragBackController;
  late final Animation<double> _dragBackCurve;
  double _dragBackStart = 0;

  /// 退场动画结束后由父级移除本条目。
  bool _removing = false;

  /// 是否由点击触发退场（点击删除先小段缩小，像被按下一样）；
  /// 滑动 / 定时触发无缩小段。
  bool _byTap = false;
  Timer? _timer;

  /// 左滑删除：手势累计偏移（负值左移）。
  double _dragX = 0;

  /// 滑动删除阈值（px）。
  static const _dismissDistance = 150.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _kEnterDuration);
    // 退场阶段 1：点击缩小（非点击直接用阶段 2）
    _pressController =
        AnimationController(vsync: this, duration: _kPressDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              // 缩小完成 → 停顿 100ms → 划出淡化
              _waitTimer?.cancel();
              _waitTimer = Timer(_kPressWait, _startSwipe);
            }
          });
    // 退场阶段 2：划出 + 淡化 → 紧随占位收缩
    _swipeController =
        AnimationController(vsync: this, duration: _kSwipeDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _startShrink();
          });
    // 退场阶段 3：占位收缩 → 移除
    _shrinkController =
        AnimationController(vsync: this, duration: _kShrinkDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              widget.onRemove();
            }
          });
    // 滑动归位：easeOut 曲线从 _dragBackStart 缓慢收拢回 0
    _dragBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _dragBackCurve = CurvedAnimation(
      parent: _dragBackController,
      curve: _kDragBackCurve,
    );
    _dragBackController.addListener(() {
      setState(() {
        _dragX = _dragBackStart * (1 - _dragBackCurve.value);
      });
    });
    // 首帧布局后播放入场（避免布局期间动画触发 paint）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
    _timer = Timer(widget.item.duration, _remove);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waitTimer?.cancel();
    _controller.dispose();
    _pressController.dispose();
    _swipeController.dispose();
    _shrinkController.dispose();
    _dragBackController.dispose();
    super.dispose();
  }

  void _remove({bool byTap = false}) {
    if (!mounted || _removing) return;
    _timer?.cancel(); // 点击后自动消失计时器失效；其它删除路径同样停表
    _dragBackController.stop();
    setState(() {
      _removing = true;
      _byTap = byTap;
      // 保留 _dragX：退场 Slide 从当前滑动位置继续（不回弹）
    });
    if (_byTap) {
      _pressController.forward(from: 0);
    } else {
      _startSwipe();
    }
  }

  void _startSwipe() {
    if (!mounted || !_removing) return;
    _swipeController.forward(from: 0);
  }

  void _startShrink() {
    if (!mounted || !_removing) return;
    _shrinkController.forward(from: 0);
  }

  // ─── 左滑删除手势 ───

  void _onDragUpdate(DragUpdateDetails d) {
    if (_removing) return;
    _dragBackController.stop();
    setState(() {
      // delta.dx 是单帧增量，必须累计；否则 item 只动一下就被"定格"
      _dragX = (_dragX + d.delta.dx).clamp(-_dismissDistance * 1.5, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_removing) return;
    if (_dragX <= -_dismissDistance) {
      _remove();
    } else {
      // 未达阈值：缓慢归位（收拢回原位置）
      _dragBackStart = _dragX;
      _dragBackController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── 入场（forward 0→1）：左滑入 + 淡入，无展开 ──
    final enterOpacity = CurvedAnimation(
      parent: _controller,
      curve: _kEnterOpacityCurve,
    );
    final enterPosition = Tween(
      begin: const Offset(-0.35, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: _kEnterPositionCurve));

    // ── 退场三阶段（保持用户确认的方向语义）──
    //   phase 1 点击缩小（仅 _byTap，300ms）：scale 1.0→0.92，占位不变
    //   phase 2 划出 + 淡化（300ms）：fade 1→0，slide（用户定的方向）
    //   phase 3 占位收缩（200ms）：size 1→0，下方通知此时才上移
    // 时序：点击 = 缩小(300ms) → 停顿(100ms) → 划出淡化(300ms) → 收缩(200ms)
    //       滑动/定时 = 划出淡化(300ms) → 收缩(200ms)
    final pressScale = _removing && _byTap
        ? Tween(begin: 1.0, end: 0.92).animate(
            CurvedAnimation(parent: _pressController, curve: _kPressCurve),
          )
        : const AlwaysStoppedAnimation(1.0);
    final swipeOpacity = _removing
        ? Tween(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _swipeController, curve: _kSwipeCurve),
          )
        : const AlwaysStoppedAnimation(1.0);
    // 退场滑动方向：Tween(0 → -0.35) forward = 从原位往左划出（右→左）。
    // begin 必须为 Offset.zero：_swipeController 初始 value=0，
    // 若 begin 取 -0.35 会在点按/定时瞬间先把条目左跳 35%（诡异）。
    final swipePosition = _removing
        ? Tween(begin: Offset.zero, end: const Offset(-0.35, 0)).animate(
            CurvedAnimation(parent: _swipeController, curve: _kSwipeCurve),
          )
        : const AlwaysStoppedAnimation(Offset.zero);
    // 占位收缩只在 _shrinkController 真正前进时才生效：
    // Tween(1.0 → 0.0) 让初始 value=0 时 sizeFactor=1（不塌陷），
    // 否则 _removing 一瞬间 shrinkController 仍为 0 → sizeFactor=0 → 立即消失。
    final shrinkSize = _removing
        ? Tween(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _shrinkController, curve: _kShrinkCurve),
          )
        : const AlwaysStoppedAnimation(1.0);

    // 合成：入场用 _controller（forward）；退场各阶段用独立 controller
    final opacity = _removing ? swipeOpacity : enterOpacity;
    final position = _removing ? swipePosition : enterPosition;
    final sizeFactor = _removing
        ? shrinkSize
        : const AlwaysStoppedAnimation(1.0);
    final scale = _removing ? pressScale : const AlwaysStoppedAnimation(1.0);

    Widget content = FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: position,
        child: ScaleTransition(
          scale: scale,
          child: SizeTransition(
            sizeFactor: sizeFactor,
            axisAlignment: -1.0, // 收缩时向上（顶部通知）
            child: widget.item.widget,
          ),
        ),
      ),
    );

    // ── 左滑删除：拖动跟手（无背景层）──
    // _dragX 保留至退场：滑动删除时退场 Slide 从当前位置继续向左，
    // 点击/定时删除时 _dragX=0 从原位起飞。
    content = Transform.translate(offset: Offset(_dragX, 0), child: content);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.item.onTap?.call();
        // 点击：退场先小段缩小（像被按下一样）
        _remove(byTap: true);
      },
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: content,
    );
  }
}

class _NoticeData {
  final String id;
  final Widget widget;
  final VoidCallback? onTap;
  final Duration duration;

  _NoticeData(this.id, this.widget, this.onTap, this.duration);
}
