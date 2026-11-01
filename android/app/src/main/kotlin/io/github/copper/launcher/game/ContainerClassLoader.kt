package io.github.copper.launcher.game

import dalvik.system.DexClassLoader

/**
 * 子优先类加载器：loader / bridge jar 里的类先于宿主解析，找不到再交给父加载器。
 *
 * 两条游戏运行路径都靠它把外置 jar 里的类挡在宿主前面。
 */
class ContainerClassLoader(dexPath: String, parent: ClassLoader) :
    DexClassLoader(dexPath, dexPath, null, parent) {

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
