// AUTO GENERATED FILE - DO NOT EDIT.
// 由 tool/android_bridge/generate.dart 依据 Kotlin @DartCall / @DartAsyncCall 生成。
// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。
@file:Suppress("UNCHECKED_CAST")

package io.github.copper.launcher.generated

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.github.copper.launcher.game.GameProcess
import io.github.copper.launcher.intent.IncomingIntake
import io.github.copper.launcher.launch.Bridge
import io.github.copper.launcher.launch.Loader
import io.github.copper.launcher.shortcut.GameShortcut
import io.github.copper.launcher.shortcut.GameWidget
import io.github.copper.launcher.system.HeapLimits
import io.github.copper.launcher.system.MemorySnapshot
import io.github.copper.launcher.system.SystemInfo
import io.github.copper.launcher.ui.LauncherWindow
import io.github.copper.launcher.ui.SilentLaunchOverlay

/**
 * Dart → Android 的调用通道。
 *
 * [register] 的 handler 捕获了 [activity]：Activity 销毁时调用方必须 [clear]，
 * 否则引擎比 Activity 活得久时会把旧 Activity 一直留在内存里。
 *
 * 结构体（@DartData）过通道是 Map：返回值转 `toBridgeMap()`，参数按字段还原。
 */
object AndroidCall {
    private const val CHANNEL = "io.github.copper.launcher/android"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val args = call.arguments as? List<Any?> ?: emptyList()
            when (call.method) {
                "buildLoader" -> {
                    Thread {
                        try {
                            Loader.buildLoader(args[0] as String, (args[1] as List<String>).toTypedArray())
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        } catch (error: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("call_failed", error.message, null)
                            }
                        }
                    }.start()
                }
                "finishLauncher" -> {
                    try {
                        LauncherWindow.finishLauncher(activity)
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "getHeapMemoryInfo" -> {
                    try {
                        result.success(SystemInfo.getHeapMemoryInfo(activity.applicationContext)?.toBridgeMap())
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "getMemoryInfo" -> {
                    try {
                        result.success(SystemInfo.getMemoryInfo(activity.applicationContext)?.toBridgeMap())
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "hide" -> {
                    try {
                        SilentLaunchOverlay.hide()
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "isGameActivityVisible" -> {
                    try {
                        result.success(GameProcess.isGameActivityVisible(activity.applicationContext))
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "isGameProcessRunning" -> {
                    Thread {
                        try {
                            val value = GameProcess.isGameProcessRunning(activity.applicationContext)
                            Handler(Looper.getMainLooper()).post { result.success(value) }
                        } catch (error: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("call_failed", error.message, null)
                            }
                        }
                    }.start()
                }
                "killGameProcess" -> {
                    Thread {
                        try {
                            GameProcess.killGameProcess(activity.applicationContext)
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        } catch (error: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("call_failed", error.message, null)
                            }
                        }
                    }.start()
                }
                "launchBridge" -> {
                    try {
                        Bridge.launchBridge(args[0] as String, activity, (args[1] as List<String>).toTypedArray())
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "launchLoader" -> {
                    try {
                        Loader.launchLoader(args[0] as String, activity, (args[1] as List<String>).toTypedArray())
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "moveTaskToBack" -> {
                    try {
                        result.success(LauncherWindow.moveTaskToBack(activity))
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "requestPinShortcut" -> {
                    try {
                        result.success(GameShortcut.requestPinShortcut(activity, args[0] as String, args[1] as String, args[2] as String, args[3] as String))
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "requestPinWidget" -> {
                    try {
                        result.success(GameWidget.requestPinWidget(activity, args[0] as String, args[1] as String, args[2] as String, args[3] as String))
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "takeAuthUri" -> {
                    try {
                        result.success(IncomingIntake.takeAuthUri())
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "takeLaunchRequest" -> {
                    try {
                        result.success(IncomingIntake.takeLaunchRequest())
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                "takeSharedFiles" -> {
                    try {
                        result.success(IncomingIntake.takeSharedFiles())
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun clear(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(null)
    }

    private fun HeapLimits.toBridgeMap(): Map<String, Any?> = mapOf(
        "normalSize" to normalSize,
        "largeSize" to largeSize,
    )


    private fun MemorySnapshot.toBridgeMap(): Map<String, Any?> = mapOf(
        "availMem" to availMem,
        "lowMemory" to lowMemory,
        "threshold" to threshold,
        "totalMem" to totalMem,
    )

}
