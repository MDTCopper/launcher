import 'dart:async';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';

/// 轻提示（toast）：**独立于通知**的单条浮层，底部居中、自动消失
///
/// 定位差异：
/// - toast = 轻提示，一次只显示一条，新的直接替换旧的，不堆叠、不进通知列表
/// - notification = 需要看清内容 / 可保留的通知（右上卡片、顶部横条），会堆叠
///
/// 用法：`showToast(text: '已复制房间码', icon: Icons.copy)`
void showToast({
  required String text,
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
  BuildContext? context,
}) {
  ToastManager.show(
    text: text,
    icon: icon,
    duration: duration,
    context: context,
  );
}

class ToastManager {
  ToastManager._();

  static final _key = GlobalKey<_ToastWidgetState>();
  static final _widget = _ToastWidget(key: _key);

  static OverlayEntry? _entry;

  static void show({
    required String text,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    BuildContext? context,
  }) {
    final ctx = context ?? PageKeyProvider.shellKey.currentContext;
    // shell 还没挂上（启动早期 / 单测）时静默丢弃：fire-and-forget
    if (ctx == null) return;

    _ensureEntry(ctx);
    // 等第一帧把 widget 挂上，再推内容；同帧连发只保留最后一条
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _key.currentState?.show(text: text, icon: icon, duration: duration);
    });
  }

  static void _ensureEntry(BuildContext context) {
    if (_entry != null && (_entry?.mounted ?? false)) return;
    _entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: _widget,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  static void _removeEntry() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({super.key});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  Timer? _timer;
  String _text = '';
  IconData? _icon;

  void show({
    required String text,
    IconData? icon,
    required Duration duration,
  }) {
    setState(() {
      _text = text;
      _icon = icon;
    });
    _timer?.cancel();
    _controller.forward();
    _timer = Timer(duration, _hide);
  }

  void _hide() async {
    if (!mounted) return;
    await _controller.reverse();
    if (!mounted) return;
    ToastManager._removeEntry();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: Material(
          color: colors.elevatedBackground,
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.hardEdge,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (_icon != null)
                  Icon(_icon, size: 16, color: colors.itemSecondary),
                Flexible(
                  child: Text(
                    _text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.itemPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
