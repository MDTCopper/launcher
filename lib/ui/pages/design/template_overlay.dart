import 'dart:async';

import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

/// 对话框壳：标题（可选图标）+ 正文 + 底部动作
///
/// 覆盖度审计（2026-11-04）P0-3：现有 App 有 20+ 处对话框，设计层原先没有壳；
/// 语义色与按钮都走皮肤，动作区右对齐、间距 8
class TemplateDialog extends StatelessWidget {
  const TemplateDialog({
    super.key,
    required this.skin,
    required this.title,
    this.message,
    this.content,
    this.actions = const <Widget>[],
    this.icon,
    this.maxWidth = 420,
  });

  final TemplateSkin skin;
  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final IconData? icon;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(TemplateRadius.card),
          border: Border.all(color: skin.border),
          boxShadow: [
            BoxShadow(
              color: skin.shadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(TemplateSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.md,
            children: [
              if (icon != null)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: skin.accentTint,
                    borderRadius: BorderRadius.circular(TemplateRadius.control),
                  ),
                  child: Icon(icon, size: 20, color: skin.onAccentTint),
                ),
              Text(
                title,
                style: TemplateType.section.copyWith(color: skin.textPrimary),
              ),
              if (message != null)
                Text(
                  message!,
                  style: TemplateType.caption.copyWith(
                    color: skin.textSecondary,
                    height: 18 / 12,
                  ),
                ),
              if (content != null) content!,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: TemplateSpace.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: TemplateSpace.sm,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹出对话框（遮罩用皮肤的 `barrier`）
Future<void> showTemplateDialog(
  BuildContext context, {
  required TemplateSkin skin,
  required String title,
  String? message,
  Widget? content,
  List<Widget> actions = const <Widget>[],
  IconData? icon,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: skin.barrier,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(TemplateSpace.xl),
      child: TemplateDialog(
        skin: skin,
        title: title,
        message: message,
        content: content,
        actions: actions,
        icon: icon,
      ),
    ),
  );
}

/// 危险操作二次确认：返回 true = 确认
Future<bool> showTemplateConfirm(
  BuildContext context, {
  required TemplateSkin skin,
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: skin.barrier,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(TemplateSpace.xl),
      child: TemplateDialog(
        skin: skin,
        title: title,
        message: message,
        actions: [
          TemplateButton(
            skin: skin,
            label: cancelLabel,
            icon: Icons.close,
            kind: TemplateButtonKind.plain,
            onTap: () => Navigator.of(dialogContext).pop(false),
          ),
          TemplateButton(
            skin: skin,
            label: confirmLabel,
            icon: danger ? Icons.delete_outline : Icons.check,
            kind: danger ? TemplateButtonKind.danger : TemplateButtonKind.solid,
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Toast 的语气
enum TemplateToastTone { info, success, warning, danger }

/// 一条 Toast 的静态外观（真弹出用 [TemplateToastHost.show]）
class TemplateToast extends StatelessWidget {
  const TemplateToast({
    super.key,
    required this.skin,
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = TemplateToastTone.info,
  });

  final TemplateSkin skin;
  final String message;
  final IconData icon;
  final TemplateToastTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      TemplateToastTone.info => skin.accentText,
      TemplateToastTone.success => skin.success,
      TemplateToastTone.warning => skin.warning,
      TemplateToastTone.danger => skin.dangerText,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
        border: Border.all(color: skin.border),
        boxShadow: [
          BoxShadow(
            color: skin.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TemplateSpace.md,
          vertical: TemplateSpace.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: TemplateSpace.sm,
          children: [
            Icon(icon, size: 16, color: color),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                style: TemplateType.caption.copyWith(color: skin.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToastItem {
  _ToastItem({
    required this.id,
    required this.skin,
    required this.message,
    required this.icon,
    required this.tone,
    required this.timer,
  });

  final int id;
  final TemplateSkin skin;
  final String message;
  final IconData icon;
  final TemplateToastTone tone;
  final Timer timer;
}

/// Toast 宿主：右上角堆叠、5 秒自动消失
///
/// 覆盖度审计 P0-4：现有 App 有 60+ 处 `addNotice`，`TemplateNotice` 是静态条替代不了。
/// 这里按「有就复用、没有就建一个 OverlayEntry」的做法，堆叠成一条列
class TemplateToastHost {
  static OverlayEntry? _entry;
  static final ValueNotifier<List<_ToastItem>> _items = ValueNotifier([]);
  static int _nextId = 0;

  static void show(
    BuildContext context, {
    required TemplateSkin skin,
    required String message,
    IconData icon = Icons.info_outline,
    TemplateToastTone tone = TemplateToastTone.info,
    Duration duration = const Duration(seconds: 5),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => _ToastLayer(items: _items));
      overlay.insert(_entry!);
    }
    late final _ToastItem item;
    final id = _nextId++;
    item = _ToastItem(
      id: id,
      skin: skin,
      message: message,
      icon: icon,
      tone: tone,
      timer: Timer(duration, () => _dismiss(item.id)),
    );
    _items.value = [..._items.value, item];
  }

  static void _dismiss(int id) {
    final next = _items.value.where((item) => item.id != id).toList();
    for (final item in _items.value) {
      if (item.id == id) item.timer.cancel();
    }
    _items.value = next;
  }

  /// 测试 / 退出时清空
  static void clear() {
    for (final item in _items.value) {
      item.timer.cancel();
    }
    _items.value = const [];
    _entry?.remove();
    _entry = null;
  }
}

class _ToastLayer extends StatelessWidget {
  const _ToastLayer({required this.items});

  final ValueNotifier<List<_ToastItem>> items;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: TemplateSpace.lg,
      right: TemplateSpace.lg,
      child: IgnorePointer(
        child: ValueListenableBuilder<List<_ToastItem>>(
          valueListenable: items,
          builder: (context, list, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: TemplateSpace.sm,
              children: [
                for (final item in list)
                  TweenAnimationBuilder<double>(
                    key: ValueKey(item.id),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset((1 - t) * 12, 0),
                        child: child,
                      ),
                    ),
                    child: TemplateToast(
                      skin: item.skin,
                      message: item.message,
                      icon: item.icon,
                      tone: item.tone,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
