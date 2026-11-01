package io.github.copper.launcher.shortcut

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.util.Log

/**
 * debug 包的 adb 调试入口：建快捷方式 / 建小组件 / 把小组件绑到指定版本。
 *
 * 只在 `FLAG_DEBUGGABLE` 包上生效，正式包收到这些 action 直接忽略。
 */
class DebugPinHandler(private val activity: Activity) {
    fun handle(intent: Intent?) {
        val action = intent?.action ?: return
        if (action != GameShortcut.ACTION_DEBUG_PIN &&
            action != GameShortcut.ACTION_DEBUG_PIN_WIDGET &&
            action != GameShortcut.ACTION_DEBUG_BIND_WIDGET
        ) {
            return
        }
        if ((activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return

        val versionId = intent.getStringExtra("version_id").orEmpty()
        val tag = intent.getStringExtra("tag").orEmpty()
        val jarPath = intent.getStringExtra("jar_path").orEmpty()
        val iconPath = intent.getStringExtra("icon_path").orEmpty()
        when (action) {
            GameShortcut.ACTION_DEBUG_PIN -> {
                val requested = GameShortcut.requestPinShortcut(activity, versionId, tag, jarPath, iconPath)
                Log.i(TAG, "调试：请求桌面快捷方式 version=$versionId 提交=$requested")
            }
            GameShortcut.ACTION_DEBUG_PIN_WIDGET -> {
                val requested = GameWidget.requestPinWidget(activity, versionId, tag, jarPath, iconPath)
                Log.i(TAG, "调试：请求桌面小组件 version=$versionId 提交=$requested")
            }
            GameShortcut.ACTION_DEBUG_BIND_WIDGET -> {
                val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
                if (appWidgetId >= 0) {
                    GameWidget.saveBinding(
                        activity,
                        appWidgetId,
                        GameWidget.Binding(versionId, tag, jarPath, iconPath),
                    )
                    GameWidget.render(activity, appWidgetId)
                    Log.i(TAG, "调试：绑定小组件 $appWidgetId version=$versionId")
                }
            }
        }
    }

    private companion object {
        const val TAG = "DebugPin"
    }
}
