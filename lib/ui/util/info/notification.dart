import 'dart:async';
import 'dart:ui';
import 'package:copperlauncher_main/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

//final notificationManager = NotificationManager();

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
    context ??= PageKeyProvider.globalKey.currentContext;
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
    context ??= PageKeyProvider.globalKey.currentContext;
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
  final _globalKey = GlobalKey<AnimatedListState>();
  final _uuid = const Uuid();

  final List<NotificationItem> _itemList = [];

  void addItem(//todo 通知类型
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
            Icon(icon,size: 28),
            if (title != null)
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
              ),
          ],
        ),
        if (content != null)
          Text(
            content,
            style: theme.textTheme.bodyMedium,
          ),
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
    final item = NotificationItem(_uuid.v4(), widget, onTap);
    item.timer = Timer(duration, () => _removeById(item.id));
    setState(() {
      _itemList.add(item);
      _globalKey.currentState!.insertItem(_itemList.length - 1);
    });
  }

  void _removeById(String id) {
    final index = _itemList.indexWhere((item) => item.id == id);
    _removeItem(index);
  }

  void _removeItem(int index) {
    final item = _itemList[index];
    item.timer?.cancel();
    _itemList.removeAt(index);
    setState(() {
      try {
        //todo 这里的并行删除bug不知道怎么修,但是避免快速添加和删除通知还是没有什么问题的
        if (_itemList.isEmpty) {
          _globalKey.currentState!.removeItem(index, (context, animation) {
            animation.addStatusListener((status) {
              if (status.isDismissed && _itemList.isEmpty) {
                widget.onDismiss.call();
              }
            });
            return _buildRemoveAnimation(item.widget, animation);
          }, duration: Duration(milliseconds: 800));
        } else {
          _globalKey.currentState!.removeItem(index, (context, animation) {
            return _buildRemoveAnimation(item.widget, animation);
          }, duration: Duration(milliseconds: 800));
        }
      } catch (e) {
        return;
      }
    });
  }

  Widget _buildRemoveAnimation(Widget? child, Animation<double> animation) {
    final position = Tween<Offset>(
      begin: Offset(-0.4, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    final opacity = CurvedAnimation(
      parent: animation,
      curve: Interval(0.6, 1.0, curve: Curves.easeIn),
    );

    final sizeFactor = CurvedAnimation(
      parent: animation,
      curve: Interval(0.0, 0.4, curve: Curves.easeIn),
    );

    return SizeTransition(
      sizeFactor: sizeFactor,
      child: FadeTransition(
        opacity: opacity,
        child: SlideTransition(position: position, child: child),
      ),
    );
  }

  Widget _buildWidget(int index) {
    final item = _itemList[index];
    return GestureDetector(
      onTap: () {
        item.onTap?.call();
        _removeItem(index);
      },
      child: item.widget,
    );
  }

  @override
  void dispose() {
    for (final item in _itemList) {
      item.timer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 300),
      child: AnimatedList(
        key: _globalKey,
        shrinkWrap: true,
        clipBehavior: Clip.none,
        initialItemCount: _itemList.length,
        physics: NeverScrollableScrollPhysics(),
        itemBuilder: (context, index, animation) {
          Animation<Offset> position = Tween<Offset>(
            begin: Offset(-0.4, 0.0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          );

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: position,
              child: _buildWidget(index),
            ),
          );
        },
      ),
    );
  }
}

class NotificationItem {
  final String id;
  final Widget widget;
  final VoidCallback? onTap;
  Timer? timer; //计时器
  NotificationItem(this.id, this.widget, this.onTap);
}
