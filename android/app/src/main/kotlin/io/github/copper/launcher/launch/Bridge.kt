package io.github.copper.launcher.launch

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.github.copper.launcher.channel.DartCall
import io.github.copper.launcher.game.GameProcess
import io.github.copper.launcher.game.MindustryActivity
import java.io.File

/**
 * 桥的入口：不跑 ART，而是起一个真 JVM 跑桌面版游戏 jar。
 *
 * 与 `Loader.launchLoader` 保持同一形状：调用方拼好整条参数向量并给出 jar，
 * 这里只负责把它交给占位 Activity，组件工厂会把占位 Activity 换成桥建好的游戏界面。
 * 游戏 jar、数据目录、缓存目录、JVM、arc 原生库都归参数向量管，不归这个类管。
 */
object Bridge {
    /** 通过 [MindustryActivity] 启动桥，传入 bridge jar 与参数。 */
    @DartCall
    @Suppress("DEPRECATION")
    fun launchBridge(bridgePath: String, activityContext: Context, args: Array<String>) {
        val jar = File(bridgePath)
        if (!jar.exists()) {
            throw RuntimeException("bridge jar not existed: ${jar.absolutePath}")
        }

        // Android 14+ DexClassLoader 要求 jar 只读，否则抛 SecurityException
        jar.setReadOnly()
        // 上一局会留下占位进程；一个进程只放得下一个 JVM（或一条 loader），
        // 不清掉的话下一次启动会在组件工厂里失败
        GameProcess.killGameProcess(activityContext.applicationContext)
        val intent = Intent(activityContext, MindustryActivity::class.java)
        intent.putExtra("copper_bridge_jar", jar.absolutePath)
        intent.putExtra("copper_bridge_args", args)
        activityContext.startActivity(intent)
        // 启动器已经用主题色罩住自己：淡入淡出比系统默认滑动更稳，不会滑到一半停住
        if (activityContext is Activity) {
            activityContext.overridePendingTransition(
                android.R.anim.fade_in,
                android.R.anim.fade_out,
            )
        }
    }
}
