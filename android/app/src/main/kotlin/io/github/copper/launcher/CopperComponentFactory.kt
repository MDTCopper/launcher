package io.github.copper.launcher

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.util.Log
import androidx.core.app.CoreComponentFactory
import io.github.copper.launcher.game.ContainerClassLoader
import io.github.copper.launcher.game.MindustryActivity
import java.io.File
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
     * JVM 路径：参数交给桥的 `main`，活动由桥的加载器造 —— 启动器的启动画面是 [ACTIVITY] 这个子类。
     *
     * <p>子类必须由同一个加载器定义：父类只在 bridge.jar 里，所以 dex 路径同时给 bridge.jar 和宿主 APK。
     * 子类不在（或造不出来）就退回桥自己的 [BASE_ACTIVITY]。</p>
     */
    private fun launchBridge(cl: ClassLoader, className: String, intent: Intent?): Activity {
        val bridgeJar = intent?.getStringExtra("copper_bridge_jar")
        val apkPath = intent?.getStringExtra("copper_bridge_apk")
        val args = intent?.getStringArrayExtra("copper_bridge_args")
        intent?.removeExtra("copper_bridge_jar")
        intent?.removeExtra("copper_bridge_apk")
        intent?.removeExtra("copper_bridge_args")

        // 桥要靠 jar 位置拼 JVM classpath；这个选项必须插在调用方第一个 `--` 之前，
        // 之后的词都按位置参数原样交给 loader / 游戏
        val bridgeArgs = withBridgeJar(args, bridgeJar)

        return try {
            // 与 ART 路径同一个子优先加载器；bridge.jar 既是类来源，也是原生库/版本资源来源
            val bridge = ContainerClassLoader(dexPath(bridgeJar, apkPath), cl)
            bridge.loadClass(ENTRY).getDeclaredMethod("main", Array<String>::class.java)
                .invoke(null, bridgeArgs as Any)
            instantiate(bridge, ACTIVITY)
                ?: instantiate(bridge, BASE_ACTIVITY)
                ?: throw IllegalStateException("bridge jar carries no $BASE_ACTIVITY")
        } catch (error: Throwable) {
            failure(cl, className, error)
        }
    }

    /** 桥的加载器看两处：自己的 jar 在前，宿主 APK 在后（只为启动器自己的子类）。 */
    private fun dexPath(bridgeJar: String?, apkPath: String?): String = when {
        bridgeJar.isNullOrEmpty() -> apkPath.orEmpty()
        apkPath.isNullOrEmpty() -> bridgeJar
        else -> bridgeJar + File.pathSeparator + apkPath
    }

    /** 由 [loader] 定义并造出这个 Activity；这个类不在（或造不出来）就交给调用方换下一个。 */
    private fun instantiate(loader: ClassLoader, name: String): Activity? = try {
        loader.loadClass(name).getDeclaredConstructor().newInstance() as Activity
    } catch (missing: ClassNotFoundException) {
        null
    } catch (error: Throwable) {
        // 能造出来却坏了是另一回事：记下来，退回桥自己的活动，别让一次显示问题毁掉整局
        Log.w(TAG, "cannot build $name; falling back", error)
        null
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

        /** 桥的 ART 入口：解析参数、加载原生库。 */
        const val ENTRY = "copper.bridge.art.Main"

        /** 桥自己的活动：没有子类、或子类造不出来时用它，游戏照样能起来（只是没有启动画面）。 */
        const val BASE_ACTIVITY = "copper.bridge.art.BridgeActivity"

        /** 启动器的桥活动子类：铜色启动画面。由桥的加载器定义，见 [launchBridge]。 */
        const val ACTIVITY = "io.github.copper.launcher.game.CopperGameActivity"

        const val TAG = "CopperComponentFactory"
    }
}
