package io.github.copper.launcher.game

import dalvik.system.DexClassLoader

/**
 * 子优先类加载器：dex 路径里的类先于宿主解析，找不到再交给父加载器。
 *
 * 两条游戏运行路径都靠它把外置 jar 里的类挡在宿主前面。
 *
 * 桥这条路会把它指向**两样东西**：`bridge.jar` 和宿主 APK。前者是桥的类，后者是启动器自己的
 * 桥活动子类 —— 子类必须由这个加载器定义，否则它的父类（`BridgeActivity`，只在 bridge.jar 里）
 * 会顺着宿主加载器找，找不到。
 *
 * `optimizedDirectory` 传 null：API 26 起它被忽略，dex 由系统在内存/默认目录里优化（minSdk 30）。
 */
class ContainerClassLoader(dexPath: String, parent: ClassLoader) :
    DexClassLoader(dexPath, null, null, parent) {

    override fun loadClass(name: String, resolve: Boolean): Class<*> {
        var loaded = findLoadedClass(name)
        if (loaded == null) {
            loaded = try {
                findClass(name)
            } catch (_: Throwable) {
                null
            }
        }
        if (loaded == null) loaded = parent.loadClass(name)
        if (resolve) resolveClass(loaded)
        return loaded
    }
}
