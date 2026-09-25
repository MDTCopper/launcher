import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/mindustry/settings.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;
import 'package:copper_launcher/util/format/string_cleaner.dart';

/// 自动分配内存估算
///
/// Mindustry 官方没有自动分配逻辑（属启动器看门人的职责）
/// 分档收紧思路，但默认比例放温和：
/// - 基准：可用内存的 30%
/// - mod 下限：标准 512MB + 各启用 mod 体积 ×2 之和；基准比它小则取它
/// - 收尾：预留 512MB 给堆外/图形；可用内存不够则全分配；
///   再按可用大小分档收紧，封顶 8GB
class AutoMemory {
  /// 基准比例：可用内存的 30%（温和默认）
  static const double _baseRatio = 0.3;

  /// 堆外/图形 + 启动器自身预留
  static const int _reserveBytes = 512 * MB;

  /// mod 下限的基准标准内存（Mindustry 本体跑起来的最低堆）
  static const int _modBaseBytes = 512 * MB;

  /// mod 体积放大系数（加载进堆的内容比文件体积更大）
  static const int _modFactor = 2;

  /// 分档阈值：可用内存 ≤ 8GB 用较宽松比例，超出部分减速
  static const int _thresholdBytes = 8 * GB;

  /// 可用内存 ≤ 阈值时的上限比例
  static const double _tightRatio = 0.8;

  /// 超出阈值部分的上限比例
  static const double _excessRatio = 0.2;

  /// 自动分配硬上限（均衡 8GB）
  static const int _hardLimitBytes = 8 * GB;

  /// 估算自动分配的最大堆内存（字节）。
  ///
  /// [availableBytes] 为平台归一化的可用物理内存；
  /// [enabledModTotalBytes] 为所有启用 mod 文件体积之和。
  static Memory estimate({
    required int availableBytes,
    required int enabledModTotalBytes,
  }) {
    // mod 下限：标准 512MB + 各 mod 体积 ×2 之和
    final modFloorBytes = _modBaseBytes + enabledModTotalBytes * _modFactor;

    // 基准：可用内存的 30%
    final baseBytes = (availableBytes * _baseRatio).round();

    // 混合基准：取基准与 mod 下限的较大者
    var suggestedBytes = max(baseBytes, modFloorBytes);

    // 收尾：预留堆外；可用内存不够则全分配
    final usableBytes = availableBytes - _reserveBytes;
    if (usableBytes <= 0) {
      return Memory(bytes: availableBytes);
    }

    // 分档收紧：可用 ≤ 阈值用 80%，超出部分 20%，再封顶硬上限

    int cap;
    if (usableBytes <= _thresholdBytes) {
      cap = (usableBytes * _tightRatio).round();
    } else {
      cap =
          ((_thresholdBytes * _tightRatio) +
                  (usableBytes - _thresholdBytes) * _excessRatio)
              .round();
    }

    cap = min(cap, _hardLimitBytes);

    suggestedBytes = min(cap, suggestedBytes);

    return Memory(bytes: suggestedBytes);
  }
}

/// 统计多个模组目录里启用模组的体积之和
///
/// 走加载器时模组分两个目录（`copper/mods` 与原版 `mods`），内存估算要把两边都算上
Future<int> sumEnabledModSizesIn(
  List<String> modsPaths, {
  String? settingsPath,
}) async {
  var total = 0;
  for (final modsPath in modsPaths) {
    total += await sumEnabledModSizes(modsPath, settingsPath: settingsPath);
  }
  return total;
}

/// 统计 mods 目录下所有启用 mod 的文件体积之和（字节）。
///
/// 传入 [settingsPath]（settings.bin）时按游戏启用状态判断：
/// `mod-<internalName>-enabled` 键为准、未记录则按文件名兜底（`.disable` 为禁用）；
/// 不传或解析失败时仅按文件名（不带 `.disable` 的 jar/zip）判断。
Future<int> sumEnabledModSizes(String modsPath, {String? settingsPath}) async {
  final dir = Directory(modsPath);
  if (!dir.existsSync()) return 0;

  // settings.bin 的启用状态（键为 mod 内部名）；读取失败回退文件名判断
  Map<String, bool>? settingsStates;
  if (settingsPath != null) {
    final settingsFile = File(settingsPath);
    if (await settingsFile.exists()) {
      try {
        settingsStates = MindustrySettings.fromFile(
          settingsFile.path,
        ).modStates;
      } catch (e) {
        addLogAndPrint(.warning, '读取模组启用状态失败，按文件名判断：${removeNewlines('$e')}', tag: 'Memory');
      }
    }
  }

  var total = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    // 统一剥 .disable 后缀判断 jar/zip；禁用文件也遍历，便于按 settings 判定
    final disabled = name.endsWith('.disable');
    final baseName = disabled
        ? name.substring(0, name.length - '.disable'.length)
        : name;
    if (!baseName.endsWith('.jar') && !baseName.endsWith('.zip')) continue;

    bool enabled;
    if (settingsStates != null) {
      final reader = await FileReader.fromPath(entity.path);
      final mod = reader.mod;
      if (mod == null) continue; // 解析不出内部名，无法对应启用状态，不计入
      enabled = settingsStates[mod.internalName] ?? !disabled;
    } else {
      enabled = !disabled;
    }
    if (!enabled) continue;

    total += await entity.length();
  }
  return total;
}
