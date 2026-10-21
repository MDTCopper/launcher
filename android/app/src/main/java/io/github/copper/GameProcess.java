package io.github.copper;

import android.app.*;
import android.content.*;
import android.util.*;

import java.io.File;
import java.io.IOException;
import java.util.List;

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

    /** Written by {@link CopperApplication} in the game process when its last activity is gone. */
    private static final String EXIT_MARKER = "game-exit.marker";

    /** Kills that process if one is still there, and waits until it is really gone. */
    public static void kill(Context context) {
        clearExitMarker(context);
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
        List<ActivityManager.RunningAppProcessInfo> processes = manager.getRunningAppProcesses();
        if (processes == null)
            return -1;
        String name = context.getPackageName() + SUFFIX;
        for (ActivityManager.RunningAppProcessInfo process : processes)
            if (name.equals(process.processName))
                return process.pid;
        return -1;
    }

    /**
     * Whether the game is still running, or null when the system will not say.
     *
     * <p>The launcher asks this when it returns to the foreground: coming back does not mean the game
     * ended, the player may just have switched apps. A null answer is "unknown" and the caller falls
     * back to treating it as ended, so a device that hides the process list cannot make the launcher
     * wait for an exit that never gets reported.</p>
     *
     * <p>A living process alone is not enough: a clean ending leaves :mdt_process behind on purpose,
     * so the game's own activity going away is the exit signal. It arrives from the game process,
     * which may still be on its way when the launcher is already back; wait for it briefly instead
     * of reporting a game that is already gone.</p>
     */
    public static Boolean isRunning(Context context) {
        if (consumeExitMarker(context))
            return false;

        ActivityManager manager = context.getSystemService(ActivityManager.class);
        if (manager == null)
            return null;
        List<ActivityManager.RunningAppProcessInfo> processes = manager.getRunningAppProcesses();
        if (processes == null)
            return null;

        String name = context.getPackageName() + SUFFIX;
        if (!hasProcess(processes, name))
            return false;

        for (int waited = 0; waited < 20; waited++) {
            try {
                Thread.sleep(50);
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                break;
            }
            if (consumeExitMarker(context))
                return false;
            if (!hasProcess(manager.getRunningAppProcesses(), name))
                return false;
        }
        return true;
    }

    private static boolean hasProcess(List<ActivityManager.RunningAppProcessInfo> processes, String name) {
        if (processes == null)
            return true; // cannot tell; do not turn a running game into an exit
        for (ActivityManager.RunningAppProcessInfo process : processes)
            if (name.equals(process.processName))
                return true;
        return false;
    }

    /** Called from the game process when its last activity goes away. */
    static void markGameExited(Context context) {
        File marker = exitMarker(context);
        try {
            File parent = marker.getParentFile();
            if (parent != null && !parent.exists())
                parent.mkdirs();
            if (marker.createNewFile())
                Log.i("Copper", "game-exit marker written");
        } catch (IOException error) {
            Log.w("Copper", "cannot write game-exit marker", error);
        }
    }

    /** A stale marker must not make the next run look like it already ended. */
    static void clearExitMarker(Context context) {
        File marker = exitMarker(context);
        if (marker.exists() && !marker.delete())
            Log.w("Copper", "cannot clear game-exit marker");
    }

    private static boolean consumeExitMarker(Context context) {
        File marker = exitMarker(context);
        if (!marker.exists())
            return false;
        if (marker.delete())
            Log.i("Copper", "game-exit marker read: game exited");
        return true;
    }

    private static File exitMarker(Context context) {
        return new File(context.getFilesDir(), EXIT_MARKER);
    }

    private GameProcess() {
    }
}
