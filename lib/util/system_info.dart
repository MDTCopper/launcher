import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:system_info2/system_info2.dart' as s;
import 'package:win32/win32.dart';

import 'cgroup_memory.dart';

/// 系统信息查询
///
/// 各平台取内存的方式：
/// - Windows：[GlobalMemoryStatusEx] 原生 API，一次取总 / 可用内存
/// - Android：宿主通道 `getMemoryInfo`（ActivityManager 语义，应用可用内存）；
///   失败回退 `/proc/meminfo`（物理内存全局值）
/// - Linux：直接读 `/proc/meminfo`
/// - macOS：system_info2（`vm_stat` / `sysctl`，轻量，用 isolate 防阻塞）
///
/// **Linux / Android 的 `/proc/meminfo` 报的是宿主内核的内存**，在容器 / 受限环境里
/// 比应用实际能用的大得多（WSL2、docker、Android 的 app cgroup 都这样）⇒
/// 一律再与 cgroup 限额取 min，见 [CgroupMemory]
class SysInfo {
  /// Windows 总物理内存缓存
  static int? _totalMemoryCache;

  /// 总物理内存
  static Future<int> getTotalPhysicalMemory() async {
    if (Platform.isWindows) {
      return _totalMemoryCache ??= _windowsMemory().ullTotalPhys;
    }
    if (Platform.isAndroid) {
      final total = (await _androidMemoryInfo())?.totalMem;
      if (total != null) return CgroupMemory.cap(total);
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
    if (Platform.isAndroid) {
      final available = (await _androidMemoryInfo())?.availMem;
      if (available != null) return available;
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

  /// 「可用」口径物理内存：供自动分配内存估算使用
  ///
  /// 各平台归一化（与 getFreePhysicalMemory / getAvailablePhysicalMemory 不同，
  /// 这里统一给「可被新增分配」的值）：
  /// - Windows：原生 [GlobalMemoryStatusEx] 的 `ullAvailPhys`（即可用物理）
  /// - Linux / Android：/proc/meminfo 的 `MemAvailable`（含可回收缓存）
  /// - macOS 及其它：system_info2 的 available（isolate 执行）
  static Future<int> getUsablePhysicalMemory() async {
    if (Platform.isWindows) {
      return _windowsMemory().ullAvailPhys;
    }
    if (Platform.isLinux || Platform.isAndroid) {
      final info = _readProcMeminfo();
      return info.availableKiloBytes * 1024;
    }
    return _systemInfo2InIsolate(() => s.SysInfo.getAvailablePhysicalMemory());
  }

  /// Android：ActivityManager 口径的内存信息；宿主异常时返回 null，
  /// 让调用方回退 `/proc/meminfo`
  static Future<MemorySnapshot?> _androidMemoryInfo() async {
    try {
      return await AndroidCall.getMemoryInfo();
    } on Object {
      return null;
    }
  }

  /// Linux / Android：读取 /proc/meminfo，一次解析总 / 可用 / 空闲内存
  ///
  /// 内容形如 `MemTotal:       32768508 kB`；[availableKiloBytes] 是
  /// MemAvailable（含可回收缓存），[freeKiloBytes] 是 MemFree（严格空闲）
  ///
  /// 三个值都先与 cgroup 限额取 min —— meminfo 报的是**宿主内核**的内存，
  /// 容器 / 受限环境里比应用实际能用的大
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

    int cappedKiloBytes(String key) =>
        CgroupMemory.cap(valueOf(key) * 1024) ~/ 1024;

    return (
      totalKiloBytes: cappedKiloBytes('MemTotal'),
      freeKiloBytes: cappedKiloBytes('MemFree'),
      availableKiloBytes: cappedKiloBytes('MemAvailable'),
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
