// AUTO GENERATED FILE - DO NOT EDIT.
// 由 tool/android_bridge/generate.dart 依据 Dart @KotlinEvent / @KotlinData 生成。
// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。

package io.github.copper.launcher.generated

import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Android → Dart 的事件通道。
 *
 * 通道在 [attach] 时建一次，`send*` 不用再传 messenger。
 *
 * 事件载荷的结构体定义在 Dart（@KotlinData），这里的 `*Payload` 是生成的镜像：
 * 宿主构造它，发出去之前转成 Map。
 *
 * Dart 还没装 handler 时（冷启动）发送会失败，只记日志：真正的数据仍在
 * IncomingIntake 里，Dart 起来后会自己取。
 */
object AndroidEvent {
    private const val CHANNEL = "io.github.copper.launcher/flutter"
    private const val TAG = "AndroidEvent"

    /**
     * 每个活着的引擎一条通道，按 attach 顺序：发送取最后一条。
     *
     * 启动器同一进程里可能有不止一个 FlutterActivity（MainActivity / SilentLaunchActivity），
     * 各自一个引擎；单槽位会在一个销毁时把另一个的通道也带走。
     */
    private val channels = LinkedHashMap<BinaryMessenger, MethodChannel>()

    /** 接上引擎的 messenger；Activity 拿到引擎时调一次 */
    fun attach(messenger: BinaryMessenger) {
        channels[messenger] = MethodChannel(messenger, CHANNEL)
    }

    /**
     * 断开这条通道。
     *
     * Activity 销毁时必须调：静态 map 会一直持有 messenger，
     * 引擎比 Activity 活得久时就把旧实例留住了。
     */
    fun detach(messenger: BinaryMessenger) {
        channels.remove(messenger)
    }

    private fun send(name: String, payload: Any?) {
        val channel = channels.values.lastOrNull()
        if (channel == null) {
            Log.w(TAG, "通知 Dart 失败：通道还没接上（$name）")
            return
        }
        channel.invokeMethod(name, payload, logResult(name))
    }

    fun sendAuthCallback() = send("onAuthCallback", null)

    fun sendSharedFiles(
        files: List<String>,
    ) = send("onSharedFiles", listOf(files))

    fun sendShortcutLaunch(
        versionId: String,
        silent: Boolean,
    ) = send("onShortcutLaunch", listOf(versionId, silent))

    private fun logResult(name: String): MethodChannel.Result =
        object : MethodChannel.Result {
            override fun success(result: Any?) = Unit

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.w(TAG, "通知 Dart $name 失败：$errorMessage")
            }

            override fun notImplemented() {
                Log.w(TAG, "通知 Dart 失败：Dart 侧还没装 handler（$name）")
            }
        }
}
