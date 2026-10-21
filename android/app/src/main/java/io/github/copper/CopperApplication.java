package io.github.copper;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;

/**
 * The app's Application.
 *
 * <p>The bridge leaves its process behind after a clean exit ({@link GameProcess} strips the
 * leftover before the next launch), so "is :mdt_process still there" cannot tell a running game
 * from an exited one. What does change is the game activity: when the last one goes away, the
 * game is over. That happens in the game's process, so record it there and let the launcher read
 * it when it comes back to the foreground.</p>
 */
public class CopperApplication extends Application {
    private static final String GAME_PROCESS_SUFFIX = ":mdt_process";

    private int activityCount;

    @Override
    public void onCreate() {
        super.onCreate();

        String process = getProcessName();
        if (process == null || !process.endsWith(GAME_PROCESS_SUFFIX))
            return;

        // a new run starts clean; a marker from an earlier one must not look like this run's exit
        GameProcess.clearExitMarker(this);

        registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
            @Override
            public void onActivityCreated(Activity activity, Bundle state) {
                activityCount++;
            }

            @Override
            public void onActivityStarted(Activity activity) {
            }

            @Override
            public void onActivityResumed(Activity activity) {
            }

            @Override
            public void onActivityPaused(Activity activity) {
            }

            @Override
            public void onActivityStopped(Activity activity) {
                // onStop lands before the launcher's onResume; wait for onDestroy would race it
                if (activity.isFinishing() && activityCount <= 1)
                    GameProcess.markGameExited(CopperApplication.this);
            }

            @Override
            public void onActivitySaveInstanceState(Activity activity, Bundle state) {
            }

            @Override
            public void onActivityDestroyed(Activity activity) {
                if (activityCount > 0)
                    activityCount--;
                if (activityCount == 0)
                    GameProcess.markGameExited(CopperApplication.this);
            }
        });
    }
}
