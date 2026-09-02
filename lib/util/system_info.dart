import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:jni_flutter/jni_flutter.dart';
import 'package:system_info2/system_info2.dart' as s;
import 'package:win32/win32.dart';

import '../util/loader_binding.dart';

/// 系统信息查询
///
/// 各平台取内存的方式：
/// - Windows：[GlobalMemoryStatusEx] 原生 API，一次取总 / 可用内存
/// - Android：Copper loader 的 [Loader.getMemoryInfo]（ActivityManager 语义，
///   应用可用内存）；失败回退 `/proc/meminfo`（物理内存全局值）
/// - Linux：直接读 `/proc/meminfo`
/// - macOS：system_info2（`vm_stat` / `sysctl`，轻量，用 isolate 防阻塞）
class SysInfo {
  /// Windows 总物理内存缓存
  static int? _totalMemoryCache;

  /// Android：Copper loader 的 App 上下文（单例，引用转让后缓存复用）
  static Context? _androidContext;

  /// 获取 Android 上下文：把 jni_flutter 的全局 [androidApplicationContext]
  /// 转成绑定类型。`releaseOriginal: true` 是引用转让——原 JObject 的 JNI
  /// 引用交给新的 [Context]，只转一次并缓存，避免重复转换 / 双释放
  static Context? _getAndroidContext() {
    if (_androidContext != null) return _androidContext;
    try {
      final context =
          androidApplicationContext.as(Context.type, releaseOriginal: true);
      _androidContext = context;
      return context;
    } catch (e) {
      return null;
    }
  }

  /// 总物理内存
  static Future<int> getTotalPhysicalMemory() async {
    if (Platform.isWindows) {
      return _totalMemoryCache ??= _windowsMemory().ullTotalPhys;
    }
    if (Platform.isAndroid) {
      final total = _androidTotalMemory();
      if (total != null) return total;
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
      final available = _androidAvailableMemory();
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

  /// Android：Copper loader 查询总内存（ActivityManager 语义），失败返回 null
  static int? _androidTotalMemory() {
    final info = _androidMemoryInfo();
    if (info == null) return null;
    final total = info.totalMem;
    info.release(); // 返回的 Java 对象用后即释放，避免 JNI 引用累积
    return total;
  }

  /// Android：Copper loader 查询可用内存，失败返回 null
  static int? _androidAvailableMemory() {
    final info = _androidMemoryInfo();
    if (info == null) return null;
    final available = info.availMem;
    info.release();
    return available;
  }

  /// Android：调 [Loader.getMemoryInfo] 拿内存信息对象（调用方负责 release）
  static Loader$MemoryInfo? _androidMemoryInfo() {
    final context = _getAndroidContext();
    if (context == null) return null;
    return Loader.getMemoryInfo(context);
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
