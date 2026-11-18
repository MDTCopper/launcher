package io.github.copper.launcher.system

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.PowerManager
import android.view.Display
import io.github.copper.launcher.channel.DartData

/**
 * 显示侧的只读快照。
 *
 * 帧率**控制**交给 `flutter_displaymode` 插件（Kazumi 用的那个，Dart 侧直接调
 * `FlutterDisplayMode.setPreferredMode`），这里不再碰窗口属性 / Surface，只负责把
 * 「现在实际是什么状态」读给运行日志，方便出问题时对照。
 */
object DisplayState {
    /** 当前分辨率下屏幕支持的最高刷新率对应的模式 */
    private fun peakMode(display: Display): Display.Mode? {
        val modes = display.supportedModes.toList()
        val current: Display.Mode = display.mode ?: return modes.maxByOrNull { it.refreshRate }
        val sameSize = modes.filter {
            it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight
        }
        return sameSize.ifEmpty { modes }.maxByOrNull { it.refreshRate }
    }

    private fun arrSupported(display: Display): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA && display.hasArrSupport()

    fun snapshot(activity: Activity): DisplayFrameRateInfo? {
        val display = activity.display ?: return null
        val power = activity.getSystemService(PowerManager::class.java)
        return DisplayFrameRateInfo(
            current = display.refreshRate.toDouble(),
            modeRate = display.mode?.refreshRate?.toDouble() ?: 0.0,
            modeId = display.mode?.modeId ?: 0,
            peak = (peakMode(display)?.refreshRate ?: display.refreshRate).toDouble(),
            arrSupported = arrSupported(display),
            powerSave = power?.isPowerSaveMode == true,
            apiLevel = Build.VERSION.SDK_INT,
            gameApp = (activity.applicationInfo.flags and ApplicationInfo.FLAG_IS_GAME) != 0,
        )
    }
}

/**
 * 刷新率快照（字段名就是 Dart 侧的字段名）。
 *
 * 读法：`current` 与 `modeRate` 对不上说明应用看到的 vsync 低于显示模式；
 * 两个都低于 `peak` 就是系统正在按自己的策略降档（省电 / 厂商策略）。
 */
@DartData
data class DisplayFrameRateInfo(
    /** 当前渲染帧率 */
    val current: Double,
    /** 当前显示模式的刷新率 */
    val modeRate: Double,
    /** 当前显示模式的 id */
    val modeId: Int,
    /** 面板峰值（当前分辨率下最高的模式刷新率） */
    val peak: Double,
    /** 平台是否支持自适应刷新率（Android 16 起才有这个查询） */
    val arrSupported: Boolean,
    /** 系统省电模式是否开着 */
    val powerSave: Boolean,
    /** Build.VERSION.SDK_INT */
    val apiLevel: Int,
    /** 本应用是否带 android:isGame 标记 */
    val gameApp: Boolean,
)
