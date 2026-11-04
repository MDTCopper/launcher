package io.github.copper.launcher.shortcut

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import io.github.copper.launcher.channel.DartCall

/**
 * 桌面图标跟随 App 内主题。
 *
 * 四个主题各有一个启用了 LAUNCHER 入口的 activity-alias（清单里 .IconXxx），
 * 这里只负责把当前主题那个启用、其余禁用 —— 系统据此换掉桌面上的图标。
 */
object LauncherIcon {
    private const val TAG = "LauncherIcon"

    /** 主题名（ThemeColor.name）→ 清单里的 activity-alias 简单名 */
    private val themeAliases = listOf(
        "copper" to ".IconCopper",
        "titanium" to ".IconTitanium",
        "thorium" to ".IconThorium",
        "plastanium" to ".IconPlastanium",
    )

    @DartCall
    fun setLauncherIcon(applicationContext: Context, theme: String) {
        val packageName = applicationContext.packageName
        val target = themeAliases.firstOrNull { it.first == theme } ?: themeAliases.first()
        val manager = applicationContext.packageManager

        // 先启用目标再禁用其余：中间不出现「桌面没有启动入口」的时刻
        setEnabled(manager, packageName, target.second, true)
        for ((_, alias) in themeAliases) {
            if (alias == target.second) continue
            setEnabled(manager, packageName, alias, false)
        }
        Log.i(TAG, "桌面图标切到 ${target.first}")
    }

    private fun setEnabled(
        manager: PackageManager,
        packageName: String,
        alias: String,
        enabled: Boolean,
    ) {
        val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        manager.setComponentEnabledSetting(
            ComponentName(packageName, packageName + alias),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }
}
