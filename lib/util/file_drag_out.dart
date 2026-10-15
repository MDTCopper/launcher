import 'dart:io';
import 'dart:ui';

import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/services.dart';

/// 桌面端「把文件拖出去」：从指针所在的位置开始一次原生拖放
///
/// Windows 侧走 `windows/runner/file_drag_out.cpp`（`DoDragDrop` + `CF_HDROP`）；
/// Linux / macOS 还没有原生实现，[isSupported] 为 false 时调用方应当退回菜单里的导出
class FileDragOut {
  FileDragOut._();

  static const channel = MethodChannel('io.github.copper.launcher/dragout');

  /// 有没有可用的原生拖出
  static bool get isSupported => Platform.isWindows;

  /// 在拖拽手势里调用：从 [globalPosition] 开始拖
  ///
  /// [globalPosition] 用 Flutter 的逻辑像素（手势回调给的那个直接传）；
  /// 返回是否真的落到了别处——用户按 Esc 取消、原地松手都算 false
  static Future<bool> start(
    List<String> paths, {
    required Offset globalPosition,
  }) async {
    if (!isSupported) return false;
    final files = _existingFiles(paths);
    if (files.isEmpty) {
      addLog(.warning, '没有可拖出的文件：$paths', tag: 'Share');
      return false;
    }
    try {
      final dropped = await channel.invokeMethod<bool>('startDrag', {
        'paths': files,
        'x': globalPosition.dx,
        'y': globalPosition.dy,
        'dpr': _devicePixelRatio(),
      });
      return dropped ?? false;
    } on Object catch (error) {
      addLog(.warning, '拖出失败：${removeNewlines('$error')}', tag: 'Share');
      return false;
    }
  }

  /// 手势坐标是逻辑像素，原生侧要乘这个数才是物理像素
  static double _devicePixelRatio() {
    final views = PlatformDispatcher.instance.views;
    return views.isEmpty ? 1 : views.first.devicePixelRatio;
  }

  static List<String> _existingFiles(List<String> paths) => [
    for (final path in paths)
      if (File(path).existsSync()) path,
  ];
}
