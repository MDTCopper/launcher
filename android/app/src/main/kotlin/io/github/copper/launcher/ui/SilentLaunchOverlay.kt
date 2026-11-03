package io.github.copper.launcher.ui

import android.app.Activity
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import io.github.copper.launcher.channel.DartCall

/**
 * 静默启动的黑幕：在界面上盖一层纯黑，窗口本身保持不透明。
 *
 * 之前把窗口 alpha 压 0 会在启动瞬间露出桌面；盖黑幕既看不到启动器 UI，也不闪桌面。
 * 游戏起来 / 启动失败后由 Dart 调 [hide] 撤掉。
 *
 * 做成 object 是为了让 [hide] 作为静态方法接进生成通道；静态状态持有 Activity/View，
 * 所以 Activity 销毁时必须调 [release]（见 MainActivity.onDestroy），否则必然泄漏。
 */
object SilentLaunchOverlay {
    private var overlay: View? = null
    private var silentLaunch = false
    private var headlessSilent = false

    /** MainActivity 在 super.onCreate 前标记：这次是从桌面快捷方式静默启动 */
    fun markSilentLaunch() {
        silentLaunch = true
    }

    fun clearSilentLaunch() {
        silentLaunch = false
    }

    /** Dart 侧决定不建启动器 UI（直接回桌面模式） */
    @DartCall
    fun setHeadlessSilent() {
        headlessSilent = true
    }

    fun isHeadlessSilent(): Boolean = headlessSilent

    @DartCall
    fun isSilentLaunch(): Boolean = silentLaunch

    fun show(activity: Activity) {
        if (overlay != null) return
        val view = View(activity).apply { setBackgroundColor(Color.BLACK) }
        overlay = view
        activity.window.decorView.post {
            // 期间可能已经被撤掉（启动失败得很快），那就别再贴上去
            if (overlay !== view) return@post
            (activity.window.decorView as? ViewGroup)?.addView(
                view,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    /** 撤掉黑幕，把启动器界面还回来 */
    @DartCall
    fun hide() {
        detach()
    }

    /** Activity 销毁时调用：静态状态不能留着旧 Activity 和它的 View */
    fun release() {
        silentLaunch = false
        headlessSilent = false
        detach()
    }

    private fun detach() {
        val view = overlay ?: return
        overlay = null
        (view.parent as? ViewGroup)?.removeView(view)
    }
}
