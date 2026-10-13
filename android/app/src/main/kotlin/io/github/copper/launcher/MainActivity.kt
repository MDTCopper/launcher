package io.github.copper.launcher

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 启动器宿主。
 *
 * 系统返回键归 Dart 侧（`AppShell` 的 PopScope）管；这里只补 Dart 够不着的事 ——
 * 「退到后台」（moveTaskToBack 是 Activity 的方法）与「结束游戏进程」
 * （游戏跑在 `:mdt_process` 里，Dart 侧没有 Process 句柄）。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    "killGameProcess" -> killGameProcess(result)
                    else -> result.notImplemented()
                }
            }
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

    private companion object {
        const val CHANNEL = "io.github.copper.launcher/host"
    }
}
