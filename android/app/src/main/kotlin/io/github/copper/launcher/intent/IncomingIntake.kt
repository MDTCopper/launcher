package io.github.copper.launcher.intent

import android.content.Context
import android.content.Intent
import io.github.copper.launcher.channel.DartCall
import io.github.copper.launcher.shortcut.GameShortcut

/**
 * 外部 intent 的解析与暂存。
 *
 * 只做「收下、攒着、等 Dart 来取」，不碰窗口：Activity 负责把这里返回的
 * [Incoming] 转成静默黑幕之类的界面动作。冷启动时 Dart 还没接线，所以事件
 * 发不出去也无所谓，Dart 起来后会主动来取。
 *
 * 做成 object 是为了让 `take*` 能作为静态方法接进生成通道；状态只有应用上下文
 * 与待取数据，不持有 Activity，所以随进程存续是安全的。
 */
object IncomingIntake {
    private var shareHandler: ShareIntentHandler? = null
    private var pendingAuthUri: String? = null
    private var pendingLaunchVersionId: String? = null

    /** 绑定应用上下文；重复调用无害（Activity 重建时会再调一次） */
    fun attach(applicationContext: Context) {
        if (shareHandler == null) {
            shareHandler = ShareIntentHandler(applicationContext.applicationContext)
        }
    }

    /**
     * 处理一次外部 intent；返回非 [Incoming.None] 时调用方负责通知 Dart / 处理界面
     *
     * 分享的文件要在后台复制，所以这类 intent 返回 [Incoming.None]：复制完在主线程回调 [onShared]
     */
    fun handle(intent: Intent?, onShared: (List<String>) -> Unit): Incoming {
        if (intent == null) return Incoming.None

        if (intent.action == GameShortcut.ACTION_LAUNCH_GAME) {
            val versionId = intent.getStringExtra(GameShortcut.EXTRA_VERSION_ID).orEmpty()
            pendingLaunchVersionId = versionId
            // 老快捷方式没有 silent 标记；LAUNCH_GAME 只可能来自快捷方式/小组件，默认静默
            val silent = intent.getBooleanExtra(GameShortcut.EXTRA_SILENT, true)
            return Incoming.Launch(versionId, silent)
        }

        if (intent.action == Intent.ACTION_VIEW) {
            val data = intent.data
            // 新协议 copper://；copperlauncher:// 是旧清单留下的兼容入口，
            // 服务端回调白名单切换期间两个都接
            val scheme = data?.scheme?.lowercase()
            if (data != null &&
                (scheme == "copper" || scheme == "copperlauncher") &&
                data.host == "oauth"
            ) {
                pendingAuthUri = data.toString()
                return Incoming.Auth
            }
        }

        // 复制与通知都在 accept 里排好：界面动作与通知 Dart 都留在调用方的 [onShared]
        shareHandler?.accept(intent, onShared)
        return Incoming.None
    }

    /** 取走待处理的登录回调 URI；没有就 null */
    @DartCall
    fun takeAuthUri(): String? {
        val value = pendingAuthUri
        pendingAuthUri = null
        return value
    }

    /** 取走待处理的快捷方式启动版本 id；没有就 null */
    @DartCall
    fun takeLaunchRequest(): String? {
        val value = pendingLaunchVersionId
        pendingLaunchVersionId = null
        return value
    }

    /** 取走攒着的分享文件（本机缓存路径） */
    @DartCall
    fun takeSharedFiles(): List<String> = shareHandler?.takePending().orEmpty()
}

/** 一次外部 intent 的去向；只描述发生了什么，界面动作留给 Activity。 */
sealed interface Incoming {
    data object None : Incoming

    /** [versionId] 会随事件送给 Dart，热启动时那边不必再取一次 */
    data class Launch(val versionId: String, val silent: Boolean) : Incoming

    data object Auth : Incoming
}
