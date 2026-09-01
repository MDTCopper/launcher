package io.github.copper.loader;

import dalvik.system.*;

public class ContainerClassLoader extends DexClassLoader {
    public ContainerClassLoader(String dexPath, ClassLoader parent) {
        super(dexPath, dexPath, null, parent);
    }

    @Override
    protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
        Class<?> c = findLoadedClass(name);
        if (c == null) {
            try {
                c = findClass(name);
            } catch (Throwable ignored) {}
        }
        if (c == null)
            c = getParent().loadClass(name);
        if (c == null)
            throw new ClassNotFoundException(name);
        if (resolve)
            resolveClass(c);
        return c;
    }
}
