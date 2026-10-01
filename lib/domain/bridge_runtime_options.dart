import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/util/app_paths.dart';
import 'package:path/path.dart' as p;

/// 运行环境的「钉版本」设置：留空就是跟随最新
///
/// - [jreBuild]：爪住的 Java 运行环境构建号（release 里 `version` 文件的值），
///   钉住后即使远端出了新构建也不自动重下
/// - [bridgeTag]：钉住的桥版本（`snapshot` / `0.1.3`…）
///
/// 存在 `<数据根>/bridge/runtime.json`（与它描述的那份载荷放一起，
/// 清了运行环境这条记录留着也无妨 —— 下次装完还是这个选择）
class BridgeRuntimeOptions {
  BridgeRuntimeOptions({this.jreBuild, this.bridgeTag});

  String? jreBuild;
  String? bridgeTag;

  static String filePath({String? bridgeDir}) =>
      p.join(bridgeDir ?? AppPaths.bridge, 'runtime.json');

  /// 读本地设置；文件不在 / 坏了都当「跟随最新」，不抛
  static BridgeRuntimeOptions load({String? bridgeDir}) {
    final file = File(filePath(bridgeDir: bridgeDir));
    if (!file.existsSync()) return BridgeRuntimeOptions();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return BridgeRuntimeOptions();
      String? read(String key) {
        final value = decoded[key];
        return value is String && value.isNotEmpty ? value : null;
      }

      return BridgeRuntimeOptions(
        jreBuild: read('jreBuild'),
        bridgeTag: read('bridgeTag'),
      );
    } catch (_) {
      return BridgeRuntimeOptions();
    }
  }

  Future<void> save({String? bridgeDir}) async {
    final file = File(filePath(bridgeDir: bridgeDir));
    await file.parent.create(recursive: true);
    final data = <String, dynamic>{
      if (jreBuild != null) 'jreBuild': jreBuild,
      if (bridgeTag != null) 'bridgeTag': bridgeTag,
    };
    await file.writeAsString(jsonEncode(data));
  }

  /// 有没有钉住任何一项
  bool get hasPin => jreBuild != null || bridgeTag != null;
}
