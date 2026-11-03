package io.github.copper.launcher

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.github.copper.launcher.generated.AndroidCall
import io.github.copper.launcher.generated.AndroidEvent
import io.github.copper.launcher.game.GameProcess
import io.github.copper.launcher.intent.Incoming
import io.github.copper.launcher.intent.IncomingIntake
import io.github.copper.launcher.shortcut.DebugPinHandler
import io.github.copper.launcher.shortcut.GameShortcut
import io.github.copper.launcher.system.LanDiscoveryLock
import io.github.copper.launcher.ui.SilentLaunchOverlay

/**
 * 启动器宿主：只负责 Activity 生命周期、Flutter 引擎接线和外部 intent 分流。
 *
 * 「退到后台」「启动桥」「系统内存」这些能力由生成的 [AndroidCall] 暴露给 Dart，
 * 具体实现就在各自的 object 上（注解标在原方法上，见 channel/DartCall.kt）。
 * 外部 intent 的解析与暂存、静默黑幕、组播锁、调试入口都各自成类，这里不再堆业务细节。
 */
open class MainActivity : FlutterActivity() {
    // 引擎可能比 Activity 活得久：onDestroy 要用它把通道 handler 摘掉
    private var androidMessenger: BinaryMessenger? = null
    private var leftForHeadlessGame = false

    // configureFlutterEngine 可能在 super.onCreate 里就被调用，这里用 lazy 避免初始化顺序问题
    private val lanLock by lazy { LanDiscoveryLock(applicationContext) }
    private val debugPin by lazy { DebugPinHandler(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        val silentRequest = intent?.action == GameShortcut.ACTION_LAUNCH_GAME &&
            intent.getBooleanExtra(GameShortcut.EXTRA_SILENT, true)
        // 静默启动：super 之前换深色主题，启动窗口就是黑的（不闪白、不闪桌面）
        if (silentRequest) setTheme(R.style.SilentLaunchTheme)
        if (silentRequest) {
            SilentLaunchOverlay.markSilentLaunch()
        } else {
            SilentLaunchOverlay.clearSilentLaunch()
        }

        // configureFlutterEngine 在 super.onCreate 里就会分流冷启动 intent，所以解析器要先拿到上下文；
        // 顺序反过来会把冷启动那次分享丢掉（文件还没复制到缓存）
        IncomingIntake.attach(applicationContext)

        super.onCreate(savedInstanceState)

        if (silentRequest) {
            SilentLaunchOverlay.show(this)
            // 关掉 Activity 打开动画：不然会先看到桌面 + 一块黑窗放大（就是「闪一下」）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                overrideActivityTransition(Activity.OVERRIDE_TRANSITION_OPEN, 0, 0)
            } else {
                @Suppress("DEPRECATION")
                overridePendingTransition(0, 0)
            }
        }

        debugPin.handle(intent)
        lanLock.acquire()
    }

    override fun onPause() {
        super.onPause()
        if (SilentLaunchOverlay.isHeadlessSilent()) leftForHeadlessGame = true
    }

    override fun onResume() {
        super.onResume()
        // 无界面快捷启动：从游戏回到空 Activity 时直接退后台，
        // 不在黑屏上等 Dart 收尾；上传由后台进程继续
        if (SilentLaunchOverlay.isHeadlessSilent() && leftForHeadlessGame) {
            leftForHeadlessGame = false
            // 退出标记可能比 Activity 恢复晚几十毫秒，稍后再确认一次
            window.decorView.postDelayed({
                if (SilentLaunchOverlay.isHeadlessSilent() &&
                    !GameProcess.isGameActivityVisible(applicationContext)
                ) {
                    moveTaskToBack(true)
                }
            }, 600)
        }
    }

    override fun onDestroy() {
        // 两条通道都挂在引擎的 BinaryMessenger 上，并且都持有 Activity 侧的对象：
        // 引擎比 Activity 活得久时（缓存引擎 / add-to-app）必须先摘掉，否则旧实例留在内存里
        androidMessenger?.let {
            AndroidCall.clear(it)
            AndroidEvent.detach(it)
        }
        androidMessenger = null
        // 黑幕是静态状态，里面存着旧 Activity 的 View，不释放同样会泄漏
        SilentLaunchOverlay.release()
        lanLock.release()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        androidMessenger = messenger
        AndroidCall.register(messenger, this)
        // 事件通道只建一次：send* 不再每次传 messenger，也就不用每次 new MethodChannel
        AndroidEvent.attach(messenger)

        // 冷启动那次 intent：数据已经攒下，Dart 起来后会自己来取；事件这里先推一次
        dispatchIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        debugPin.handle(intent)
        dispatchIncoming(intent)
    }

    /** 外部 intent 分流：数据由 [IncomingIntake] 收下，这里只做界面动作和通知 Dart。 */
    private fun dispatchIncoming(intent: Intent?) {
        when (val incoming = IncomingIntake.handle(intent)) {
            Incoming.None -> Unit
            is Incoming.Launch -> {
                if (incoming.silent) SilentLaunchOverlay.show(this)
                AndroidEvent.sendShortcutLaunch(incoming.versionId, incoming.silent)
            }
            // 登录回调：URI 由 [IncomingIntake] 攒着，事件只当敲门声；Dart 收到后自己去取
            Incoming.Auth -> AndroidEvent.sendAuthCallback()
            is Incoming.Share -> AndroidEvent.sendSharedFiles(incoming.files)
        }
    }
}
