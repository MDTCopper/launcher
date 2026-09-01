package io.github.copper.loader;

import android.annotation.*;
import android.app.*;
import android.content.*;
import androidx.annotation.*;
import androidx.core.app.*;
import java.io.*;
import java.util.*;
import dalvik.system.*;

/**
 * The app's {@link CoreComponentFactory}: intercepts activity instantiation.
 *
 * <p>When the launcher starts {@link MindustryActivity} (the "launch" action), this
 * factory loads the loader jar with a child-first {@link ContainerClassLoader}, runs
 * {@code ArtLauncher.main()} with the intent arguments, and returns the game's
 * main activity. If the launch fails, a {@link MindustryActivity} showing the error
 * stack trace is returned instead.</p>
 */
@SuppressLint("RestrictedApi")
public class LoaderComponentFactory extends CoreComponentFactory {
    @NonNull
    @Override
    public Activity instantiateActivity(@NonNull ClassLoader cl, @NonNull String className, @Nullable Intent intent) throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        // only MindustryActivity is special; everything else is created normally
        if (!className.equals("io.github.copper.loader.MindustryActivity"))
            return super.instantiateActivity(cl, className, intent);

        // the launcher passed the loader jar location and its arguments via extras
        String loaderJar = intent.getStringExtra("copper_loader_jar");
        String[] args = intent.getStringArrayExtra("copper_args");
        intent.removeExtra("copper_loader_jar");
        intent.removeExtra("copper_args");

        try {
            // child-first classloader: own classes from the loader dex win over the app's
            ClassLoader copper = new ContainerClassLoader(loaderJar, cl);

            // boot the loader, then take the game's main class and use it as the activity
            copper.loadClass("copper.launch.ArtLauncher")
                    .getDeclaredMethod("main", String[].class)
                    .invoke(null, (Object) args);

            Object game = copper.loadClass("copper.loader.Loader")
                    .getDeclaredField("game").get(null);
            Class<?> main = (Class<?>) game.getClass()
                    .getDeclaredMethod("getMainClass").invoke(game);
            return (Activity) main.getDeclaredConstructor().newInstance();
        } catch (Throwable e) {
            // launch failed: show the stack trace in a MindustryActivity instead
            try {
                StringWriter writer = new StringWriter();
                PrintWriter pw = new PrintWriter(writer);
                e.printStackTrace(pw);
                pw.flush();

                Activity activity = (Activity) cl.loadClass(className).getDeclaredConstructor().newInstance();
                activity.getClass().getDeclaredField("errorMessage")
                        .set(activity, writer.toString());
                return activity;
            } catch (Throwable t) {
                throw new RuntimeException(t);
            }
        }
    }
}
