package io.github.copper.launcher

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 启动器宿主。
 *
 * 系统返回键归 Dart 侧（`AppShell` 的 PopScope）管；这里只补 Dart 够不着的事 ——
 * 「退到后台」（moveTaskToBack 是 Activity 的方法）、「结束游戏进程」
 * （游戏跑在 `:mdt_process` 里，Dart 侧没有 Process 句柄），
 * 以及「系统分享进来」（`content://` 只有宿主读得了）。
 */
open class MainActivity : FlutterActivity() {    private val shareIntentHandler by lazy { ShareIntentHandler(applicationContext) }
    private var shareChannel: MethodChannel? = null
    private var hostChannel: MethodChannel? = null

    /** 登录回调（copperlauncher://oauth/...）：攒着等 Dart 来取，冷启动也丢不了 */
    private var pendingAuthUri: String? = null

    /** 桌面快捷方式带来的版本 id：同样攒着等 Dart 来取 */
    private var pendingLaunchVersionId: String? = null

    /** 这次是不是从快捷方式静默启动（窗口先透明，别让人看到启动器界面） */
    private var silentLaunch = false

    private var multicastLock: WifiManager.MulticastLock? = null

    /**
     * 伪局域网房间要靠组播收游戏发出的探测；Android 上不拿 MulticastLock
     * 时 Wi-Fi 芯片会把组播包过滤掉。锁跟随 Activity 生命周期
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        // 静默启动：在 super 之前换深色主题并把窗口压透明，别让人看到启动器界面或白屏
        val silentRequest = intent?.action == GameShortcut.ACTION_LAUNCH_GAME &&
            intent.getBooleanExtra(GameShortcut.EXTRA_SILENT, true)
        if (silentRequest) {
            setTheme(R.style.SilentLaunchTheme)
            window.attributes = window.attributes.apply { alpha = 0f }
        }
        super.onCreate(savedInstanceState)
        handleDebugPin(intent)
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifi?.createMulticastLock("copper-lan-discovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
            if (multicastLock?.isHeld == true) {
                Log.i(TAG, "已获取组播锁（伪局域网房间）")
            }
        } catch (error: Exception) {
            Log.w(TAG, "获取组播锁失败：${error.message}")
        }
    }

    override fun onDestroy() {
        multicastLock?.let { lock ->
            if (lock.isHeld) lock.release()
        }
        multicastLock = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        hostChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        hostChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeAuthUri" -> {
                    result.success(pendingAuthUri)
                    pendingAuthUri = null
                }
                "takeLaunchRequest" -> {
                    result.success(pendingLaunchVersionId)
                    pendingLaunchVersionId = null
                }
                "requestPinShortcut" -> requestPinShortcut(call, result)
                "requestPinWidget" -> requestPinWidget(call, result)
                "finishLauncher" -> {
                    result.success(true)
                    finish()
                }
                "setLauncherVisible" -> {
                    setSilentWindow(false)
                    result.success(true)
                }
                "moveTaskToBack" -> result.success(moveTaskToBack(true))
                "killGameProcess" -> killGameProcess(result)
                "isGameProcessRunning" -> isGameProcessRunning(result)
                else -> result.notImplemented()
            }
        }

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "takeSharedFiles" -> result.success(shareIntentHandler.takePending())
                        else -> result.notImplemented()
                    }
                }
            }

        // 冷启动那次分享：先复制好攒着，Dart 起来后会自己来取
        dispatchIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDebugPin(intent)
        dispatchIncoming(intent)
    }

    /** 分享、登录回调与桌面快捷方式走同一个入口：先认快捷方式，再认登录回调，最后当分享处理 */
    private fun dispatchIncoming(intent: Intent?) {
        if (captureLaunchRequest(intent)) return
        if (captureAuthUri(intent)) return
        dispatchShare(intent)
    }

    /**
     * 收桌面快捷方式带来的版本 id：`action=io.github.copper.launcher.LAUNCH_GAME`
     *
     * 收到就先攒着并通知 Dart 来取；Dart 在启动器起来后取一次，直接拉起对应版本
     */
    private fun captureLaunchRequest(intent: Intent?): Boolean {
        if (intent?.action != GameShortcut.ACTION_LAUNCH_GAME) return false
        pendingLaunchVersionId = intent.getStringExtra(GameShortcut.EXTRA_VERSION_ID)
        // 老快捷方式的 intent 里没有 silent 标记，但 LAUNCH_GAME 只可能是快捷方式/小组件来的，默认就当静默
        silentLaunch = intent.getBooleanExtra(GameShortcut.EXTRA_SILENT, true)
        if (silentLaunch) setSilentWindow(true)
        Log.i(TAG, "收到快捷方式启动请求：$pendingLaunchVersionId 静默=$silentLaunch")
        hostChannel?.invokeMethod("launchRequestAvailable", null)
        return true
    }

    /** 静默启动时把窗口压成全透明，Dart 那边起完游戏再喊 [setSilentWindow] 恢复 */
    private fun setSilentWindow(silent: Boolean) {
        val target = if (silent) 0f else 1f
        val attributes = window.attributes
        if (attributes.alpha == target) return
        attributes.alpha = target
        window.attributes = attributes
    }

