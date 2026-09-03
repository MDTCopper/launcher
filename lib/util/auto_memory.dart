import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:path/path.dart' as p;

/// 自动分配内存估算。
///
/// Mindustry 官方没有自动分配逻辑（属启动器看门人的职责），这里参考 HMCL 的
/// 分档收紧思路，但默认比例放温和：
/// - 基准：可用内存的 30%
/// - mod 下限：标准 512MB + 各启用 mod 体积 ×2 之和；基准比它小则取它
/// - 收尾（HMCL 式）：预留 512MB 给堆外/图形 + 启动器自身；可用内存不够则全分配；
///   再按可用大小分档收紧，封顶 8GB
class AutoMemory {
  /// 基准比例：可用内存的 30%（温和默认）
  static const double _baseRatio = 0.3;

  /// 堆外/图形 + 启动器自身预留（HMCL 式）
  static const int _reserveBytes = 512 * 1024 * 1024;

  /// mod 下限的基准标准内存（Mindustry 本体跑起来的最低堆）
  static const int _modBaseBytes = 512 * 1024 * 1024;

  /// mod 体积放大系数（加载进堆的内容比文件体积更大）
  static const int _modFactor = 2;

  /// 分档阈值：可用内存 ≤ 8GB 用较宽松比例，超出部分减速
  static const int _thresholdBytes = 8 * 1024 * 1024 * 1024;

  /// 可用内存 ≤ 阈值时的上限比例（HMCL 式收紧）
  static const double _tightRatio = 0.8;

  /// 超出阈值部分的上限比例（HMCL 式，递减）
  static const double _excessRatio = 0.2;

  /// 自动分配硬上限（均衡 8GB）
  static const int _hardLimitBytes = 8 * 1024 * 1024 * 1024;

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
    var suggestedBytes = baseBytes > modFloorBytes ? baseBytes : modFloorBytes;

    // 收尾：预留堆外；可用内存不够则全分配
    final usableBytes = availableBytes - _reserveBytes;
    if (usableBytes <= 0) {
      return Memory(bytes: availableBytes);
    }

    // 分档收紧：可用 ≤ 阈值用 80%，超出部分 20%，再封顶硬上限
    int capBytes;
    if (usableBytes <= _thresholdBytes) {
      capBytes = (usableBytes * _tightRatio).round();
    } else {
      capBytes = ((_thresholdBytes * _tightRatio) +
              (usableBytes - _thresholdBytes) * _excessRatio)
          .round();
    }
    if (capBytes > _hardLimitBytes) {
      capBytes = _hardLimitBytes;
    }

    if (suggestedBytes > capBytes) {
      suggestedBytes = capBytes;
    }

    return Memory(bytes: suggestedBytes);
  }
}

/// 统计 mods 目录下所有启用 mod 的文件体积之和（字节）。
///
/// 版本设置页的启停是「文件名追加 `.disable`」双保险，所以文件名不带
/// `.disable` 的 `.jar` / `.zip` 就视为启用态（无需解析 settings.bin）。
Future<int> sumEnabledModSizes(String modsPath) async {
  final dir = Directory(modsPath);
  if (!dir.existsSync()) return 0;

  var total = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name.endsWith('.disable')) continue;
    if (!name.endsWith('.jar') && !name.endsWith('.zip')) continue;
    total += await entity.length();
  }
  return total;
}
