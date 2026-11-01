package io.github.copper.launcher

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import androidx.core.app.CoreComponentFactory
import io.github.copper.launcher.game.ContainerClassLoader
import io.github.copper.launcher.game.MindustryActivity
import java.io.PrintWriter
import java.io.StringWriter

/**
 * 应用的 [CoreComponentFactory]：只接管占位 Activity 的实例化。
 *
 * 两种跑游戏的方式都向系统要同一个 [MindustryActivity]，靠 intent extras 区分：
 * 带 `copper_bridge_args` 的走桥（真 JVM），否则走 copper loader（ART）。
 * 其他 Activity 一律交给系统正常创建。
 */
@SuppressLint("RestrictedApi")
class CopperComponentFactory : CoreComponentFactory() {

    override fun instantiateActivity(
        cl: ClassLoader,
        className: String,
        intent: Intent?,
    ): Activity {
        // 只有占位 Activity 特殊；其余正常创建
        if (className != PLACEHOLDER) return super.instantiateActivity(cl, className, intent)

        // 两条路径共用一个占位 Activity，extras 是唯一区分依据
        return if (intent?.hasExtra("copper_bridge_args") == true) {
            launchBridge(cl, className, intent)
        } else {
            launchLoader(cl, className, intent)
        }
    }

    /** ART 路径：跑 copper loader，返回游戏自己的主 Activity。 */
    private fun launchLoader(cl: ClassLoader, className: String, intent: Intent?): Activity {
        val loaderJar = intent?.getStringExtra("copper_loader_jar")
        val args = intent?.getStringArrayExtra("copper_args")
        intent?.removeExtra("copper_loader_jar")
        intent?.removeExtra("copper_args")

        return try {
            // 子优先加载器：loader dex 里的类压过宿主同名类
            val copper = ContainerClassLoader(loaderJar.orEmpty(), cl)

            // 先起 loader，再取游戏主类，拿它当 Activity
            copper.loadClass("copper.launch.ArtLauncher")
                .getDeclaredMethod("main", Array<String>::class.java)
                .invoke(null, args as Any)

            val game = copper.loadClass("copper.loader.Loader")
                .getDeclaredField("game")
                .get(null)
            val main = game.javaClass.getDeclaredMethod("getMainClass").invoke(game) as Class<*>
            main.getDeclaredConstructor().newInstance() as Activity
        } catch (error: Throwable) {
            // 启动失败：把堆栈交给一个 MindustryActivity 显示
            failure(cl, className, error)
        }
    }

    /**
     * JVM 路径：把参数交给桥，返回桥建好的 Activity。
     *
     * bridge 不是一个 app，它的 ART 侧只有 jar 里的 `copper.bridge.art.Main`。
     * `main` 解析参数并加载原生库，`launch` 返回系统要的 Activity；所以这个 Activity
     * 既不可能、也没必要写进清单。
     */
    private fun launchBridge(cl: ClassLoader, className: String, intent: Intent?): Activity {
        val bridgeJar = intent?.getStringExtra("copper_bridge_jar")
        val args = intent?.getStringArrayExtra("copper_bridge_args")
        intent?.removeExtra("copper_bridge_jar")
        intent?.removeExtra("copper_bridge_args")

        // 桥要靠 jar 位置拼 JVM classpath；这个选项必须插在调用方第一个 `--` 之前，
        // 之后的词都按位置参数原样交给 loader / 游戏
        val bridgeArgs = withBridgeJar(args, bridgeJar)

        return try {
            // 与 ART 路径同一个子优先加载器；bridge.jar 既是类来源，也是原生库/版本资源来源
            val bridge = ContainerClassLoader(bridgeJar.orEmpty(), cl)
            val entry = bridge.loadClass("copper.bridge.art.Main")
            entry.getDeclaredMethod("main", Array<String>::class.java).invoke(null, bridgeArgs as Any)
            entry.getDeclaredMethod("launch").invoke(null) as Activity
        } catch (error: Throwable) {
            failure(cl, className, error)
        }
    }

    /** 在调用方第一个 `--` 前插入 `--bridge-jar <jar>`；没有就追加到末尾。 */
    private fun withBridgeJar(args: Array<String>?, bridgeJar: String?): Array<String> {
        if (bridgeJar == null) return args ?: emptyArray()
        val original = args ?: emptyArray()
        val at = original.indexOf("--").let { if (it < 0) original.size else it }
        return buildList {
            addAll(original.take(at))
            add("--bridge-jar")
            add(bridgeJar)
            addAll(original.drop(at))
        }.toTypedArray()
    }

    /** 显示堆栈是失败时唯一还有用的事。 */
    private fun failure(cl: ClassLoader, className: String, error: Throwable): Activity {
        return try {
            val writer = StringWriter()
            PrintWriter(writer).use { error.printStackTrace(it) }
            val activity = cl.loadClass(className).getDeclaredConstructor().newInstance()
                as MindustryActivity
            activity.errorMessage = writer.toString()
            activity
        } catch (failure: Throwable) {
            throw RuntimeException(failure)
        }
    }

    private companion object {
        /**
         * 两条路径共用这一个占位名，必须与清单、[io.github.copper.launcher.launch.Bridge] /
         * [io.github.copper.launcher.launch.Loader] 完全一致；对不上会落到真正的占位 Activity，
         * 它什么都不说就把自己关掉。
         */
        const val PLACEHOLDER = "io.github.copper.launcher.game.MindustryActivity"
    }
}
