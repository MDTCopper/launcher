package io.github.copper.bridge;

import android.content.Context;
import android.content.Intent;

import io.github.copper.GameProcess;
import io.github.copper.MindustryActivity;

import java.io.File;

/**
 * Placeholder entry of the bridge: a real JVM, instead of the copper loader on ART.
 *
 * <p>The counterpart of {@link io.github.copper.loader.Loader#launch}, and deliberately the same
 * shape: the caller builds the whole argument vector and names the jar, this only hands both to the
 * placeholder activity, and the component factory turns it into the activity the bridge builds.
 * What the run needs - the game jar, the data and cache folders, the JVM, arc's native libraries -
 * is the argument vector's business, not this class's.</p>
 */
public class Bridge {
    /** Starts the bridge through {@link MindustryActivity}, passing the bridge jar and its arguments. */
    public static void launch(String bridgePath, Context activityContext, String[] args) {
        File jar = new File(bridgePath);
        if (!jar.exists())
            throw new RuntimeException("bridge jar not existed: " + jar.getAbsolutePath());

        // readonly is required on Android 14 and above, or SecurityException will be thrown by DexClassLoader
        jar.setReadOnly();
        // A previous run leaves the placeholder's process behind; one process holds one JVM - or one
        // loader on the ART path - so a launch into a living one fails inside the component factory.
        GameProcess.kill(activityContext);
        Intent intent = new Intent(activityContext, MindustryActivity.class);
        intent.putExtra("copper_bridge_jar", jar.getAbsolutePath());
        intent.putExtra("copper_bridge_args", args);
        activityContext.startActivity(intent);
    }

    private Bridge() {
    }
}
