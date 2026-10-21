package io.github.copper.launcher

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 启动器宿主。
 *
 * 系统返回键归 Dart 侧（`AppShell` 的 PopScope）管；这里只补 Dart 够不着的事 ——
 * 「退到后台」（moveTaskToBack 是 Activity 的方法）、「结束游戏进程」
 * （游戏跑在 `:mdt_process` 里，Dart 侧没有 Process 句柄），
 * 以及「系统分享进来」（`content://` 只有宿主读得了）。
 */
class MainActivity : FlutterActivity() {
    private val shareIntentHandler by lazy { ShareIntentHandler(applicationContext) }
    private var shareChannel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    /**
     * 伪局域网房间要靠组播收游戏发出的探测；Android 上不拿 MulticastLock
     * 时 Wi-Fi 芯片会把组播包过滤掉。锁跟随 Activity 生命周期
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
        dispatchShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchShare(intent)
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

    private companion object {
        const val TAG = "MainActivity"
        const val CHANNEL = "io.github.copper.launcher/host"
        const val SHARE_CHANNEL = "io.github.copper.launcher/share"
    }
}
