import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// 运行环境的「钉版本」设置：留空就是跟随最新
///
/// - [jreVersion]：钉住的 Java **大版本**（`17` / `25` …，对应上游 tag `jre17` / `jre25`），
///   钉住后启动时缺哪份装哪份，不会跟着上游换构建重下
/// - [bridgeTag]：钉住的桥版本（`snapshot` / `0.1.3`…）
/// - [wrapperVersion]：钉住的模组加载器适配层版本（`0.1.0`…），留空就自动挑与当前
///   loader 兼容的最新一份
///
/// 存在 `<数据根>/bridge/runtime.json`（与它描述的那份载荷放一起，
/// 清了运行环境这条记录留着也无妨 —— 下次装完还是这个选择）
///
/// 旧版本这里存的是 `jreBuild`（上游 release `version` 文件的构建号）。构建号不当版本用，
/// 读到旧键直接忽略：JRE 库会按 `release` 文件把已装的那份归位到 `java/<大版本>`，
/// 选择的语义回到「跟随最新」。
class BridgeRuntimeOptions {
  BridgeRuntimeOptions({this.jreVersion, this.bridgeTag, this.wrapperVersion});

  String? jreVersion;
  String? bridgeTag;
  String? wrapperVersion;

  static String filePath({String? bridgeDirPath}) =>
      p.join(bridgeDirPath ?? AppPaths.bridge, 'runtime.json');

  /// 读本地设置；文件不在 / 坏了都当「跟随最新」，不抛
  static BridgeRuntimeOptions load({String? bridgeDirPath}) {
    final file = File(filePath(bridgeDirPath: bridgeDirPath));
    if (!file.existsSync()) return BridgeRuntimeOptions();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return BridgeRuntimeOptions();
      String? read(String key) {
        final value = decoded[key];
        return value is String && value.isNotEmpty ? value : null;
      }

      /// Java 大版本只收纯数字：手改坏的值当没钉，避免拼出 jre<乱码> 的下载地址
      String? readVersion() {
        final value = read('jreVersion');
        return value != null && RegExp(r'^\d+$').hasMatch(value) ? value : null;
      }

      return BridgeRuntimeOptions(
        jreVersion: readVersion(),
        bridgeTag: read('bridgeTag'),
        wrapperVersion: read('wrapperVersion'),
      );
    } catch (_) {
      return BridgeRuntimeOptions();
    }
  }

  Future<void> save({String? bridgeDirPath}) async {
    final file = File(filePath(bridgeDirPath: bridgeDirPath));
    await file.parent.create(recursive: true);
    final data = <String, dynamic>{
      if (jreVersion != null) 'jreVersion': jreVersion,
      if (bridgeTag != null) 'bridgeTag': bridgeTag,
      if (wrapperVersion != null) 'wrapperVersion': wrapperVersion,
    };
    await file.writeAsString(jsonEncode(data));
  }

  /// 有没有钉住任何一项
  bool get hasPin =>
      jreVersion != null || bridgeTag != null || wrapperVersion != null;
}
