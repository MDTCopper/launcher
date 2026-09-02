package io.github.copper.loader;

import android.app.*;
import android.content.*;
import java.io.*;

@SuppressWarnings("unused")
public class Loader {
    /** Starts the loader through MindustryActivity, passing the loader jar and its arguments. */
    public static void launch(String loaderPath, Context activityContext, String[] args) {
        File jar = new File(loaderPath);
        if (!jar.exists())
            throw new RuntimeException("loader jar not existed: " + jar.getAbsolutePath());

        // readonly is required on Android 14 and above, or SecurityException will be thrown by DexClassLoader
        jar.setReadOnly();
        Intent intent = new Intent(activityContext, MindustryActivity.class);
        intent.putExtra("copper_loader_jar", jar.getAbsolutePath());
        intent.putExtra("copper_args", args);
        activityContext.startActivity(intent);
    }

    /** Runs {@code ArtBuilder} on the device to build the dex cache. */
    public static void build(String loaderPath, String[] args) {
        File jar = new File(loaderPath);
        if (!jar.exists())
            throw new RuntimeException("loader jar not existed: " + jar.getAbsolutePath());

        jar.setReadOnly();
        ClassLoader cl = new ContainerClassLoader(jar.getAbsolutePath(), Loader.class.getClassLoader());
        try {
            cl.loadClass("copper.launch.ArtBuilder")
                    .getDeclaredMethod("main", String[].class)
                    .invoke(null, (Object) args);
        } catch (Throwable e) {
            throw new RuntimeException("failed to build", e);
        }
    }

    /** Get device memory info. */
    public static MemoryInfo getMemoryInfo(Context applicationContext) {
        ActivityManager manager = applicationContext.getSystemService(ActivityManager.class);
        ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(info);
        return new MemoryInfo(info);
    }

    /** Wrapper of android.app.ActivityManager.MemoryInfo */
    public static class MemoryInfo {
        public long availMem;
        public boolean lowMemory;
        public long threshold;
        public long totalMem;

        MemoryInfo(ActivityManager.MemoryInfo info) {
            availMem = info.availMem;
            lowMemory = info.lowMemory;
            threshold = info.threshold;
            totalMem = info.totalMem;
        }
    }
}
