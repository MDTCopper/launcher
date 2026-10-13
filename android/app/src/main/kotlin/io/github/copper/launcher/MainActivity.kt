package io.github.copper.launcher

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 启动器宿主。
 *
 * 系统返回键归 Dart 侧（`AppShell` 的 PopScope）管；这里只补一件 Dart 够不着的事 ——
 * 「退到后台」（moveTaskToBack 是 Activity 的方法）。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val CHANNEL = "io.github.copper.launcher/host"
    }
}
