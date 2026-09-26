package io.github.copper;

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
 * <p>Two activities are built here rather than by the system, because both are stubs that stand in
 * for something the app loads itself:</p>
 *
 * <ul>
 *   <li>{@link MindustryActivity} - the placeholder the launcher asks for. Two ways of running the
 *       game are built from it, told apart by the extras: the copper loader on ART, and the bridge,
 *       a real JVM started by {@code copper.bridge.art.Main}. The bridge path was ported from the
 *       bridge's own test app; only that app's probes were left behind.</li>
 * </ul>
 *
 * <p>Everything else is created normally.</p>
 */
@SuppressLint("RestrictedApi")
public class CopperComponentFactory extends CoreComponentFactory {
    /**
     * The one placeholder: both ways of running the game are asked for by this name. It has to match
     * the manifest entry and {@code Bridge.launch} / {@code Loader.launch} exactly - it did not, and a
     * launch fell through to the real placeholder, which finished itself without a word.
     */
    private static final String PLACEHOLDER = "io.github.copper.MindustryActivity";

    @NonNull
    @Override
    public Activity instantiateActivity(@NonNull ClassLoader cl, @NonNull String className, @Nullable Intent intent) throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        // only the placeholder is special; everything else is created normally
        if (!className.equals(PLACEHOLDER))
            return super.instantiateActivity(cl, className, intent);

        // The two paths share the placeholder, so the extras decide which one this is: only the
        // bridge's launch carries an argument vector under its own name.
        if (intent != null && intent.hasExtra("copper_bridge_args"))
            return launchBridge(cl, className, intent);

        return launchLoader(cl, className, intent);
    }

    /** The ART path: run the copper loader and return the game's own main activity. */
    private Activity launchLoader(ClassLoader cl, String className, Intent intent) {
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
            return failure(cl, className, e);
        }
    }

    /**
     * The JVM path: hand the arguments to the bridge and return the activity it builds.
     *
     * <p>The bridge is not an app. Its ART side is one class, {@code copper.bridge.art.Main}, inside a
     * jar this app loads itself; {@code main} parses the arguments and loads the bridge's native
     * library, then {@code launch} returns the activity the system is asking for. That activity is
     * handed straight back, so declaring it in the manifest is neither possible nor necessary.</p>
     */
    private Activity launchBridge(ClassLoader cl, String className, Intent intent) {
        String bridgeJar = intent.getStringExtra("copper_bridge_jar");
        String[] args = intent.getStringArrayExtra("copper_bridge_args");
        intent.removeExtra("copper_bridge_jar");
        intent.removeExtra("copper_bridge_args");

        // The bridge cannot start a JVM without knowing which jar it came out of: that jar is the only
        // place copper.bridge.jvm.Main exists, and the JVM's class path is built from it.
        args = withBridgeJar(args, bridgeJar);

        try {
            // The same child-first loader the ART path uses. The bridge's classes have to come out of
            // bridge.jar, which is also the file it reads its native library and version resource from
            // - so the jar, not an extracted dex, is what this class loader is given (decision 29).
            ClassLoader bridge = new ContainerClassLoader(bridgeJar, cl);

            Class<?> entry = bridge.loadClass("copper.bridge.art.Main");
            entry.getDeclaredMethod("main", String[].class).invoke(null, (Object) args);
            return (Activity) entry.getDeclaredMethod("launch").invoke(null);
        } catch (Throwable e) {
            return failure(cl, className, e);
        }
    }

    /**
     * The arguments, plus the jar the bridge was loaded from.
     *
     * <p>The caller builds the vector and neither knows nor has to know where the jar it is loading
     * came from; the bridge needs it to build the JVM's class path. It is inserted before the caller's
     * first {@code --}: from there on the bridge reads every word as a positional argument - which is
     * how the caller hands loader options and game arguments over untouched - and the jar is the one
     * option that must never become one.</p>
     */
    private static String[] withBridgeJar(String[] args, String bridgeJar) {
        if (bridgeJar == null)
            return args;
        String[] original = args == null ? new String[0] : args;

        int at = original.length;
        for (int i = 0; i < original.length; i++) {
            if ("--".equals(original[i])) {
                at = i;
                break;
            }
        }

        String[] result = new String[original.length + 2];
        System.arraycopy(original, 0, result, 0, at);
        result[at] = "--bridge-jar";
        result[at + 1] = bridgeJar;
        System.arraycopy(original, at, result, at + 2, original.length - at);
        return result;
    }

    /** Shows the stack trace instead of the game, which is the only useful thing left to do. */
    private Activity failure(ClassLoader cl, String className, Throwable e) {
        try {
            StringWriter writer = new StringWriter();
            PrintWriter pw = new PrintWriter(writer);
            e.printStackTrace(pw);
            pw.flush();

            Activity activity = (Activity) cl.loadClass(className).getDeclaredConstructor().newInstance();
            activity.getClass().getDeclaredField("errorMessage").set(activity, writer.toString());
            return activity;
        } catch (Throwable t) {
            throw new RuntimeException(t);
        }
    }
}
