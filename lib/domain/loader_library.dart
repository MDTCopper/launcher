import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/app_paths.dart';

/// 模组加载器库（`<数据根>/copper_loader/`）：loader jar 集中放这里，
/// 多个版本复用同一份，与本体库 [AppPaths.mindustrys] 是同一套思路
///
/// 现在只有 Copper 一家；以后接别的加载器时按同样的方式扩展（键是 loader 类型）
class LoaderLibrary {
  /// 收进库里：同名文件已存在就直接复用，否则复制过去
  ///
  /// 返回库内文件的**绝对路径**（调用方按记录形态存进版本里）
  static Future<String> importIntoLibrary(File source) async {
    final libraryDir = Directory(AppPaths.copperLoader);
    await libraryDir.create(recursive: true);
    final target = File(p.join(libraryDir.path, p.basename(source.path)));
    if (!await target.exists()) {
      await source.copy(target.path);
    }
    return target.path;
  }

  /// 库里现有的 loader jar（按文件名升序）
  static List<File> list() {
    final libraryDir = Directory(AppPaths.copperLoader);
    if (!libraryDir.existsSync()) return const [];
    final jars =
        libraryDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.jar'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return jars;
  }

  /// 没指定 loader 时的兜底：库里第一个可用的 loader
  ///
  /// （loader 版本适配表还没做，先按文件名取第一个；将来按游戏版本挑）
  static String? fallbackPath() {
    final jars = list();
    return jars.isEmpty ? null : jars.first.path;
  }

  /// 取可用的 loader：优先 [recordedPath] 指定的（文件真在才算），其次库里第一个
  static String? usablePath(String? recordedPath) {
    if (recordedPath != null && File(recordedPath).existsSync()) {
      return recordedPath;
    }
    return fallbackPath();
  }

  /// 从文件名里读 loader 版本：`desktop-0.1.1.jar` → `0.1.1`
  ///
  /// 取不到就返回 null（版本适配表做出来之前，版本号只用于展示与排查）
  static String? versionOf(File loader) {
    final name = p.basenameWithoutExtension(loader.path);
    final matched = RegExp(r'(\d+(?:\.\d+)*)$').firstMatch(name)?.group(1);
    return matched;
  }
}
