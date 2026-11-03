package io.github.copper.launcher.system

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.github.copper.launcher.channel.DartCall
import io.github.copper.launcher.channel.DartData

/**
 * ActivityManager 口径的设备内存信息。
 *
 * 返回值是 [@DartData] 数据类，生成器会翻成 Dart 数据类并按字段名过通道；
 * Dart 侧拿到的就是类型化对象，不再包一层 Java 静态内部类。
 *
 * 返回类型可空只是给「非安卓平台没有宿主通道」留位置：那边生成层直接返回 null，
 * 安卓上这里始终有值。
 */
object SystemInfo {
    /** 设备支持的 ABI（主 ABI 在前）；桥的 JRE 要按它选分包 */
    @DartCall
    fun getSupportedAbis(): List<String> = Build.SUPPORTED_ABIS.toList()

    @DartCall
    fun getMemoryInfo(applicationContext: Context): MemorySnapshot? {
        val manager = applicationContext.getSystemService(ActivityManager::class.java)
            ?: return null
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return MemorySnapshot(
            availMem = info.availMem,
            lowMemory = info.lowMemory,
            threshold = info.threshold,
            totalMem = info.totalMem,
        )
    }

    @DartCall
    fun getHeapMemoryInfo(applicationContext: Context): HeapLimits? {
        val manager = applicationContext.getSystemService(ActivityManager::class.java)
            ?: return null
        return HeapLimits(
            // dalvik.vm.heapgrowthlimit / dalvik.vm.heapsize，单位 MB
            normalSize = manager.memoryClass.toLong(),
            largeSize = manager.largeMemoryClass.toLong(),
        )
    }
}

/** 设备内存快照；字段名就是 Dart 侧的字段名 */
@DartData
data class MemorySnapshot(
    val availMem: Long,
    val lowMemory: Boolean,
    val threshold: Long,
    val totalMem: Long,
)

/** 单进程堆上限（MB） */
@DartData
data class HeapLimits(
    val normalSize: Long,
    val largeSize: Long,
)
