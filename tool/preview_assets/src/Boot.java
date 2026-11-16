import arc.files.Fi;
import mindustry.Vars;
import mindustry.core.ContentLoader;

import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.ZipFile;

/**
 * CPU-only 内容引导与公共工具（无 GL、无窗口、无 Arc Application）
 *
 * 引导步骤与 tmp/bp-research/map/Spike.java 验证过的五步配方一致：
 * Vars.content = new ContentLoader() → createBaseContent() → 建 world/state
 * → Core.settings → init() → Core.files + loadColors()
 * 全程不碰 Texture / Core.atlas / GL
 */
public class Boot {
    /** 引导是否已做过；同一进程里多个工具复用一次引导（PackBuilder 走这条） */
    private static boolean bootstrapped;
    private static boolean colorsLoaded;

    /** 显式指定本次使用的游戏 jar（PackBuilder 显式参数模式）；不设则取 classpath 第一个 jar */
    private static File jarOverride;

    static void useJar(File jar) {
        jarOverride = jar;
    }

    /** 从 classpath 里找游戏 jar（取第一个 .jar），调用方必须把 jar 放在 classpath 最前面 */
    static File locateJar() {
        if (jarOverride != null) return jarOverride;
        for (String p : System.getProperty("java.class.path").split(File.pathSeparator)) {
            if (p.endsWith(".jar")) return new File(p);
        }
        throw new IllegalStateException("no jar on classpath");
    }

    /**
     * 执行 CPU-only 引导，返回耗时毫秒；同一进程里重复调用直接复用（必要时补 loadColors）
     *
     * @param loadColors 是否读取 jar 内的 sprites/block_colors.png 设置 mapColor
     *                   （v6 等老 jar 的 Arc native 可能不可用，此时传 false 跳过）
     */
    static double bootstrap(boolean loadColors) throws Exception {
        if (bootstrapped) {
            if (loadColors && !colorsLoaded) loadColors();
            return 0;
        }
        long t0 = System.nanoTime();
        Vars.content = new ContentLoader();
        Vars.content.createBaseContent();
        Vars.world = new mindustry.core.World();
        Vars.state = new mindustry.core.GameState();
        if (arc.Core.settings == null) arc.Core.settings = new arc.Settings();
        Vars.content.init();
        bootstrapped = true;
        if (loadColors) loadColors();
        return (System.nanoTime() - t0) / 1_000_000.0;
    }

    private static void loadColors() throws Exception {
        arc.Core.files = new JarFiles(locateJar(), Files.createTempDirectory("mindustry-preview-assets"));
        Vars.content.loadColors();
        colorsLoaded = true;
    }

    /** 以游戏 jar 为后端的 arc.Files 最小实现，仅 internal() 会被用到 */
    static class JarFiles implements arc.Files {
        final ZipFile zip;
        final Path tmp;
        final Map<String, Fi> extracted = new HashMap<>();

        JarFiles(File jar, Path tmp) throws Exception {
            this.zip = new ZipFile(jar);
            this.tmp = tmp;
        }

        @Override
        public Fi get(String path, FileType type) {
            if (type == FileType.internal || type == FileType.classpath) {
                return extracted.computeIfAbsent(path, p -> {
                    try (var is = zip.getInputStream(zip.getEntry(p))) {
                        Path dst = tmp.resolve(p);
                        Files.createDirectories(dst.getParent());
                        Files.copy(is, dst, StandardCopyOption.REPLACE_EXISTING);
                        return new Fi(dst.toFile());
                    } catch (Exception e) {
                        throw new RuntimeException("cannot extract jar entry " + p, e);
                    }
                });
            }
            return new Fi(path);
        }

        @Override public String getExternalStoragePath() { return tmp.toAbsolutePath().toString(); }
        @Override public boolean isExternalStorageAvailable() { return true; }
        @Override public String getLocalStoragePath() { return tmp.toAbsolutePath().toString(); }
        @Override public boolean isLocalStorageAvailable() { return true; }
    }

    /// 取静态实例的字段名：BuildVisibility / CacheLayer 这类类没有稳定的 toString，
    /// 直接 toString 会带对象哈希，导致每次生成的 content.json 不一致
    static String staticName(Object instance) {
        if (instance == null) return null;
        Class<?> type = instance.getClass();
        for (Field field : type.getFields()) {
            if (!Modifier.isStatic(field.getModifiers()) || field.getType() != type) continue;
            try {
                if (field.get(null) == instance) return field.getName();
            } catch (IllegalAccessException ignored) {
                // 跳过不可读字段，继续找
            }
        }
        return type.getSimpleName();
    }
    /** JSON 字符串转义（null 原样输出 null） */
    static String esc(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder(s.length() + 4);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
            }
        }
        return b.toString();
    }

    /** JSON 字符串字段 */
    static String q(String s) { return s == null ? "null" : "\"" + esc(s) + "\""; }

    static String hex(arc.graphics.Color c) {
        if (c == null) return "null";
        return String.format("\"%02x%02x%02x%02x\"", (int) (c.r * 255), (int) (c.g * 255),
                (int) (c.b * 255), (int) (c.a * 255));
    }

    /** 六位颜色串（忽略 alpha） */
    static String rgb(arc.graphics.Color c) {
        if (c == null) return "null";
        return String.format("\"%02x%02x%02x\"", (int) (c.r * 255), (int) (c.g * 255), (int) (c.b * 255));
    }

    static double ms(long t0) { return (System.nanoTime() - t0) / 1_000_000.0; }
}
