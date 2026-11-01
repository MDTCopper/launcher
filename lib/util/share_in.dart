import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/host_annotations.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';

/// 安卓「系统分享进来」的 Dart 侧入口
///
/// 宿主（`MainActivity` 的 `ShareIntentHandler`）把 `content://` 复制成应用缓存里的
/// 真文件——Dart 读不了 content URI——再交给 `IncomingIntake` 攒着。
/// 这里通过生成的 [AndroidCall] 取回；拿到文件之后怎么导由调用方决定，
/// 页面上与桌面拖入共用 `showResourceImporter`
class ShareIn {
  ShareIn._();

  static final _queue = SharedFileQueue();

  static bool _started = false;

  /// 接线：有分享到的文件时回调（已经在缓存目录里，可直接读）
  ///
  /// 只留一个回调——导入流程同屏只允许一个；重复接线会把攒着的文件立刻交出去
  static void onFiles(void Function(List<String> files) handler) {
    _queue.attach(handler);
  }

  /// 启动时调一次：把「App 没在跑时那次分享」取回来
  ///
  /// 重复调用无害；非安卓平台直接返回
  static Future<void> start() async {
    if (!Platform.isAndroid || _started) return;
    _started = true;
    await _refresh();
  }

  /// 宿主推来的新分享：热启动事件自带文件路径，不用再取一次
  ///
  /// 冷启动那次事件早于 `AndroidEvent.start()`（甚至早于引擎），
  /// 文件的来源始终是 [start] 里那次取。
  @KotlinEvent()
  static void onSharedFiles(List<String> files) {
    _queue.add(files);
  }

  static Future<void> _refresh() async {
    _queue.add(await _takeSharedFiles());
  }

  /// 向宿主取一次；失败只记日志，不让启动流程挂在这条通道上
  static Future<List<String>> _takeSharedFiles() async {
    try {
      final files = await AndroidCall.takeSharedFiles();
      if (files.isNotEmpty) {
        addLog(.info, '收到系统分享：${files.length} 个文件', tag: 'Share');
      }
      return files;
    } on Object catch (error) {
      addLog(.warning, '取分享文件失败：${removeNewlines('$error')}', tag: 'Share');
      return const [];
    }
  }
}

/// 「分享先到、界面后到」的那点缓冲：没接线时攒着，接线后一次性交出去
///
/// 宿主可能早于界面把文件送过来（冷启动那次分享），攒着才不会丢
@visibleForTesting
class SharedFileQueue {
  final List<String> _files = [];

  void Function(List<String> files)? _handler;

  void attach(void Function(List<String> files) handler) {
    _handler = handler;
    _flush();
  }

  void add(List<String> files) {
    if (files.isEmpty) return;
    _files.addAll(files);
    _flush();
  }

  void _flush() {
    final handler = _handler;
    if (handler == null || _files.isEmpty) return;
    final batch = List<String>.of(_files);
    _files.clear();
    handler(batch);
  }
}
