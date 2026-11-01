package io.github.copper.launcher.system

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log

/**
 * 伪局域网房间的组播锁。
 *
 * 不拿 MulticastLock 时 Wi-Fi 芯片会把游戏发出的组播探测包过滤掉。锁跟随
 * Activity 生命周期，onCreate 获取、onDestroy 释放。
 */
class LanDiscoveryLock(context: Context) {
    private val appContext = context.applicationContext
    private var lock: WifiManager.MulticastLock? = null

    fun acquire() {
        try {
            val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            lock = wifi?.createMulticastLock("copper-lan-discovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
            if (lock?.isHeld == true) Log.i(TAG, "已获取组播锁（伪局域网房间）")
        } catch (error: Exception) {
            Log.w(TAG, "获取组播锁失败：${error.message}")
        }
    }

    fun release() {
        lock?.let { if (it.isHeld) it.release() }
        lock = null
    }

    private companion object {
        const val TAG = "LanDiscovery"
    }
}
