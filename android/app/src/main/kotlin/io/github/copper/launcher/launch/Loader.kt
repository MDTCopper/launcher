package io.github.copper.launcher.launch

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.github.copper.launcher.channel.DartAsyncCall
import io.github.copper.launcher.channel.DartCall
import io.github.copper.launcher.game.ContainerClassLoader
import io.github.copper.launcher.game.GameProcess
import io.github.copper.launcher.game.MindustryActivity
import java.io.File

/**
 * Copper loader 的入口：在 ART 上把游戏 dex 化后运行。
 *
 * 与桥一样只是把 jar 和参数交给占位 Activity，真正的加载由组件工厂完成。
 * 两个入口都接进了 Dart 通道（[launchLoader] / [buildLoader]），虽然现在还没有调用点。
 */
object Loader {
    /**
     * 通过 [MindustryActivity] 启动 loader，传入 loader jar 与参数。
     *
     * Dart 侧现在还没有入口点它（桌面端走自己的 loader 任务），但通道里留着：
     * loader 这条路要能被调起来，不能因为暂时没人用就从生成器视野里消失。
     */
    @DartCall
    @Suppress("DEPRECATION")
    fun launchLoader(loaderPath: String, activityContext: Context, args: Array<String>) {
        val jar = File(loaderPath)
        if (!jar.exists()) {
            throw RuntimeException("loader jar not existed: ${jar.absolutePath}")
        }

        // Android 14+ DexClassLoader 要求 jar 只读，否则抛 SecurityException
        jar.setReadOnly()
        // 上一局会留下占位进程；一个进程只放得下一条 loader（或一个 JVM），
        // 不清掉的话下一次启动会在组件工厂里失败
        GameProcess.killGameProcess(activityContext.applicationContext)
        val intent = Intent(activityContext, MindustryActivity::class.java)
        intent.putExtra("copper_loader_jar", jar.absolutePath)
        intent.putExtra("copper_args", args)
        activityContext.startActivity(intent)
        // 启动器已经用主题色罩住自己：淡入淡出比系统默认滑动更稳，不会滑到一半停住
        if (activityContext is Activity) {
            activityContext.overridePendingTransition(
                android.R.anim.fade_in,
                android.R.anim.fade_out,
            )
        }
    }

    /**
     * 在设备上跑 `ArtBuilder`，生成 dex 缓存。
     *
     * 会一直阻塞到构建结束（读 jar、写 dex），所以标成异步：生成器放进 `Thread`，
     * 结果回主线程；平台线程等这个会把整条通道卡住。
     */
    @DartAsyncCall
    fun buildLoader(loaderPath: String, args: Array<String>) {
        val jar = File(loaderPath)
        if (!jar.exists()) {
            throw RuntimeException("loader jar not existed: ${jar.absolutePath}")
        }

        jar.setReadOnly()
        val classLoader = ContainerClassLoader(jar.absolutePath, Loader::class.java.classLoader)
        try {
            classLoader
                .loadClass("copper.launch.ArtBuilder")
                .getDeclaredMethod("main", Array<String>::class.java)
                .invoke(null, args as Any)
        } catch (error: Throwable) {
            throw RuntimeException("failed to build", error)
        }
    }
}
