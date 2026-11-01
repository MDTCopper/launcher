// AUTO GENERATED FILE - DO NOT EDIT.
// 由 tool/android_bridge/generate.dart 依据 @DartCall / @DartAsyncCall / @DartData 生成。
// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 非安卓平台没有宿主通道：这里统一短路，调用点不用各自判断平台。
///
/// 用 defaultTargetPlatform 而不是 dart:io 的 Platform：生成物不碰 dart:io。
bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

/// Dart → Android 的调用通道
///
/// 每个方法对应 Kotlin 侧一个 @DartCall / @DartAsyncCall 静态方法；
/// Activity 与其应用上下文由宿主注入，这里只传业务参数。
/// 结构体（@DartData）过通道就是 Map：Dart 侧传 `toMap()`，收 `fromMap()`。
class AndroidCall {
  AndroidCall._();

  static const _channel = MethodChannel(
    'io.github.copper.launcher/android',
    StandardMethodCodec(),
  );

  static Future<void> buildLoader(String loaderPath, List<String> args) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('buildLoader', <Object?>[loaderPath, args]);
  }

  static Future<void> finishLauncher() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('finishLauncher');
  }

  static Future<HeapLimits?> getHeapMemoryInfo() async {
    if (!_isAndroid) return null;
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('getHeapMemoryInfo');
    return map == null ? null : HeapLimits.fromMap(map);
  }

  static Future<MemorySnapshot?> getMemoryInfo() async {
    if (!_isAndroid) return null;
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('getMemoryInfo');
    return map == null ? null : MemorySnapshot.fromMap(map);
  }

  static Future<void> hide() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('hide');
  }

  static Future<bool> isGameActivityVisible() async {
    if (!_isAndroid) return false;
    return await _channel.invokeMethod<bool>('isGameActivityVisible') ?? false;
  }

  static Future<bool?> isGameProcessRunning() async {
    if (!_isAndroid) return null;
    return await _channel.invokeMethod<bool>('isGameProcessRunning');
  }

  static Future<void> killGameProcess() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('killGameProcess');
  }

  static Future<void> launchBridge(String bridgePath, List<String> args) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('launchBridge', <Object?>[bridgePath, args]);
  }

  static Future<void> launchLoader(String loaderPath, List<String> args) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('launchLoader', <Object?>[loaderPath, args]);
  }

  static Future<bool> moveTaskToBack() async {
    if (!_isAndroid) return false;
    return await _channel.invokeMethod<bool>('moveTaskToBack') ?? false;
  }

  static Future<bool> requestPinShortcut(String versionId, String tag, String jarPath, String iconPath) async {
    if (!_isAndroid) return false;
    return await _channel.invokeMethod<bool>('requestPinShortcut', <Object?>[versionId, tag, jarPath, iconPath]) ?? false;
  }

  static Future<bool> requestPinWidget(String versionId, String tag, String jarPath, String iconPath) async {
    if (!_isAndroid) return false;
    return await _channel.invokeMethod<bool>('requestPinWidget', <Object?>[versionId, tag, jarPath, iconPath]) ?? false;
  }

  static Future<String?> takeAuthUri() async {
    if (!_isAndroid) return null;
    return await _channel.invokeMethod<String>('takeAuthUri');
  }

  static Future<String?> takeLaunchRequest() async {
    if (!_isAndroid) return null;
    return await _channel.invokeMethod<String>('takeLaunchRequest');
  }

  static Future<List<String>> takeSharedFiles() async {
    if (!_isAndroid) return const <String>[];
    return (await _channel.invokeMethod<List<Object?>>('takeSharedFiles'))?.cast<String>() ??
        const <String>[];
  }
}

/// Kotlin data class HeapLimits 的 Dart 镜像（io.github.copper.launcher.system）
///
/// 定义只在 Kotlin 的 @DartData 那一处；这里不要手改。
class HeapLimits {
  const HeapLimits({
    required this.normalSize,
    required this.largeSize,
  });

  factory HeapLimits.fromMap(Map<Object?, Object?> map) => HeapLimits(
    normalSize: map['normalSize'] as int,
    largeSize: map['largeSize'] as int,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'normalSize': normalSize,
    'largeSize': largeSize,
  };

  final int normalSize;
  final int largeSize;
}


/// Kotlin data class MemorySnapshot 的 Dart 镜像（io.github.copper.launcher.system）
///
/// 定义只在 Kotlin 的 @DartData 那一处；这里不要手改。
class MemorySnapshot {
  const MemorySnapshot({
    required this.availMem,
    required this.lowMemory,
    required this.threshold,
    required this.totalMem,
  });

  factory MemorySnapshot.fromMap(Map<Object?, Object?> map) => MemorySnapshot(
    availMem: map['availMem'] as int,
    lowMemory: map['lowMemory'] as bool,
    threshold: map['threshold'] as int,
    totalMem: map['totalMem'] as int,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'availMem': availMem,
    'lowMemory': lowMemory,
    'threshold': threshold,
    'totalMem': totalMem,
  };

  final int availMem;
  final bool lowMemory;
  final int threshold;
  final int totalMem;
}

