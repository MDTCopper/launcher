import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:system_info2/system_info2.dart' as s;
import 'package:win32/win32.dart';

/// 系统信息查询
///
/// 各平台取内存的方式：
/// - Windows：[GlobalMemoryStatusEx] 原生 API，一次取总 / 可用内存
/// - Linux / Android：直接读 `/proc/meminfo`
/// - macOS：system_info2（`vm_stat` / `sysctl`，轻量，用 isolate 防阻塞）

class SysInfo {
  /// Windows 总物理内存缓存
  static int? _totalMemoryCache;

  /// 总物理内存
  static Future<int> getTotalPhysicalMemory() async {
    if (Platform.isWindows) {
      return _totalMemoryCache ??= _windowsMemory().ullTotalPhys;
    }
    if (Platform.isLinux || Platform.isAndroid) {
      final info = _readProcMeminfo();
      return info.totalKiloBytes * 1024;
    }
    return _systemInfo2InIsolate(() => s.SysInfo.getTotalPhysicalMemory());
  }

  /// 可用物理内存（字节）：实时查询
  static Future<int> getFreePhysicalMemory() async {
    if (Platform.isWindows) {
      return _windowsMemory().ullAvailPhys;
    }
    if (Platform.isLinux || Platform.isAndroid) {
      final info = _readProcMeminfo();
      return info.freeKiloBytes * 1024;
    }
    return _systemInfo2InIsolate(() => s.SysInfo.getFreePhysicalMemory());
  }

  /// 可用物理内存
  static Future<int> getAvailablePhysicalMemory() async {
    if (Platform.isLinux || Platform.isAndroid) {
      final info = _readProcMeminfo();
      return info.availableKiloBytes * 1024;
    }
    return _systemInfo2InIsolate(() => s.SysInfo.getAvailablePhysicalMemory());
  }

  /// Linux / Android：读取 /proc/meminfo，一次解析总 / 可用 / 空闲内存
  ///
  /// 内容形如 `MemTotal:       32768508 kB`；[availableKiloBytes] 是
  /// MemAvailable（含可回收缓存），[freeKiloBytes] 是 MemFree（严格空闲）
  static ({int totalKiloBytes, int freeKiloBytes, int availableKiloBytes})
  _readProcMeminfo() {
    int valueOf(String key) {
      for (final line in File('/proc/meminfo').readAsLinesSync()) {
        if (line.startsWith(key)) {
          final parts = line.split(RegExp(r'\s+'));
          return parts.length > 1 ? int.parse(parts[1]) : 0;
        }
      }
      return 0;
    }

    return (
      totalKiloBytes: valueOf('MemTotal'),
      freeKiloBytes: valueOf('MemFree'),
      availableKiloBytes: valueOf('MemAvailable'),
    );
  }

  /// macOS 及其它平台：system_info2 通过进程查询，
  /// 放 isolate 执行避免阻塞 UI 线程
  static Future<R> _systemInfo2InIsolate<R>(R Function() callback) async {
    return compute<void, R>((_) => callback(), null);
  }

  /// Windows：调用 [GlobalMemoryStatusEx] 原生 API，一次拿到内存状态
  static MEMORYSTATUSEX _windowsMemory() {
    final status = calloc<MEMORYSTATUSEX>();
    try {
      status.ref.dwLength = sizeOf<MEMORYSTATUSEX>();
      GlobalMemoryStatusEx(status);
      return status.ref;
    } finally {
      calloc.free(status);
    }
  }
}
