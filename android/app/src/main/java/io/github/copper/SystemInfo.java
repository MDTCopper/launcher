package io.github.copper;

import android.app.*;
import android.content.*;

/**
 * Device memory, straight from the activity manager.
 *
 * <p>Extracted from {@code io.github.copper.loader.Loader} when the bridge path arrived: nothing
 * about it is loader-specific, and it is read while deciding how much heap a game run may ask for.</p>
 */
@SuppressWarnings("unused")
public class SystemInfo {
    /** Get native memory info. */
    public static MemoryInfo getMemoryInfo(Context applicationContext) {
        ActivityManager manager = applicationContext.getSystemService(ActivityManager.class);
        ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(info);
        return new MemoryInfo(info);
    }

    /** Get art heap memory info. */
    public static HeapMemoryInfo getHeapMemoryInfo(Context applicationContext) {
        ActivityManager manager = applicationContext.getSystemService(ActivityManager.class);
        HeapMemoryInfo info = new HeapMemoryInfo();
        info.normalSize = manager.getMemoryClass();
        info.largeSize = manager.getLargeMemoryClass();
        return info;
    }

    /** Heap memory info of ART. */
    public static class HeapMemoryInfo {
        /** dalvik.vm.heapgrowthlimit, unit: megabytes */
        public int normalSize;
        /** dalvik.vm.heapsize, unit: megabytes */
        public int largeSize;
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

    private SystemInfo() {
    }
}
