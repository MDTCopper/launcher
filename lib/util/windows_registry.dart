import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Windows 注册表的只读小工具（读一个字符串值），非 Windows 一律返回 null
///
/// 现在两处用它：显卡首选项（读已有值判断要不要写）与 Steam 安装路径探测；
/// **只读不写** —— 要写的那套（[GpuPreference]）自己带着 key 句柄与错误日志
class WindowsRegistry {
  WindowsRegistry._();

  /// 读 `HKCU\<subKey>` 下的一个值；项或值不存在都返回 null
  static String? readCurrentUser({
    required String subKey,
    required String valueName,
  }) => _openAndRead(
    root: HKEY_CURRENT_USER,
    subKey: subKey,
    valueName: valueName,
  );

  /// 读 `HKLM\<subKey>` 下的一个值；[wow64] 为 true 时走 32 位视图
  /// （Steam 的安装路径在 64 位系统上常常只在 `WOW6432Node` 那边）
  static String? readLocalMachine({
    required String subKey,
    required String valueName,
    bool wow64 = false,
  }) => _openAndRead(
    root: HKEY_LOCAL_MACHINE,
    subKey: subKey,
    valueName: valueName,
    wow64: wow64,
  );

  /// 从一个**已经打开的项**里读字符串值（`REG_SZ` / `REG_EXPAND_SZ` 都能读出来）
  static String? readValue(HKEY key, String valueName) {
    final name = valueName.toNativeUtf16();
    final size = calloc<Uint32>();
    try {
      var result = RegQueryValueEx(key, PCWSTR(name), nullptr, nullptr, size);
      if (result != ERROR_SUCCESS || size.value == 0) return null;

      final buffer = calloc<Uint8>(size.value);
      try {
        result = RegQueryValueEx(key, PCWSTR(name), nullptr, buffer, size);
        if (result != ERROR_SUCCESS) return null;
        return buffer.cast<Utf16>().toDartString();
      } finally {
        free(buffer);
      }
    } finally {
      free(name);
      free(size);
    }
  }

  static String? _openAndRead({
    required HKEY root,
    required String subKey,
    required String valueName,
    bool wow64 = false,
  }) {
    if (!Platform.isWindows) return null;

    final path = subKey.toNativeUtf16();
    final handle = calloc<Pointer>();
    try {
      final result = RegOpenKeyEx(
        root,
        PCWSTR(path),
        0,
        wow64 ? KEY_READ | KEY_WOW64_32KEY : KEY_READ,
        handle,
      );
      if (result != ERROR_SUCCESS) return null;

      final key = HKEY(handle.value);
      if (!key.isValid) return null;
      try {
        return readValue(key, valueName);
      } finally {
        key.close();
      }
    } catch (_) {
      // 注册表读不到不该影响调用方（探测类逻辑，缺了就按「没装」处理）
      return null;
    } finally {
      free(path);
      free(handle);
    }
  }
}
