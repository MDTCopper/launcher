import 'dart:async';
import 'dart:ui';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// 失败语义的通知图标：这类通知除了弹出来，还会落一条运行日志
///
/// 通知会自动消失，用户关掉 / 错过就查不到原因——失败类一律同时进日志
final _failureNoticeIcons = <IconData>{
  Icons.close,
  Icons.error,
  Icons.error_outline,
  Icons.delete_forever,
};

/// 通知样式
enum NoticeStyle {
  /// 右上角卡片（默认）：标题 + 正文，适合需要看清内容的结果提示
  card,

  /// 底部居中胶囊：单行短句，3 秒左右自动消失，适合「已复制」这类轻提示
  toast,

  /// 顶部居中横条：图标 + 标题 + 说明，适合页面级提示（有轻微干扰）
  banner,
}

void addNotice({
  IconData? icon,
  String? title,
  String? content,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 5),
  NoticeStyle style = NoticeStyle.card,
}) => NotificationManager.addNotice(
  content: content,
  title: title,
  icon: icon,
  onTap: onTap,
  duration: duration,
  style: style,
);

void addNoticeWidget({
  required Widget widget,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 5),
  NoticeStyle style = NoticeStyle.card,
}) => NotificationManager.addNoticeWidget(
  widget: widget,
  onTap: onTap,
  duration: duration,
  style: style,
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
    NoticeStyle style = NoticeStyle.card,
  }) async {
    // 失败类通知同时落盘（消息先压成一行，异常原文常带换行）
    if (icon != null && _failureNoticeIcons.contains(icon)) {
      final message = [
        ?title,
        ?content,
      ].where((text) => text.isNotEmpty).join('：');
      addLog(.error, removeNewlines(message), tag: 'Notice');
    }
    context ??= PageKeyProvider.shellKey.currentContext;
    //shell 还没挂上（启动早期 / 退出阶段 / 单测）时静默跳过：这是 fire-and-forget
    //调用，异步里抛出来就是未捕获异常
    if (context == null) return;
    await _show(context).then((_) {
      _globalKey.currentState?.addItem(
        icon,
        title,
        content,
        onTap,
        duration,
        style,
      );
    });
  }

  static void addNoticeWidget({
    BuildContext? context,
    required Widget widget,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 5),
    NoticeStyle style = NoticeStyle.card,
  }) async {
    context ??= PageKeyProvider.shellKey.currentContext;
    //同 addNotice：没有 shell 就没人能收到这条通知，直接跳过而不是抛空指针
    if (context == null) return;
    await _show(context).then((_) {
      _globalKey.currentState?.addItemWidget(widget, onTap, duration, style);
    });
  }

  /// 正在插入 overlay 的 Future：同一帧里连发多条通知时共用它，
  /// 否则每条都会看到 `mounted == false` 各插一份，同一 `_widget`
  /// （带 GlobalKey）会被放进两个 OverlayEntry ⇒ GlobalKey 冲突
  static Future<void>? _showFuture;

  static Future<void> _show(BuildContext context) {
    if (_overlayEntry != null && (_overlayEntry?.mounted ?? false)) {
      return Future.value();
    }
    return _showFuture ??= _insert(context).whenComplete(() {
      _showFuture = null;
    });
  }

  static Future<void> _insert(BuildContext context) async {
    if (_overlayEntry != null && (_overlayEntry?.mounted ?? false)) return;
    _overlayEntry = OverlayEntry(
      builder: (_) {
        // 铺满整块，由 NotificationWidget 自己按样式分配到三个位置
        return Positioned.fill(child: _widget);
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
    await WidgetsBinding.instance.endOfFrame; //等待第一帧加载
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
    NoticeStyle style,
  ) {
    final widget = switch (style) {
      NoticeStyle.card => _buildCard(icon, title, content),
      NoticeStyle.toast => _buildToast(icon, title, content),
      NoticeStyle.banner => _buildBanner(icon, title, content),
    };
    addItemWidget(widget, onTap, duration, style);
  }

  /// 右上角卡片：图标 + 标题 + 正文（卡片底 + 1px 描边）
  Widget _buildCard(IconData? icon, String? title, String? content) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colors.cardBackground,
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.hardEdge,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            if (icon != null) Icon(icon, size: 20, color: colors.interactive),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  if (title != null)
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.itemPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (content != null)
                    Text(
                      content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.itemSecondary,
                        height: 18 / 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部居中胶囊：单行短句（有标题优先标题，否则正文）
  Widget _buildToast(IconData? icon, String? title, String? content) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final text = title ?? content ?? '';

    return Material(
      color: colors.elevatedBackground,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.hardEdge,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (icon != null) Icon(icon, size: 16, color: colors.itemSecondary),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: colors.itemPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部居中横条：图标 + 标题 + 说明
  Widget _buildBanner(IconData? icon, String? title, String? content) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colors.cardBackground,
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.hardEdge,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          spacing: 10,
          children: [
            if (icon != null) Icon(icon, size: 18, color: colors.interactive),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  if (title != null)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.itemPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (content != null)
                    Text(
                      content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.itemSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void addItemWidget(
    Widget widget,
    VoidCallback? onTap,
    Duration duration,
    NoticeStyle style,
  ) {
    setState(() {
      _itemList.add(_NoticeData(_uuid.v4(), widget, onTap, duration, style));
    });
  }

  /// 移除指定 id 的通知（定时器 / 左滑删除按钮 / 点击共同入口）
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
    return Stack(
      fit: StackFit.expand,
      children: [
        // 右上角卡片：顶边让开 40 高的顶栏
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 56),
            child: _columnFor(NoticeStyle.card, _maxCard),
          ),
        ),
        // 顶部居中横条
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _columnFor(NoticeStyle.banner, _maxBanner),
          ),
        ),
        // 底部居中胶囊
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _columnFor(NoticeStyle.toast, _maxToast),
          ),
        ),
      ],
    );
  }

  Widget _columnFor(NoticeStyle style, double maxWidth) {
    final items = _itemList.where((item) => item.style == style).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in items)
            // key 必须落在 Column 的直接 children 上：藏在包装里时，
            // 删中间一条会让后面那条按 index 复用包装层、被重建并重播入场动画
            _NoticeItem(
              key: ValueKey(item.id),
              item: item,
              onRemove: () => _removeById(item.id),
              padding: style == NoticeStyle.toast
                  ? const EdgeInsets.only(bottom: 8)
                  : const EdgeInsets.only(right: 12, bottom: 12),
              alignment: style == NoticeStyle.toast
                  ? Alignment.bottomCenter
                  : style == NoticeStyle.banner
                  ? Alignment.topCenter
                  : Alignment.topRight,
            ),
        ],
      ),
    );
  }

  /// 各样式最大宽度
  static const _maxCard = 300.0;
  static const _maxToast = 420.0;
  static const _maxBanner = 560.0;
}

