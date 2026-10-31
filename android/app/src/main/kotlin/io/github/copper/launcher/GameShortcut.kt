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
 * 快捷方式带版本 id 回到 [MainActivity]，Dart 侧取到后直接拉起对应版本。
 */
object GameShortcut {
    const val ACTION_LAUNCH_GAME = "io.github.copper.launcher.LAUNCH_GAME"
    const val EXTRA_VERSION_ID = "version_id"

    /** 小组件 / 快捷方式共用的版本信息：标签与 jar 路径 */
    const val EXTRA_TAG = "mindustry_tag"
    const val EXTRA_JAR_PATH = "mindustry_jar_path"
    const val EXTRA_ICON_PATH = "mindustry_icon_path"

    /** 调试入口：`adb shell am start -a ... -n .../.MainActivity --es ...` 触发建快捷方式 */
    const val ACTION_DEBUG_PIN = "io.github.copper.launcher.DEBUG_PIN"

    /** 调试入口：用 adb 触发建 1x1 小组件 */
    const val ACTION_DEBUG_PIN_WIDGET = "io.github.copper.launcher.DEBUG_PIN_WIDGET"

    /** 调试入口：把某个已存在的小组件绑到指定版本并重画（没有配置页的桌面用它验证） */
    const val ACTION_DEBUG_BIND_WIDGET = "io.github.copper.launcher.DEBUG_BIND_WIDGET"

    private const val TAG = "GameShortcut"

    /** 快捷方式图标最多用这么大，再大只是白占内存（有些 jar 的 icns 有 1024） */
    private const val ICON_MAX_SIZE = 512

    /**
     * 图标来源，按清晰度排：
     * 1. `icons/icon.icns` / `icons/icon.ico` 里最大的 PNG（多数版本有 512、1024）
     * 2. `icons/icon.png`（v9 起有，256）
     * 3. `icons/icon_64.png`（更早只有 64px）
     */
    private val highResEntries = listOf("icons/icon.icns", "icons/icon.ico")
    private val pngEntries = listOf("icons/icon.png", "icons/icon_64.png")

    fun isSupported(context: Context): Boolean =
        ShortcutManagerCompat.isRequestPinShortcutSupported(context)

    /** 给小组件用：读版本 jar 里的 logo（读不到返回 null） */
    fun loadLogo(jarPath: String): Bitmap? = iconFromJar(jarPath)

    /** 读玩家给版本换的图标；没换过 / 文件坏了返回 null */
    fun loadIconFile(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        val file = File(path)
        if (!file.exists()) return null
        val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: return null
        return scaleDown(bitmap)
    }

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
        iconPath: String = "",
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
            .setIcon(iconOf(activity, jarPath, iconPath))
            .setIntent(intent)
            .setLongLived(true)
            .build()

        return ShortcutManagerCompat.requestPinShortcut(activity, shortcut, null)
    }

    private fun shortcutId(versionId: String) = "launch-$versionId"

    private fun iconOf(activity: Activity, jarPath: String, iconPath: String): IconCompat =
        loadIconFile(iconPath)?.let { IconCompat.createWithBitmap(it) }
            ?: iconFromJar(jarPath)?.let { IconCompat.createWithBitmap(it) }
            ?: IconCompat.createWithResource(activity, R.mipmap.ic_launcher)

    /** 从版本 jar 里读 logo；读不到返回 null */
    private fun iconFromJar(jarPath: String): Bitmap? {
        val file = File(jarPath)
        if (!file.exists()) return null
        return try {
            ZipFile(file).use { zip ->
                readHighResIcon(zip) ?: readPngIcon(zip)
            }
        } catch (error: Exception) {
            Log.w(TAG, "读 jar 图标失败：${error.message}")
            null
        }
    }

    /** icns / ico 里塞了多张 PNG，挑面积最大的那张 */
    private fun readHighResIcon(zip: ZipFile): Bitmap? {
        for (name in highResEntries) {
            val entry = zip.getEntry(name) ?: continue
            val bytes = zip.getInputStream(entry).use { it.readBytes() }
            val best = largestPng(bytes) ?: continue
            val sized = scaleDown(best)
            Log.i(TAG, "图标取自 $name（${sized.width}x${sized.height}）")
            return sized
        }
        return null
    }

    private fun readPngIcon(zip: ZipFile): Bitmap? {
        for (name in pngEntries) {
            val entry = zip.getEntry(name) ?: continue
            zip.getInputStream(entry).use { stream ->
                BitmapFactory.decodeStream(stream)?.let {
                    Log.i(TAG, "图标取自 $name（${it.width}x${it.height}）")
                    return it
                }
            }
        }
        return null
    }

    /** 容器里可能塞了多张 PNG，挑面积最大的；不依赖容器格式细节 */
    private fun largestPng(bytes: ByteArray): Bitmap? {
        var best: Bitmap? = null
        var index = 0
        while (index <= bytes.size - 8) {
            val looksLikePng = bytes[index] == 0x89.toByte() &&
                bytes[index + 1] == 'P'.code.toByte() &&
                bytes[index + 2] == 'N'.code.toByte() &&
                bytes[index + 3] == 'G'.code.toByte()
            if (looksLikePng) {
                val length = pngSize(bytes, index)
                if (length > 0) {
                    val bitmap = BitmapFactory.decodeByteArray(bytes, index, length)
                    val current = best
                    if (bitmap != null &&
                        (current == null || bitmap.width * bitmap.height > current.width * current.height)
                    ) {
                        current?.recycle()
                        best = bitmap
                    } else {
                        bitmap?.recycle()
                    }
                    index += length
                    continue
                }
            }
            index++
        }
        return best
    }

    /** 一个 PNG 从 [start] 起的字节数；读到 IEND 才知道结尾 */
    private fun pngSize(bytes: ByteArray, start: Int): Int {
        var offset = start + 8
        while (offset + 12 <= bytes.size) {
            val length = ((bytes[offset].toInt() and 0xFF) shl 24) or
                ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
                ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
                (bytes[offset + 3].toInt() and 0xFF)
            if (length < 0 || offset + 12 + length > bytes.size) return -1
            val type = String(bytes, offset + 4, 4, Charsets.US_ASCII)
            offset += 12 + length
            if (type == "IEND") return offset - start
        }
        return -1
    }

    /** 快捷方式用不到 1024 那么大，压到 512 省内存 */
    private fun scaleDown(bitmap: Bitmap): Bitmap {
        if (bitmap.width <= ICON_MAX_SIZE && bitmap.height <= ICON_MAX_SIZE) return bitmap
        val ratio = ICON_MAX_SIZE.toFloat() / maxOf(bitmap.width, bitmap.height)
        val scaled = Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * ratio).toInt(),
            (bitmap.height * ratio).toInt(),
            true,
        )
        bitmap.recycle()
        return scaled
    }
}
