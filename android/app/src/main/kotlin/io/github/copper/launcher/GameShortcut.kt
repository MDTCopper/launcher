package io.github.copper.launcher

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import java.io.File
import java.util.zip.ZipFile

/**
 * 桌面快捷方式：一个版本一个「直接启动游戏」的固定快捷方式。
 *
 * 快捷方式带版本 id 回到 [MainActivity]，Dart 侧取到后直接拉起对应版本；
 * 图标优先用版本 jar 里自带的 logo，没有就用应用图标。
 */
object GameShortcut {
    const val ACTION_LAUNCH_GAME = "io.github.copper.launcher.LAUNCH_GAME"
    const val EXTRA_VERSION_ID = "version_id"

    /** 调试入口：`adb shell am start -a ... -n .../.MainActivity --es ...` 触发建快捷方式 */
    const val ACTION_DEBUG_PIN = "io.github.copper.launcher.DEBUG_PIN"

    private const val TAG = "GameShortcut"

    /** 版本 jar 里 logo 的候选条目：v9 起是 icon.png，更早只有 64px 那张 */
    private val iconEntries = listOf("icons/icon.png", "icons/icon_64.png")

    fun isSupported(context: Context): Boolean =
        ShortcutManagerCompat.isRequestPinShortcutSupported(context)

    /**
     * 请求把对应版本的快捷方式固定到桌面；系统不支持固定时返回 false。
     *
     * 必须在有前台 Activity 时调用（系统接口的限制）。
     */
    fun requestPin(
        activity: Activity,
        versionId: String,
        tag: String,
        jarPath: String,
    ): Boolean {
        if (versionId.isEmpty()) return false
        if (!isSupported(activity)) return false

        val intent = Intent(activity, MainActivity::class.java).apply {
            action = ACTION_LAUNCH_GAME
            putExtra(EXTRA_VERSION_ID, versionId)
        }

        val shortcut = ShortcutInfoCompat.Builder(activity, shortcutId(versionId))
            .setShortLabel(tag)
            .setLongLabel("启动 Mindustry $tag")
            .setIcon(iconOf(activity, jarPath))
            .setIntent(intent)
            .setLongLived(true)
            .build()

        return ShortcutManagerCompat.requestPinShortcut(activity, shortcut, null)
    }

    private fun shortcutId(versionId: String) = "launch-$versionId"

    private fun iconOf(activity: Activity, jarPath: String): IconCompat =
        readJarIcon(jarPath)?.let { IconCompat.createWithBitmap(it) }
            ?: IconCompat.createWithResource(activity, R.mipmap.ic_launcher)

    /** 从版本 jar 里读 logo；读不到返回 null */
    private fun readJarIcon(jarPath: String): Bitmap? {
        val file = File(jarPath)
        if (!file.exists()) return null
        return try {
            ZipFile(file).use { zip ->
                for (name in iconEntries) {
                    val entry = zip.getEntry(name) ?: continue
                    zip.getInputStream(entry).use { stream ->
                        BitmapFactory.decodeStream(stream)?.let { return it }
                    }
                }
            }
            null
        } catch (error: Exception) {
            Log.w(TAG, "读 jar 图标失败：${error.message}")
            null
        }
    }
}
