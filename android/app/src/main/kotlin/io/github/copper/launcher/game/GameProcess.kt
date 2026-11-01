package io.github.copper.launcher.game

import android.app.ActivityManager
import android.content.Context
import android.util.Log
import io.github.copper.launcher.channel.DartAsyncCall
import io.github.copper.launcher.channel.DartCall
import java.io.File
import java.io.IOException

/**
 * 游戏占位进程（`:mdt_process`）：loader 与 bridge 的游戏界面都跑在这里。
 *
 * 正常结束会故意留下这个进程，下一局启动前必须清掉——`bridge.jar` 每局都换新的
 * 类加载器，残留副本会让第二次启动报 `UnsatisfiedLinkError: … already opened by ClassLoader`。
 *
 * 等待是必要的：杀进程和启动同一口气做会撞上系统拆 Activity，表现成「刚退出一局
 * 再启动没有转场动画」。等待有上限，进程赖着不走也不能把按钮永远卡住。
 */
object GameProcess {
    private const val TAG = "Copper"
    private const val SUFFIX = ":mdt_process"
    private const val EXIT_MARKER = "game-exit.marker"
    private const val ALIVE_MARKER = "game-alive.marker"

    /** 结束该进程并等它真的消失；没有残留进程时立即返回。 */
    @DartAsyncCall
    fun killGameProcess(applicationContext: Context) {
        clearExitMarker(applicationContext)
        val pid = pid(applicationContext)
        Log.i(TAG, "killGameProcess: leftover pid=$pid")
        if (pid < 0) return

        android.os.Process.killProcess(pid)
        for (waited in 0 until 40) {
            if (pid(applicationContext) < 0) {
                Log.i(TAG, "killGameProcess: $pid gone after ${waited * 25} ms")
                return
            }
            try {
                Thread.sleep(25)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
        }
        Log.i(TAG, "killGameProcess: $pid still there after 1000 ms")
    }

    /** 该进程的 pid；不在时返回 -1。 */
    private fun pid(context: Context): Int {
        val manager = context.getSystemService(ActivityManager::class.java) ?: return -1
        val processes = manager.runningAppProcesses ?: return -1
        val name = context.packageName + SUFFIX
        return processes.firstOrNull { name == it.processName }?.pid ?: -1
    }

    /**
     * 游戏是否还在跑；系统不透露进程列表时返回 null。
     *
     * 只看到进程活着不够：正常结束会留下 `:mdt_process`，真正的退出信号是游戏自己的
     * Activity 消失。信号由游戏进程写出，可能比启动器回到前台晚一步，所以这里短暂等它。
     */
    @DartAsyncCall
    fun isGameProcessRunning(applicationContext: Context): Boolean? {
        if (consumeExitMarker(applicationContext)) return false

        val manager = applicationContext.getSystemService(ActivityManager::class.java) ?: return null
        val processes = manager.runningAppProcesses ?: return null

        val name = applicationContext.packageName + SUFFIX
        if (!hasProcess(processes, name)) return false

        repeat(20) {
            try {
                Thread.sleep(50)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return true
            }
            if (consumeExitMarker(applicationContext)) return false
            if (!hasProcess(manager.runningAppProcesses, name)) return false
        }
        return true
    }

    /**
     * 游戏界面是否还在（前台 / 退到后台都算）。
     *
     * 不用 `ActivityManager.appTasks`：Android 14 上游戏跑在 `:mdt_process`，它的 task
     * 从启动器进程看是 `id=-1、base/topActivity=null` 的脱敏条目，判断永远不成立
     * （真机上表现为「游戏在跑，点快捷方式却重启一局」）。
     *
     * 改成由游戏进程自己维护存活标记：Activity 起来时写、最后一个销毁时删；
     * 进程崩了标记会残留，所以再拿进程列表兜一下。
     */
    @DartCall
    fun isGameActivityVisible(applicationContext: Context): Boolean {
        val marker = aliveMarker(applicationContext)
        if (!marker.exists()) return false

        val manager = applicationContext.getSystemService(ActivityManager::class.java)
            ?: return true
        // 拿不到进程列表（系统限制）就信标记，别把还在跑的游戏当成已退出
        val processes = manager.runningAppProcesses ?: return true
        val alive = processes.any { it.processName == applicationContext.packageName + SUFFIX }
        if (!alive) {
            marker.delete()
            Log.i(TAG, "game-alive marker cleared: process gone")
        }
        return alive
    }

    /** 游戏进程里：Activity 起来时写存活标记（跨进程判断「界面还在」用） */
    internal fun markGameAlive(context: Context) {
        try {
            aliveMarker(context).parentFile?.mkdirs()
            aliveMarker(context).createNewFile()
        } catch (error: IOException) {
            Log.w(TAG, "cannot write game-alive marker", error)
        }
    }

    /** 游戏 Activity 全部销毁：删存活标记（退出标记另写，见 [markGameExited]） */
    internal fun clearGameAlive(context: Context) {
        val marker = aliveMarker(context)
        if (marker.exists() && !marker.delete()) {
            Log.w(TAG, "cannot clear game-alive marker")
        }
    }

    private fun aliveMarker(context: Context): File = File(context.filesDir, ALIVE_MARKER)

    private fun hasProcess(processes: List<ActivityManager.RunningAppProcessInfo>?, name: String): Boolean {
        // 拿不到列表时按「还在」处理，别把正在跑的游戏误判成已退出
        if (processes == null) return true
        return processes.any { name == it.processName }
    }

    /** 游戏进程最后一个 Activity 消失时写标记。 */
    internal fun markGameExited(context: Context) {
        val marker = exitMarker(context)
        try {
            marker.parentFile?.mkdirs()
            if (marker.createNewFile()) Log.i(TAG, "game-exit marker written")
        } catch (error: IOException) {
            Log.w(TAG, "cannot write game-exit marker", error)
        }
    }

    /** 新一局开始前清掉上一局的标记。 */
    internal fun clearExitMarker(context: Context) {
        val marker = exitMarker(context)
        if (marker.exists() && !marker.delete()) {
            Log.w(TAG, "cannot clear game-exit marker")
        }
    }

    private fun consumeExitMarker(context: Context): Boolean {
        val marker = exitMarker(context)
        if (!marker.exists()) return false
        if (marker.delete()) Log.i(TAG, "game-exit marker read: game exited")
        return true
    }

    private fun exitMarker(context: Context): File = File(context.filesDir, EXIT_MARKER)
}
