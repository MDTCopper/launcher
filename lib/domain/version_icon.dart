import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:path/path.dart' as p;

/// 版本图标（玩家自己换的那张）的落盘与清理
///
/// 记录里存数据根内的相对路径；文件名按版本 id 生成，换图时旧文件一并删掉
class VersionIconStorage {
  VersionIconStorage._();

  /// 把 [sourcePath] 复制成这个版本的图标并写进 [Mindustry.iconPath]
  static Future<void> save(Mindustry version, String sourcePath) async {
    final directory = Directory(AppPaths.versionIcons);
    await directory.create(recursive: true);
    await _deleteFilesOf(version);
    final extension = p.extension(sourcePath).toLowerCase();
    final fileName = '${_safeName(version.id)}${extension.isEmpty ? '.png' : extension}';
    final target = File(p.join(directory.path, fileName));
    await target.writeAsBytes(await File(sourcePath).readAsBytes(), flush: true);
    version.iconPath = AppPaths.toStoredPath(target.path);
  }

  /// 恢复默认图标：删文件、清记录字段
  static Future<void> clear(Mindustry version) async {
    await _deleteFilesOf(version);
    version.iconPath = null;
  }

  static Future<void> _deleteFilesOf(Mindustry version) async {
    final directory = Directory(AppPaths.versionIcons);
    if (!await directory.exists()) return;
    final baseName = _safeName(version.id);
    await for (final entity in directory.list()) {
      if (entity is! File || p.basenameWithoutExtension(entity.path) != baseName) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {
        // 删不掉不影响换图；新文件会覆盖同名路径
      }
    }
  }

  /// 版本 id 理论上都是 uuid / 数字，保险起见把文件名里不安全的字符换掉
  static String _safeName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
