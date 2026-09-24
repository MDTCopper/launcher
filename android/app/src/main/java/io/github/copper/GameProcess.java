package io.github.copper;

import android.app.*;
import android.content.*;
import android.util.*;

/**
 * This app's placeholder process, where the game screen - the loader's or the bridge's - runs.
 *
 * <p>A clean ending leaves that process behind on purpose: the screen animates out and nothing tears
 * the process down. The next launch takes it out first, because bridge.jar is loaded through a fresh
 * class loader every launch and a leftover copy makes the second one fail with
 * {@code UnsatisfiedLinkError: … already opened by ClassLoader 0x…}.</p>
 *
 * <p>The wait is the point. Killing and starting in the same breath races the process's own teardown
 * - the system is still taking its activities down, and a launch that lands in that race arrives
 * without its transition, which is why starting a game right after closing one looked like it had no
 * animation while starting one a moment later looked fine. The wait is bounded, because a process
 * that will not die must not hold the button forever.</p>
 *
 * <p>Only this app's own processes are visible here, which is all this needs.</p>
 */
public class GameProcess {
    /** The placeholder activity's process, appended to the package name. */
    private static final String SUFFIX = ":mdt_process";

    /** Kills that process if one is still there, and waits until it is really gone. */
    public static void kill(Context context) {
        int pid = pid(context);
        Log.i("Copper", "killGameProcess: leftover pid=" + pid);
        if (pid < 0)
            return;

        android.os.Process.killProcess(pid);
        for (int waited = 0; waited < 40; waited++) {
            if (pid(context) < 0) {
                Log.i("Copper", "killGameProcess: " + pid + " gone after " + waited * 25 + " ms");
                return;
            }
            try {
                Thread.sleep(25);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
        Log.i("Copper", "killGameProcess: " + pid + " still there after 1000 ms");
    }

    /** The pid of that process, or -1 when it is not running. */
    private static int pid(Context context) {
        ActivityManager manager = context.getSystemService(ActivityManager.class);
        if (manager == null)
            return -1;
        String name = context.getPackageName() + SUFFIX;
        for (ActivityManager.RunningAppProcessInfo process : manager.getRunningAppProcesses())
            if (name.equals(process.processName))
                return process.pid;
        return -1;
    }

    private GameProcess() {
    }
}
