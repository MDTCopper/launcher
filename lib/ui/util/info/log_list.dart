import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../widget/desktop_scroll_view.dart';

//final logManager = LogManager();

void addLog(LogEntry entry) => LogManager.addLog(entry);

class LogManager {
  static final _instance = LogManager._();
  const LogManager._();
  factory LogManager() => _instance;

  static final ValueNotifier<List<LogEntry>> logNotifier = ValueNotifier([]);

  static List<LogEntry> get logList => logNotifier.value;

  static void addLog(LogEntry entry) {
    logNotifier.value = List.from(logNotifier.value)..add(entry);
  }

  static void removeAll() {
    logNotifier.value = [];
  }
}

class LogList extends StatefulWidget {
  const LogList({super.key});
  @override
  State<StatefulWidget> createState() => _LogListState();
}

class _LogListState extends State<LogList> {
  final List<Widget> _logList = [];
  final _key = GlobalKey<AnimatedListState>();
  final controller = ScrollController();

  @override
  void initState() {
    LogManager.logNotifier.addListener(_onChange);
    super.initState();
  }

  void _onChange() {
    setState(() {
      if (LogManager.logList.isEmpty) {
        removeItem();
      } else {
        addItem(LogManager.logList.last);
      }
    });
  }

  String _formatTime(DateTime time) {
    return DateFormat('HH:mm:ss').format(time);
  }

  @override
  void dispose() {
    LogManager.logNotifier.removeListener(_onChange);
    super.dispose();
  }

  void addItem(LogEntry logEntry) {
    IconData icon;
    switch (logEntry.type) {
      case LogType.info:
        icon = Icons.info_outline;
        break;
      case LogType.success:
        icon = Icons.check_box_outlined;
        break;
      case LogType.error:
        icon = Icons.error_outline;
        break;
      case LogType.warning:
        icon = Icons.warning_amber;
        break;
    }

    final color = Theme.of(context).colorScheme.onPrimary;

    setState(() {
      _logList.insert(
        0,
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(logEntry.describe, style: TextStyle(color: color)),
          subtitle: Text(
            _formatTime(logEntry.time),
            style: TextStyle(color: color.withAlpha(185)),
          ),
        ),
      );
      _key.currentState!.insertItem(0, duration: Duration(milliseconds: 450));
    });
  }

  void removeItem() {
    _logList.clear();
    setState(() {
      _key.currentState!.removeAllItems((context, animation) {
        return SizedBox();
      });
    });
  }

  Widget _buildNoLogPage() {
    final color = Theme.of(context).colorScheme.onPrimary.withAlpha(185);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_calendar_outlined, color: color, size: 48),
          Text('日志空空的 (´・ω・`)', style: TextStyle(color: color, fontSize: 28)),
          SizedBox(height: 50),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logList.clear();
    final color = Theme.of(context).colorScheme.onPrimary;
    for (LogEntry logEntry in LogManager.logList) {
      IconData icon;
      switch (logEntry.type) {
        case LogType.info:
          icon = Icons.info_outline;
          break;
        case LogType.success:
          icon = Icons.check_box_outlined;
          break;
        case LogType.error:
          icon = Icons.error_outline;
          break;
        case LogType.warning:
          icon = Icons.warning_amber;
          break;
      }
      _logList.insert(
        0,
        ListTile(
          style: ListTileStyle.drawer,
          leading: Icon(icon, color: color),
          title: Text(logEntry.describe, style: TextStyle(color: color)),
          subtitle: Text(
            _formatTime(logEntry.time),
            style: TextStyle(color: color.withAlpha(185)),
          ),
        ),
      );
    }

    if (_logList.isEmpty) {
      return _buildNoLogPage();
    }

    if (Platform.isWindows) {
      return DesktopScrollViewContainer(
        controller: controller,
        child: AnimatedList(
          key: _key,
          controller: controller,
          initialItemCount: _logList.length,
          itemBuilder: (context, index, animation) {
            final sizeFactor = CurvedAnimation(
              parent: animation,
              curve: Interval(0.0, 0.5, curve: Curves.easeOut),
            );
            final opacity = CurvedAnimation(
              parent: animation,
              curve: Interval(0.3, 1.0),
            );
            final position = Tween<Offset>(
              begin: Offset(0.3, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Interval(0.3, 1.0, curve: Curves.easeOutBack),
              ),
            );
            return SizeTransition(
              sizeFactor: sizeFactor,
              child: FadeTransition(
                opacity: opacity,
                child: SlideTransition(
                  position: position,
                  child: _logList[index],
                ),
              ),
            );
          },
        ),
      );
    }

    return AnimatedList(
      key: _key,
      initialItemCount: _logList.length,
      itemBuilder: (context, index, animation) {
        final sizeFactor = CurvedAnimation(
          parent: animation,
          curve: Interval(0.0, 0.5, curve: Curves.easeOut),
        );
        final opacity = CurvedAnimation(
          parent: animation,
          curve: Interval(0.3, 1.0),
        );
        final position = Tween<Offset>(
          begin: Offset(0.3, 0.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Interval(0.3, 1.0, curve: Curves.easeOutBack),
          ),
        );
        return SizeTransition(
          sizeFactor: sizeFactor,
          child: FadeTransition(
            opacity: opacity,
            child: SlideTransition(position: position, child: _logList[index]),
          ),
        );
      },
    );
  }
}

enum LogType { info, success, error, warning }

class LogEntry {
  final LogType type;
  final String describe;
  final DateTime time;

  LogEntry(this.type, this.describe) : time = DateTime.now();
}
