import 'dart:ui';

import 'package:copperlauncher_main/ui/util/widget/resource_importer.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class DragFileField extends StatefulWidget {
  const DragFileField({
    super.key,
    required this.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragUpdated,
    this.onDragDone,
    this.enable = true,
    this.duration,
  });

  final Widget child;
  final OnDragCallback<DropEventDetails>? onDragEntered;
  final OnDragCallback<DropEventDetails>? onDragExited;
  final OnDragCallback<DropEventDetails>? onDragUpdated;
  final OnDragDoneCallback? onDragDone;
  final Duration? duration;
  final bool enable;

  @override
  State<StatefulWidget> createState() => _DragFileFieldState();
}

class _DragFileFieldState extends State<DragFileField> {
  OverlayEntry? _overlayEntry;
  final _filterKey = GlobalKey<_DragFileFilterState>();

  void _showDragFileFilter() {
    if (isImporting) return;
    _filterKey.currentState?.controller.forward();
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _DragFileFilter(key: _filterKey, duration: widget.duration);
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeDragFileFilter() {
    _filterKey.currentState?.controller.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) {
        _showDragFileFilter();
        widget.onDragEntered?.call(details);
      },
      onDragExited: (details) {
        _removeDragFileFilter();
        widget.onDragExited?.call(details);
      },
      onDragDone: widget.onDragDone,
      onDragUpdated: widget.onDragUpdated,
      child: widget.child,
    );
  }
}

class _DragFileFilter extends StatefulWidget {
  const _DragFileFilter({super.key, this.duration});

  final Duration? duration;

  @override
  State<StatefulWidget> createState() => _DragFileFilterState();
}

class _DragFileFilterState extends State<_DragFileFilter>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: widget.duration ?? const Duration(milliseconds: 300),
    );
    controller.forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primaryContainer;

    final animation = CurvedAnimation(parent: controller, curve: Curves.ease);

    return FadeTransition(
      opacity: animation,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 3,
          sigmaY: 3,
          tileMode: TileMode.mirror,
        ),
        child: Container(
          alignment: Alignment.center,
          color: color.withAlpha(85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.file_download_outlined,
                size: 64,
                color: theme.colorScheme.onSurface,
              ),
              Text('导入本地资源', style: theme.textTheme.displayLarge),
              Text('拖入资源以导入', style: theme.textTheme.bodyLarge),
              Text(
                '支持导入游戏本体\n'
                'mod(.zip/.jar)  地图(.msav)  蓝图(.msch)  存档(.zip)\n'
                '也可以直接导入文件夹',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
