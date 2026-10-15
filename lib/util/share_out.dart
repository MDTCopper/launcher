import 'dart:io';

import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// 把本机文件交给别的 App（移动端那条路；桌面端是拖出，见 `file_drag_out.dart`）
class ShareOut {
  ShareOut._();

  /// 分享若干个文件，返回是否真的发出去了（用户取消为 false）
  ///
  /// 文件在调用时已经没了就返回 false，不去弹一个点不动的空面板
  static Future<bool> shareFiles(
    List<String> paths, {
    String? title,
    String? text,
  }) async {
    final files = existingFiles(paths);
    if (files.isEmpty) {
      addLog(.warning, '没有可分享的文件：$paths', tag: 'Share');
      return false;
    }
    // share_plus 在桌面端会退化成一个 mailto 链接，那不是这里的「分享」
    if (!Platform.isAndroid) {
      addLog(.info, '这个平台没有系统分享，$files', tag: 'Share');
      return false;
    }
    try {
      final result = await SharePlus.instance.share(
        buildShareParams(files, title: title, text: text),
      );
      return result.status == ShareResultStatus.success;
    } on Object catch (error) {
      addLog(.warning, '分享失败：${removeNewlines('$error')}', tag: 'Share');
      return false;
    }
  }

  /// 组装面板参数；单独拆出来是为了在用例里钉住「传了哪些文件」
  @visibleForTesting
  static ShareParams buildShareParams(
    List<String> paths, {
    String? title,
    String? text,
  }) {
    return ShareParams(
      files: [for (final path in paths) XFile(path)],
      title: title,
      text: text,
    );
  }

  /// 过滤掉已经不在的路径
  @visibleForTesting
  static List<String> existingFiles(List<String> paths) => [
    for (final path in paths)
      if (File(path).existsSync()) path,
  ];
}
