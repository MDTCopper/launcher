package io.github.copper.launcher

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import java.io.File

/**
 * 系统送进来的文件（ACTION_SEND / ACTION_SEND_MULTIPLE / ACTION_VIEW）。
 *
 * Dart 读不了 content:// ，所以这里先把每一份复制成应用缓存目录里的真文件，
 * 再把本机路径交给 Dart 侧；怎么导仍由 Dart 决定（与桌面拖入同一条路）。
 *
 * 一次分享放一个以时间戳命名的子目录；超过一天没人取就顺手清掉，缓存不至于一直涨。
 */
class ShareIntentHandler(context: Context) {

    private val appContext = context.applicationContext
    private val pending = mutableListOf<String>()

    /** 取走攒着的本机路径（Dart 启动时来取一次，之后每次新分享也会来取） */
    @Synchronized
    fun takePending(): List<String> {
        val files = pending.toList()
        pending.clear()
        return files
    }

    /**
     * 收下一次分享：复制到缓存目录并攒起来。
     *
     * 返回这次复制成功的路径；不是分享、或者一份都读不出来时返回空列表。
     */
    @Synchronized
    fun accept(intent: Intent?): List<String> {
        if (intent == null) return emptyList()
        // 排查用：面板里不出现 Copper 时（发送方的类型不在白名单）这条什么都不会打，
        // 所以真机上「有没有这条日志」本身就是结论之一（tag = ShareIntent）
        Log.i(TAG, "收到分享：action=${intent.action} type=${intent.type}")

        val uris = sharedUris(intent)
        if (uris.isEmpty()) return emptyList()

        val targetDir = prepareTargetDir()
        val copied = mutableListOf<String>()
        for (uri in uris) {
            Log.i(TAG, "分享文件：$uri（type=${appContext.contentResolver.getType(uri)}）")
            copyToCache(uri, targetDir)?.let { copied.add(it) }
        }
        pending.addAll(copied)
        return copied
    }

    private fun sharedUris(intent: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> singleSharedUri(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(multipleSharedUris(intent))
            //「用其他应用打开」：文件挂在 data 上，与分享是同一条路
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            else -> return emptyList()
        }
        // 有的应用把文件塞在 ClipData 里而不是 EXTRA_STREAM，两边都收
        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        return uris.distinct()
    }

    @Suppress("DEPRECATION")
    private fun singleSharedUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun multipleSharedUris(intent: Intent): List<Uri> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) ?: emptyList()
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        }

    private fun copyToCache(uri: Uri, targetDir: File): String? {
        val name = displayName(uri) ?: return null
        val file = uniqueFile(targetDir, name)
        return try {
            val source = appContext.contentResolver.openInputStream(uri) ?: return null
            source.use { input -> file.outputStream().use { output -> input.copyTo(output) } }
            file.absolutePath
        } catch (error: Exception) {
            Log.w(TAG, "复制分享文件失败：$uri", error)
            file.delete()
            null
        }
    }

    /** 文件名优先问内容提供者，问不到就拿 URI 的最后一段 */
    private fun displayName(uri: Uri): String? {
        val queried = runCatching {
            appContext.contentResolver
                .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        }.getOrNull()
        val raw = queried?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment
        // 名字来自别的应用，去掉目录成分，别让它写到别的目录去
        val name = raw?.substringAfterLast('/')?.substringAfterLast('\\')?.trim()
        return name?.takeIf { it.isNotEmpty() }
    }

    private fun uniqueFile(directory: File, name: String): File {
        val candidate = File(directory, name)
        if (!candidate.exists()) return candidate

        val base = name.substringBeforeLast('.', name)
        val extension = name.substringAfterLast('.', "")
        var index = 2
        while (true) {
            val next = File(
                directory,
                if (extension.isEmpty()) "$base-$index" else "$base-$index.$extension",
            )
            if (!next.exists()) return next
            index++
        }
    }

    private fun prepareTargetDir(): File {
        val root = File(appContext.cacheDir, CACHE_DIR)
        purgeExpired(root)
        val directory = File(root, System.currentTimeMillis().toString())
        directory.mkdirs()
        return directory
    }

    private fun purgeExpired(root: File) {
        val deadline = System.currentTimeMillis() - EXPIRY_MILLIS
        root.listFiles()?.forEach { entry ->
            if (entry.lastModified() < deadline) entry.deleteRecursively()
        }
    }

    private companion object {
        const val TAG = "ShareIntent"
        const val CACHE_DIR = "shared"
        const val EXPIRY_MILLIS = 24 * 60 * 60 * 1000L
    }
}
