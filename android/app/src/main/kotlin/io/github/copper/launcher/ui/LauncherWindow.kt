package io.github.copper.launcher.ui

import android.app.Activity
import io.github.copper.launcher.channel.DartCall

/**
 * 启动器窗口 / 任务栈动作：结束自己、退到后台。
 *
 * Dart 侧只表达「结束启动器」「退到后台」这两个意图；Activity 的状态机细节留在这里。
 * 生成器不认识这两个名字：它们和别的调用一样是普通 `@DartCall` 静态方法，
 * 参数名 `activityContext` 由通道注入。
 */
object LauncherWindow {
    /**
     * 结束启动器 Activity（游戏在跑时把它露出来）。
     *
     * `finish()` 必须推到下一轮主线程消息再执行：本轮的通道回复（`result.success`）要先
     * 交给引擎；直接 finish 会先拆 Activity（以及挂在它上面的引擎），Dart 的 await
     * 就等不到回复。
     */
    @DartCall
    fun finishLauncher(activityContext: Activity) {
        activityContext.window.decorView.post { activityContext.finish() }
    }

    /** 把整个 task 退到后台：露出桌面，进程留着收尾（云存档等） */
    @DartCall
    fun moveTaskToBack(activityContext: Activity): Boolean =
        activityContext.moveTaskToBack(true)
}
