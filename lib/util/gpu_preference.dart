import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'io/log.dart';
import 'windows_registry.dart';

/// 「使用高性能显卡」在各平台的落地
///
/// 同一件事在三个平台不是一个语义，所以这里按平台各给一条路：
/// - **Windows**：系统级的开关是「按可执行文件记的图形性能首选项」
///   （`HKCU\Software\Microsoft\DirectX\UserGpuPreferences` 里 `值名=exe 路径`、
///   数据 `GpuPreference=2;`），等价于系统设置里给那个程序选「高性能」。
///   游戏是 `java.exe -jar` 起的，所以认的是选中的那个 java.exe
/// - **Linux**：没有系统级开关，靠启动时的环境变量让游戏走独显
///   （Mesa 的 `DRI_PRIME`、NVIDIA 的 PRIME 卸载那对变量）
/// - **Android**：桥那边只有 GL 版本可选（`--gl3` / `--gl2`），由调用方传参
class GpuPreference {
  GpuPreference._();

  /// 注册表里那一项的路径（按可执行文件记的图形性能首选项）
  static const registryKey = r'Software\Microsoft\DirectX\UserGpuPreferences';

  /// 「高性能」在注册表里的取值（Windows 自己写的也是这个字符串）
  static const highPerformanceValue = 'GpuPreference=2;';

  /// Windows：这项现在是不是已经是我们想要的值（一致就不必再写注册表）
  ///
  /// [current] 是注册表里现有的数据；关掉时我们要的是「没有这一项」
  static bool registryValueMatches({
    required String? current,
    required bool preferHighPerformance,
  }) {
    if (preferHighPerformance) return current == highPerformanceValue;
    return current == null;
  }

  /// Linux：起游戏时该带的环境变量；其它平台返回空表
  ///
  /// 两套变量一起给（驱动不在时会被忽略）：Mesa 认 `DRI_PRIME`，
  /// NVIDIA 认 `__NV_PRIME_RENDER_OFFLOAD` + `__GLX_VENDOR_LIBRARY_NAME`
  static Map<String, String> launchEnvironment({
    required bool preferHighPerformance,
  }) {
    if (!Platform.isLinux || !preferHighPerformance) return const {};
    return const {
      'DRI_PRIME': '1',
      '__NV_PRIME_RENDER_OFFLOAD': '1',
      '__GLX_VENDOR_LIBRARY_NAME': 'nvidia',
    };
  }

  /// Windows：把「用高性能 GPU 跑这个程序」写进系统设置；关掉时删掉这一项（回到系统默认）
  ///
  /// 只在 Windows 上有效，其它平台直接返回；注册表里已经是目标状态就不写
  static void applyToExecutable({
    required String executablePath,
    required bool preferHighPerformance,
  }) {
    if (!Platform.isWindows || executablePath.isEmpty) return;
    if (!File(executablePath).existsSync()) return;

    final keyPath = registryKey.toNativeUtf16();
    final keyHandle = calloc<Pointer>();
    try {
      final result = RegCreateKeyEx(
        HKEY_CURRENT_USER,
        PCWSTR(keyPath),
        null,
        REG_OPTION_NON_VOLATILE,
        KEY_SET_VALUE | KEY_QUERY_VALUE,
        nullptr,
        keyHandle,
        nullptr,
      );
      final key = HKEY(keyHandle.value);
      if (result != ERROR_SUCCESS || !key.isValid) {
        addLogAndPrint(
          .warning,
          '写显卡首选项失败：打不开注册表项（错误码 $result）',
          tag: 'GPU',
        );
        return;
      }

      try {
        final current = _readValue(key, executablePath);
        if (registryValueMatches(
          current: current,
          preferHighPerformance: preferHighPerformance,
        )) {
          return;
        }

        if (preferHighPerformance) {
          final writeResult = _writeValue(key, executablePath);
          if (writeResult != ERROR_SUCCESS) {
            addLogAndPrint(
              .warning,
              '写显卡首选项失败：写注册表出错（错误码 $writeResult）',
              tag: 'GPU',
            );
            return;
          }
        } else {
          RegDeleteValue(key, PCWSTR(executablePath.toNativeUtf16()));
        }
        addLogAndPrint(
          .info,
          '显卡首选项：${preferHighPerformance ? '高性能' : '清除'}（$executablePath）',
          tag: 'GPU',
        );
      } finally {
        key.close();
      }
    } finally {
      free(keyHandle);
      free(keyPath);
    }
  }

  /// 读注册表里某个 exe 的首选项；没有这一项返回 null
  static String? _readValue(HKEY key, String executablePath) =>
      WindowsRegistry.readValue(key, executablePath);

  /// 写 `GpuPreference=2;`（REG_SZ，长度含结尾的那个空字符）
  static WIN32_ERROR _writeValue(HKEY key, String executablePath) {
    final valueName = executablePath.toNativeUtf16();
    final data = highPerformanceValue.toNativeUtf16();
    try {
      return RegSetValueEx(
        key,
        PCWSTR(valueName),
        REG_SZ,
        data.cast<Uint8>(),
        (highPerformanceValue.length + 1) * 2,
      );
    } finally {
      free(valueName);
      free(data);
    }
  }
}
