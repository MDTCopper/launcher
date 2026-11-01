package io.github.copper.launcher

import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.github.copper.launcher.game.GameProcess

/**
 * 应用 Application。
 *
 * bridge 正常退出后会把 `:mdt_process` 留在那里（下一局启动前由 [GameProcess] 清掉），
 * 所以「进程还在不在」判断不了游戏是否结束。真正变化的是游戏 Activity：最后一个
 * Activity 消失才算这一局结束。这发生在游戏进程里，记下来，等启动器回到前台再读。
 *
 * 另外维护一个「游戏界面还在」的存活标记：游戏 Activity 起来时写、全部销毁时删。
 * 启动器进程靠它判断快捷方式该回到游戏还是重开一局（`appTasks` 在 Android 14 上
 * 对跨进程的游戏 task 是脱敏的，不能用来判断）。
 */
class CopperApplication : Application() {
    private var activityCount = 0

    override fun onCreate() {
        super.onCreate()

        val process = getProcessName()
        if (process == null || !process.endsWith(GAME_PROCESS_SUFFIX)) return

        // 新一局从干净状态开始：上一局的退出标记不能当成这一局的退出，存活标记也重来
        GameProcess.clearExitMarker(this)
        GameProcess.clearGameAlive(this)

        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                activityCount++
                // 跨进程告诉启动器「游戏界面还在」：快捷方式据此回到游戏而不是重开一局
                GameProcess.markGameAlive(this@CopperApplication)
            }

            override fun onActivityStarted(activity: Activity) = Unit

            override fun onActivityResumed(activity: Activity) = Unit

            override fun onActivityPaused(activity: Activity) = Unit

            override fun onActivityStopped(activity: Activity) {
                // onStop 早于启动器 onResume；等 onDestroy 会和它抢时序
                if (activity.isFinishing && activityCount <= 1) {
                    GameProcess.markGameExited(this@CopperApplication)
                }
            }

            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

            override fun onActivityDestroyed(activity: Activity) {
                if (activityCount > 0) activityCount--
                if (activityCount == 0) {
                    GameProcess.clearGameAlive(this@CopperApplication)
                    GameProcess.markGameExited(this@CopperApplication)
                }
            }
        })
    }

    private companion object {
        const val GAME_PROCESS_SUFFIX = ":mdt_process"
    }
}
