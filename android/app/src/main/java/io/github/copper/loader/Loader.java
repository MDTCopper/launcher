package io.github.copper.loader;

import android.app.*;
import android.content.*;
import java.io.*;

import io.github.copper.ContainerClassLoader;
import io.github.copper.GameProcess;
import io.github.copper.MindustryActivity;

@SuppressWarnings("unused")
public class Loader {
    /** Starts the loader through MindustryActivity, passing the loader jar and its arguments. */
    public static void launch(String loaderPath, Context activityContext, String[] args) {
        File jar = new File(loaderPath);
        if (!jar.exists())
            throw new RuntimeException("loader jar not existed: " + jar.getAbsolutePath());

        // readonly is required on Android 14 and above, or SecurityException will be thrown by DexClassLoader
        jar.setReadOnly();
        // A previous run leaves the placeholder's process behind; one process holds one loader - or one
        // JVM on the bridge path - so a launch into a living one fails inside the component factory.
        GameProcess.kill(activityContext);
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
}