/// 通知条目：自持入场 / 退场动画 + 右滑删除
///
/// - **入场**：仅 右滑入 + 淡入（无展开动画），播完保持显示
/// - **退场**：分段 —— 点击先缩小（scale 1.0→0.92）→ 停顿 → 划出+淡出 →
///   最后占位收缩（SizeTransition，下方通知才上移）
/// - **右滑删除**：跟手右移，超过 [dismissDistance] 松手即退场删除；
///   未超阈值松手回弹恢复（无删除背景层）
/// - 定时器到期也走同一退场路径，`onRemove` 只在退场动画结束后触发一次
class _NoticeItem extends StatefulWidget {
  final _NoticeData item;
  final VoidCallback onRemove;

  /// 外衬；toast 只留底部间距，card / banner 保留右侧间距
  final EdgeInsets padding;

  /// 收缩时的对齐（右对齐的卡片从右上收，toast 从底部收）
  final Alignment alignment;

  const _NoticeItem({
    super.key,
    required this.item,
    required this.onRemove,
    this.padding = const EdgeInsets.only(right: 12, bottom: 12),
    this.alignment = Alignment.topRight,
  });

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

  /// 滑动未达阈值时的归位动画（_dragX 从当前位置缓慢回 0）
  late final AnimationController _dragBackController;
  late final Animation<double> _dragBackCurve;
  double _dragBackStart = 0;

  /// 退场动画结束后由父级移除本条目
  bool _removing = false;

  /// 是否由点击触发退场（点击删除先小段缩小，像被按下一样）；
  /// 滑动 / 定时触发无缩小段
  bool _byTap = false;
  Timer? _timer;

  /// 右滑删除：手势累计偏移（正值右移）
  double _dragX = 0;

  /// 滑动删除阈值（px）
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
              // 缩小完成 → 停顿 _kPressWait → 划出淡化
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

  // ─── 右滑删除手势 ───

  void _onDragUpdate(DragUpdateDetails d) {
    if (_removing) return;
    _dragBackController.stop();
    setState(() {
      // delta.dx 是单帧增量，必须累计；否则 item 只动一下就被"定格"
      _dragX = (_dragX + d.delta.dx).clamp(0.0, _dismissDistance * 1.5);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_removing) return;
    if (_dragX >= _dismissDistance) {
      _remove();
    } else {
      // 未达阈值：缓慢归位
      _dragBackStart = _dragX;
      _dragBackController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enterPosition = Tween(begin: const Offset(0.35, 0), end: Offset.zero)
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
        ? Tween(begin: Offset.zero, end: const Offset(0.35, 0)).animate(
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
    // SizeTransition / 底部分隔放在最外层，见下方 return
    Widget content = FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: position,
        child: ScaleTransition(scale: scale, child: widget.item.widget),
      ),
    );

    // ── 左滑删除 ──
    // _dragX 保留至退场：滑动删除时退场 Slide 从当前位置继续向左，
    // 点击/定时删除时 _dragX=0 从原位起飞
    content = Transform.translate(offset: Offset(_dragX, 0), child: content);

    // 点击/滑动区只覆盖卡片本身
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

    return SizeTransition(
      sizeFactor: sizeFactor,
      //纵向收缩不动宽度 ⇒ 这一层的盒子仍占满宽度，卡片得靠对齐方式贴住目标边缘
      alignment: widget.alignment,
      child: Padding(padding: widget.padding, child: item),
    );
  }
}

class _NoticeData {
  final String id;
  final Widget widget;
  final VoidCallback? onTap;
  final Duration duration;
  final NoticeStyle style;

  _NoticeData(this.id, this.widget, this.onTap, this.duration, this.style);
}
