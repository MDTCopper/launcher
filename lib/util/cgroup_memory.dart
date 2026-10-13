import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// cgroup 给本进程的内存限额
///
/// 用来给 `/proc/meminfo` 的读数打补丁：容器 / 受限环境里 meminfo 报的是**宿主内核**
/// 的内存，比应用实际能用的大得多（WSL2、docker、Android 的 app cgroup 都这样）
/// ⇒ 读出来的值一律再与这里取 min
class CgroupMemory {
  CgroupMemory._();

  /// 限额文件（按优先级）：v2 一个，v1 一个
  static const _limitFiles = [
    // v2（新发行版与 WSL2）：无限制时文件里写 `max`
    '/sys/fs/cgroup/memory.max',
    // v1：无限制时给一个接近 LONG_MAX 的天文数字
    '/sys/fs/cgroup/memory/memory.limit_in_bytes',
  ];

  /// 比它大的一律当「没有限额」（v1 的无限制写法是 `LONG_MAX` 对齐到页）
  static const _noLimitThreshold = 1 << 62;

  /// 内存限额（字节）；没有限额（含读不到）返回 null
  static int? limitBytes() {
    for (final path in _limitFiles) {
      try {
        final file = File(path);
        if (!file.existsSync()) continue;
        final limit = parseLimit(file.readAsStringSync());
        if (limit != null) return limit;
      } on Object {
        // 读不出来就换下一个候选：内存查询本身不该变成错误
      }
    }
    return null;
  }

  /// [bytes] 与限额取小的那个；没有限额时原样返回
  static int cap(int bytes) {
    final limit = limitBytes();
    return (limit != null && limit < bytes) ? limit : bytes;
  }

  /// 解析限额文件的内容（纯函数，便于用例）
  ///
  /// 空内容、v2 的无限制写法 `max`、v1 那个接近 `LONG_MAX` 的天文数字，
  /// 以及解析不出数字的内容，一律算「没有限额」
  @visibleForTesting
  static int? parseLimit(String content) {
    final text = content.trim();
    if (text.isEmpty || text == 'max') return null;
    final value = int.tryParse(text);
    if (value == null || value <= 0 || value >= _noLimitThreshold) return null;
    return value;
  }
}
