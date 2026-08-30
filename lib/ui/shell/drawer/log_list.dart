import 'dart:io';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../components/scroll/desktop_scroll_view.dart';
import '../../components/scroll/scroll_fade_mask.dart';

void addTaskLog(LogEntry entry) => TaskLogManager.addLog(entry);

/// 日志管理：全局共享，[logNotifier] 供列表监听
///
/// 上限 [_kMaxLogs]：99
class TaskLogManager {
  static final _instance = TaskLogManager._();
  const TaskLogManager._();
  factory TaskLogManager() => _instance;

  /// 日志条数上限
  static const int _kMaxLogs = 99;

  static final ValueNotifier<List<LogEntry>> logNotifier = ValueNotifier([]);

  static List<LogEntry> get logList => logNotifier.value;

  static void addLog(LogEntry entry) {
    final current = logNotifier.value;
    if (current.length >= _kMaxLogs) {
      logNotifier.value = List.of(current.skip(1))..add(entry);
      return;
    }
    logNotifier.value = List.of(current)..add(entry);
  }

  static void removeAll() {
    logNotifier.value = [];
  }
}

class TaskLogList extends StatefulWidget {
  const TaskLogList({super.key});
  @override
  State<StatefulWidget> createState() => _TaskLogListState();
}

class _TaskLogListState extends State<TaskLogList> {
  /// 当前展示的日志条数
  int _itemCount = 0;

  /// 上一轮的日志列表
  List<LogEntry> _lastEntries = [];

  /// 最近一条日志
  LogEntry? _lastNewest;

  final _key = GlobalKey<AnimatedListState>();
  final controller = ScrollController();

  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _lastEntries = TaskLogManager.logList;
    _itemCount = _lastEntries.length;
    if (_lastEntries.isNotEmpty) {
      _lastNewest = _lastEntries.last;
    }
    TaskLogManager.logNotifier.addListener(_onChange);
  }

  @override
  void dispose() {
    TaskLogManager.logNotifier.removeListener(_onChange);
    controller.dispose();
    super.dispose();
  }

  void _onChange() {
    final entries = TaskLogManager.logList;
    final newCount = entries.length;
    final newest = entries.isEmpty ? null : entries.last;
    final oldEntries = _lastEntries;
    final oldCount = _itemCount;
    final state = _key.currentState;

    LogEntry oldEntryAt(int displayIndex) =>
        oldEntries[oldEntries.length - 1 - displayIndex];

    if (newCount == 0) {
      state?.removeAllItems((context, animation) => const SizedBox.shrink());
      setState(() {
        _itemCount = 0;
        _lastEntries = entries;
      });
      return;
    }

    if (newCount > oldCount) {
      for (var i = oldCount; i < newCount; i++) {
        state?.insertItem(0, duration: const Duration(milliseconds: 450));
      }
      setState(() {
        _itemCount = newCount;
        _lastEntries = entries;
      });
      return;
    }

    if (newCount == oldCount && newest != _lastNewest) {
      if (state != null) {
        final bottomIndex = oldCount - 1;
        state.removeItem(
          bottomIndex,
          (context, animation) => _wrapItemAnimation(
            animation,
            _buildItem(oldEntryAt(bottomIndex)),
          ),
          duration: const Duration(milliseconds: 300),
        );
        state.insertItem(0, duration: const Duration(milliseconds: 450));
      }
      setState(() {
        _lastEntries = entries;
        _lastNewest = newest;
      });
      return;
    }

    final removeCount = oldCount - newCount;
    for (var i = 0; i < removeCount; i++) {
      final bottomIndex = oldCount - 1 - i;
      state?.removeItem(
        bottomIndex,
        (context, animation) =>
            _wrapItemAnimation(animation, _buildItem(oldEntryAt(bottomIndex))),
        duration: const Duration(milliseconds: 300),
      );
    }
    setState(() {
      _itemCount = newCount;
      _lastEntries = entries;
      _lastNewest = newest;
    });
  }

  LogEntry _entryAtDisplayIndex(int index) {
    return TaskLogManager.logList[TaskLogManager.logList.length - 1 - index];
  }

  Widget _buildItem(LogEntry logEntry) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(_typeIcon(logEntry.type), size: 18, color: colors.itemHint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              logEntry.describe,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _timeFormat.format(logEntry.time),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(LogType type) {
    return switch (type) {
      LogType.info => Icons.info_outline,
      LogType.success => Icons.check_box_outlined,
      LogType.error => Icons.error_outline,
      LogType.warning => Icons.warning_amber,
    };
  }

  Widget _wrapItemAnimation(Animation<double> animation, Widget child) {
    final sizeFactor = CurvedAnimation(
      parent: animation,
      curve: Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    final opacity = CurvedAnimation(
      parent: animation,
      curve: Interval(0.3, 1.0),
    );
    final position = Tween<Offset>(begin: Offset(0.2, 0.0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: animation,
            curve: Interval(0.3, 1.0, curve: Curves.easeOutBack),
          ),
        );
    return SizeTransition(
      sizeFactor: sizeFactor,
      child: FadeTransition(
        opacity: opacity,
        child: SlideTransition(position: position, child: child),
      ),
    );
  }

  Widget _buildNoLogPage() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_calendar_outlined, color: colors.itemHint, size: 48),
          Text(
            '日志空空的 (´・ω・`)',
            style: theme.textTheme.displayLarge?.copyWith(
              color: colors.itemHint,
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (TaskLogManager.logList.isEmpty) return _buildNoLogPage();

    Widget list = AnimatedList(
      key: _key,
      controller: controller,
      initialItemCount: _itemCount,
      itemBuilder: (context, index, animation) {
        return _wrapItemAnimation(
          animation,
          _buildItem(_entryAtDisplayIndex(index)),
        );
      },
    );

    if (Platform.isWindows) {
      list = DesktopScrollViewContainer(controller: controller, child: list);
    }
    list = ScrollFadeMask(controller: controller, child: list);
    return list;
  }
}

enum LogType { info, success, error, warning }

class LogEntry {
  final LogType type;
  final String describe;
  final DateTime time;

  LogEntry(this.type, this.describe) : time = DateTime.now();
}
