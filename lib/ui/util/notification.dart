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
  Duration duration = const Duration(seconds: 5),
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
  Duration duration = const Duration(seconds: 5),
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
    Duration duration = const Duration(seconds: 5),
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
    Duration duration = const Duration(seconds: 5),
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

    widget = Material(
      color: Colors.transparent,
      elevation: 4,
      clipBehavior: Clip.hardEdge,
      child: widget,
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
              child: _NoticeItem(
                item: item,
                onRemove: () => _removeById(item.id),
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

  static const Curve _kEnterPositionCurve = Curves.easeOutBack;

  static const Curve _kEnterOpacityCurve = Curves.easeOutCubic;

  static const Curve _kPressCurve = Curves.easeOutCubic;

  static const Curve _kSwipeCurve = Curves.easeInCubic;

  static const Curve _kShrinkCurve = Curves.easeOutCubic;

  static const Curve _kDragBackCurve = Curves.easeOutBack;

  late final AnimationController _controller;

  late final AnimationController _pressController;

  late final AnimationController _swipeController;

  late final AnimationController _shrinkController;

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
  static const _dismissDistance = 100.0;

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
      // 保留 _dragX：退场 Slide 从当前滑动位置继续
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
    final enterPosition = Tween(begin: const Offset(-0.35, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _controller, curve: _kEnterPositionCurve),
        );

    final pressScale = _removing && _byTap
        ? Tween(begin: 1.0, end: 0.92).animate(
            CurvedAnimation(parent: _pressController, curve: _kPressCurve),
          )
        : const AlwaysStoppedAnimation(1.0);
    final enterOpacity = CurvedAnimation(
      parent: _controller,
      curve: _kEnterOpacityCurve,
    );

    final swipePosition = _removing
        ? Tween(begin: Offset.zero, end: const Offset(-0.35, 0)).animate(
            CurvedAnimation(parent: _swipeController, curve: _kSwipeCurve),
          )
        : const AlwaysStoppedAnimation(Offset.zero);

    final shrinkSize = _removing
        ? Tween(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _shrinkController, curve: _kShrinkCurve),
          )
        : const AlwaysStoppedAnimation(1.0);

    // 合成：入场用 _controller（forward）；退场各阶段用独立 controller
    final swipeOpacity = _removing
        ? Tween(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _swipeController, curve: _kSwipeCurve),
          )
        : const AlwaysStoppedAnimation(1.0);
    final opacity = _removing ? swipeOpacity : enterOpacity;
    final position = _removing ? swipePosition : enterPosition;
    final sizeFactor = _removing
        ? shrinkSize
        : const AlwaysStoppedAnimation(1.0);
    final scale = _removing ? pressScale : const AlwaysStoppedAnimation(1.0);

    // 视觉变换（Fade / Slide / Scale）只作用于通知卡片本身；
    // SizeTransition / 底部分隔放在最外层，见下方 return。
    Widget content = FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: position,
        child: ScaleTransition(scale: scale, child: widget.item.widget),
      ),
    );

    // ── 左滑删除：拖动跟手）──
    // _dragX 保留至退场：滑动删除时退场 Slide 从当前位置继续向左，
    // 点击/定时删除时 _dragX=0 从原位起飞。
    content = Transform.translate(offset: Offset(_dragX, 0), child: content);

    // 点击/滑动区只覆盖卡片本身。
    final Widget item = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.item.onTap?.call();
        // 点击：退场先小段缩小
        _remove(byTap: true);
      },
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: content,
    );

    // 底部分隔在 SizeTransition 内、GestureDetector 外：
    // 随条目一起收缩（移除不瞬移），但不属于点击/滑动区。
    return SizeTransition(
      sizeFactor: sizeFactor,
      axisAlignment: -1.0,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Padding(padding: const EdgeInsets.only(bottom: 12), child: item),
      ),
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