    /**
     * 收登录回调：`copperlauncher://oauth/callback?code=...&state=...`
     *
     * 收到就先攒着并通知 Dart 来取；Dart 那边登录流程会轮询 `takeAuthUri`
     */
    private fun captureAuthUri(intent: Intent?): Boolean {
        if (intent?.action != Intent.ACTION_VIEW) return false
        val data = intent.data ?: return false
        if (data.scheme != "copperlauncher" || data.host != "oauth") return false
        pendingAuthUri = data.toString()
        Log.i(TAG, "收到登录回调")
        hostChannel?.invokeMethod("authCallbackAvailable", null)
        return true
    }

    /**
     * 收下这次分享并通知 Dart。
     *
     * 只通知、不把文件塞在通知里：Dart 收到后自己来取一次，
     * 这样冷启动（通知早于 Dart 接线，会丢）与热启动走的是同一条路。
     */
    private fun dispatchShare(intent: Intent?) {
        val files = shareIntentHandler.accept(intent)
        if (files.isEmpty()) return
        Log.i(TAG, "收到系统分享：${files.size} 个文件")
        shareChannel?.invokeMethod("sharedFilesAvailable", null)
    }

    /**
     * 结束游戏进程（`:mdt_process`）。
     *
     * pid 查找与「等它真的没了」那段在 `io.github.copper.GameProcess` 里 ——
     * 桥自己每次启动前清上一局用的也是同一份，口径保持一致。
     *
     * 它会阻塞（最多 1 秒，等进程退出），所以放到工作线程上跑，完了再回主线程答复。
     */
    private fun killGameProcess(result: MethodChannel.Result) {
        Thread {
            io.github.copper.GameProcess.kill(applicationContext)
            Handler(Looper.getMainLooper()).post { result.success(null) }
        }.start()
    }

    /**
     * 游戏还在不在。
     *
     * 游戏正常退出后桥会把 `:mdt_process` 留着，所以这里要等游戏进程写的退出标记，
     * 最长约 1 秒。[io.github.copper.GameProcess.isRunning] 会阻塞，放到工作线程上跑，
     * 完了再回主线程答复。
     */
    private fun isGameProcessRunning(result: MethodChannel.Result) {
        Thread {
            val running = io.github.copper.GameProcess.isRunning(applicationContext)
            Handler(Looper.getMainLooper()).post { result.success(running) }
        }.start()
    }

    /** 分享与登录回调之外的第三种外部 intent：桌面快捷方式 / 小组件（只 debug 包可用 adb 触发） */
    private fun handleDebugPin(intent: Intent?) {
        val action = intent?.action ?: return
        if (action != GameShortcut.ACTION_DEBUG_PIN &&
            action != GameShortcut.ACTION_DEBUG_PIN_WIDGET &&
            action != GameShortcut.ACTION_DEBUG_BIND_WIDGET
        ) {
            return
        }
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
        val versionId = intent.getStringExtra("version_id").orEmpty()
        val tag = intent.getStringExtra("tag").orEmpty()
        val jarPath = intent.getStringExtra("jar_path").orEmpty()
        val iconPath = intent.getStringExtra("icon_path").orEmpty()
        when (action) {
            GameShortcut.ACTION_DEBUG_PIN -> {
                val requested = GameShortcut.requestPin(this, versionId, tag, jarPath, iconPath)
                Log.i(TAG, "调试：请求桌面快捷方式 version=$versionId 提交=$requested")
            }
            GameShortcut.ACTION_DEBUG_PIN_WIDGET -> {
                val requested = GameWidget.requestPin(this, versionId, tag, jarPath, iconPath)
                Log.i(TAG, "调试：请求桌面小组件 version=$versionId 提交=$requested")
            }
            GameShortcut.ACTION_DEBUG_BIND_WIDGET -> {
                val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
                if (appWidgetId >= 0) {
                    GameWidget.saveBinding(
                        this,
                        appWidgetId,
                        GameWidget.Binding(versionId, tag, jarPath, iconPath),
                    )
                    GameWidget.render(this, appWidgetId)
                    Log.i(TAG, "调试：绑定小组件 $appWidgetId version=$versionId")
                }
            }
        }
    }

    /** Dart 侧请求建快捷方式（以后接版本页面按钮用） */
    private fun requestPinShortcut(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val versionId = args?.get("versionId") as? String ?: ""
        val tag = args?.get("tag") as? String ?: ""
        val jarPath = args?.get("jarPath") as? String ?: ""
        val iconPath = args?.get("iconPath") as? String ?: ""
        result.success(GameShortcut.requestPin(this, versionId, tag, jarPath, iconPath))
    }

    /** Dart 侧请求建桌面小组件（版本设置页的「创建桌面快捷方式」用它） */
    private fun requestPinWidget(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val versionId = args?.get("versionId") as? String ?: ""
        val tag = args?.get("tag") as? String ?: ""
        val jarPath = args?.get("jarPath") as? String ?: ""
        val iconPath = args?.get("iconPath") as? String ?: ""
        result.success(GameWidget.requestPin(this, versionId, tag, jarPath, iconPath))
    }

    private companion object {
        const val TAG = "MainActivity"
        const val CHANNEL = "io.github.copper.launcher/host"
        const val SHARE_CHANNEL = "io.github.copper.launcher/share"
    }
}
