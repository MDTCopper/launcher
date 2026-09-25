import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/util/io/remote_data.dart';
import 'package:copper_launcher/util/math/range.dart';
import 'package:flutter/foundation.dart';

/// 模组版本门禁（remote/mmgvm.hjson）：游戏版本 → 该版本游戏要求的模组最低版本。
///
/// - 普通模组（脚本）门槛：[modThresholdOf]；Java 模组门槛：[javaThresholdOf]
/// - 数据来自 remote/mmgvm.hjson，可不发版更新（[loadFromRemote]）；
///   拉取失败 / 内容非法时保持现状
class MinGameVersions {
  MinGameVersions._();

  static final MinGameVersions instance = MinGameVersions._();

  /// 无上限（Range 要求 min < max，用 infinity 表示开上限）
  static const double _noUpperLimit = double.infinity;

  /// 内置默认：与 remote/mmgvm.hjson 同源
  static RangeModifier<double, int> get _builtinMod => RangeModifier(0, [
    RangeRuler(97, 105, 97),
    RangeRuler(105, 136, 105),
    RangeRuler(136, _noUpperLimit, 136),
  ]);

  static RangeModifier<double, int> get _builtinJava => RangeModifier(0, [
    RangeRuler(97, 105, 97),
    RangeRuler(105, 136, 105),
    RangeRuler(136, 147, 136),
    RangeRuler(147, 154.2, 147),
    RangeRuler(154.2, _noUpperLimit, 154),
  ]);

  RangeModifier<double, int> _mod = _builtinMod;

  RangeModifier<double, int> _java = _builtinJava;

  /// 普通模组（脚本）门槛规则
  RangeModifier<double, int> get mod => _mod;

  /// Java 模组门槛规则
  RangeModifier<double, int> get java => _java;

  /// [gameVersion] 对应游戏的普通模组（脚本）最低版本门槛
  int modThresholdOf(double gameVersion) => _mod.resultOf(gameVersion);

  /// [gameVersion] 对应游戏的 Java 模组最低版本门槛
  int javaThresholdOf(double gameVersion) => _java.resultOf(gameVersion);

  /// 从 remote / 本地缓存 / 内置 assets 读取 mmgvm 并应用
  ///
  /// 读取失败或内容非法时保持现状（内置默认或上一次成功的数据）
  Future<void> loadFromRemote() async {
    applyRemote(await RemoteData.load(mmgvmFile));
  }

  /// 应用 [content]（mmgvm.hjson 文本）；内容非法时保持现状
  void applyRemote(String? content) {
    final parsed = parse(content);
    if (parsed == null) return;
    _mod = parsed.mod;
    _java = parsed.java;
  }

  /// 解析 mmgvm 文本为 (普通模组规则, Java 模组规则)。
  ///
  /// 内容缺失、解析失败、规则为空或任一规则不合法时返回 null（保持现状）
  @visibleForTesting
  static ({RangeModifier<double, int> mod, RangeModifier<double, int> java})?
  parse(String? content) {
    if (content == null || content.isEmpty) return null;

    final dynamic decoded;
    try {
      decoded = decodeRemote(content);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final rules = decoded['rules'];
    if (rules is! List<dynamic> || rules.isEmpty) return null;

    final modRulers = <RangeRuler<double, int>>[];
    final javaRulers = <RangeRuler<double, int>>[];
    for (final item in rules) {
      if (item is! Map) return null;

      final min = _toDouble(item['min']);
      final max = _toDouble(item['max']);
      final mod = _toDouble(item['mod']);
      final java = _toDouble(item['java']);
      if (min == null || mod == null || java == null) return null;
      if (max != null && !(min < max)) return null;

      final upper = max ?? _noUpperLimit;
      modRulers.add(RangeRuler(min, upper, mod.round()));
      javaRulers.add(RangeRuler(min, upper, java.round()));
    }

    return (
      mod: RangeModifier(0, modRulers),
      java: RangeModifier(0, javaRulers),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}
