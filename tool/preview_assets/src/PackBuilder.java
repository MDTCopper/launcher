import mindustry.Vars;
import mindustry.world.Block;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 在单个进程内构建整套蓝图预览资产包（不依赖 PowerShell）
 *
 * 用法：java -cp &lt;游戏 jar&gt;;&lt;工具 jar&gt; PackBuilder &lt;gameJar&gt; &lt;outDir&gt; [version]
 *
 * 复用工具集里的既有实现：AtlasDump 解析图集、ContentDump / BlockDrawDump / CanvasDump /
 * DrawerDump 导出内容与规则数据，再按 build_pack.ps1 相同的口径裁切 parts / icons；
 * 全部 CPU-only（无 GL、无窗口），classpath 里游戏 jar 必须排在工具 jar 前面
 */
public class PackBuilder {
    /** parts 里绘制规则共用、但不属于某个方块的 region */
    private static final List<String> EXTRA_PART_NAMES = List.of(
            "center", "cross", "laser", "laser-end",
            "block-1", "block-2", "block-3", "block-4",
            "reinforced-block-2", "reinforced-block-3", "reinforced-block-4", "reinforced-block-5");

    private static final Pattern BLOCK_UI = Pattern.compile("^block-(.+)-ui$");
    private static final Pattern BLOCK_FULL = Pattern.compile("^block-(.+)-full$");
    private static final Pattern ITEM_UI = Pattern.compile("^item-(.+)-ui$");
    private static final Pattern LIQUID_UI = Pattern.compile("^liquid-(.+)-ui$");
    private static final Pattern VERSION_TAG = Pattern.compile("v(\\d+(?:\\.\\d+)*)");
    private static final Pattern BUILD_TAG = Pattern.compile("Build\\s+(\\d+)");

    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("usage: PackBuilder <gameJar> <outDir> [version]");
            System.err.println("       PackBuilder <outDir> [version]   (game jar = classpath first jar)");
            System.exit(2);
        }
        long start = System.nanoTime();
        Path workDir = null;
        try {
            // 兼容两种调用：显式 gameJar，或省掉它直接用 classpath 里的第一个 jar
            File gameJar;
            Path outDir;
            String versionArg;
            final boolean explicitJar = args.length >= 2
                    && (args[0].toLowerCase(Locale.ROOT).endsWith(".jar") || new File(args[0]).isFile());
            if (explicitJar) {
                gameJar = new File(args[0]);
                outDir = Path.of(args[1]);
                versionArg = args.length >= 3 ? args[2] : null;
            } else {
                gameJar = Boot.locateJar();
                outDir = Path.of(args[0]);
                versionArg = args.length >= 2 ? args[1] : null;
            }
            if (!gameJar.isFile()) throw new IOException("game jar not found: " + gameJar.getAbsolutePath());
            Boot.useJar(gameJar);
            outDir = outDir.toAbsolutePath().normalize();
            String version = versionArg != null && !versionArg.isBlank()
                    ? versionArg : deriveVersion(gameJar.getName());
            System.out.printf("[PackBuilder] jar=%s version=%s out=%s%n", gameJar.getName(), version, outDir);

            // 运行时缓存目录由本工具独占，直接整体重建，避免残留上一次的图标/贴图
            deleteRecursively(outDir);
            Files.createDirectories(outDir);
            workDir = Files.createTempDirectory("preview-pack-");

            long stepStart = System.nanoTime();
            AtlasDump.AtlasData atlas = AtlasDump.loadAtlas(gameJar, workDir);
            System.out.printf("[PackBuilder] atlas %.1f ms%n", Boot.ms(stepStart));

            stepStart = System.nanoTime();
            double bootstrapMs = Boot.bootstrap(true);
            System.out.printf("[BOOT] %.1f ms blocks=%d items=%d liquids=%d%n", bootstrapMs,
                    Vars.content.blocks().size, Vars.content.items().size, Vars.content.liquids().size);

            // 四个 dump 工具各自会再调一次 Boot.bootstrap，Boot 已做幂等处理，这里只付一次引导
            ContentDump.main(new String[]{outDir.resolve("content.json").toString()});
            BlockDrawDump.main(new String[]{outDir.resolve("classes.json").toString()});
            CanvasDump.main(new String[]{outDir.resolve("canvas.json").toString()});
            DrawerDump.main(new String[]{outDir.resolve("drawer-spec.json").toString()});

            // parts：方块名相关的 region + 规则共用 region
            stepStart = System.nanoTime();
            List<String> blockNames = new ArrayList<>();
            for (Block block : Vars.content.blocks()) blockNames.add(block.name);
            Path partsDir = outDir.resolve("parts");
            AtlasDump.extract(atlas, partsDir, blockNames, false);
            AtlasDump.extract(atlas, partsDir, EXTRA_PART_NAMES, true);
            int partsCount = countPng(partsDir);
            System.out.printf("[PackBuilder] parts=%d (%.1f ms)%n", partsCount, Boot.ms(stepStart));

            // icons：block 优先 -full 再回退 -ui；item/liquid 取 -*-ui
            stepStart = System.nanoTime();
            Map<String, String> blockUi = new LinkedHashMap<>();
            Map<String, String> blockFull = new LinkedHashMap<>();
            Map<String, String> itemUi = new LinkedHashMap<>();
            Map<String, String> liquidUi = new LinkedHashMap<>();
            for (var region : atlas.regions) {
                String name = region.name;
                if (collect(BLOCK_UI, name, blockUi)) continue;
                if (collect(BLOCK_FULL, name, blockFull)) continue;
                if (collect(ITEM_UI, name, itemUi)) continue;
                collect(LIQUID_UI, name, liquidUi);
            }
            Map<String, String> blockIcons = new LinkedHashMap<>(blockUi);
            blockIcons.putAll(blockFull);

            Path iconsDir = outDir.resolve("icons");
            int blockIconCount = exportIcons(atlas, blockIcons, workDir.resolve("icons-block-raw"),
                    iconsDir.resolve("block"));
            int itemIconCount = exportIcons(atlas, itemUi, workDir.resolve("icons-item-raw"),
                    iconsDir.resolve("item"));
            int liquidIconCount = exportIcons(atlas, liquidUi, workDir.resolve("icons-liquid-raw"),
                    iconsDir.resolve("liquid"));
            int genericIconCount = exportIcons(atlas, Map.of("center", "center", "cross", "cross"),
                    workDir.resolve("icons-generic-raw"), iconsDir.resolve("generic"));
            int iconCount = blockIconCount + itemIconCount + liquidIconCount;
            System.out.printf("[PackBuilder] icons block=%d item=%d liquid=%d generic=%d (%.1f ms)%n",
                    blockIconCount, itemIconCount, liquidIconCount, genericIconCount, Boot.ms(stepStart));

            writeMeta(outDir.resolve("meta.json"), version, gameJar.getName(),
                    Vars.content.blocks().size, blockIconCount, itemIconCount, liquidIconCount,
                    partsCount, iconCount);

            System.out.printf("[PackBuilder] done blocks=%d blockIcons=%d itemIcons=%d liquidIcons=%d "
                            + "parts=%d icons=%d in %.1f ms -> %s%n",
                    Vars.content.blocks().size, blockIconCount, itemIconCount, liquidIconCount,
                    partsCount, iconCount, Boot.ms(start), outDir);
        } catch (Throwable error) {
            System.err.println("[PackBuilder] failed: " + error);
            error.printStackTrace();
            System.exit(1);
        } finally {
            deleteQuietly(workDir);
        }
    }

    /** 按版本号规则从 jar 文件名解析默认版本标签 */
    private static String deriveVersion(String jarFileName) {
        Matcher version = VERSION_TAG.matcher(jarFileName);
        if (version.find()) return "v" + version.group(1);
        Matcher build = BUILD_TAG.matcher(jarFileName);
        if (build.find()) return "Build " + build.group(1);
        return "unknown";
    }

    /** 命中正则就把 region 记进映射，返回是否命中 */
    private static boolean collect(Pattern pattern, String regionName, Map<String, String> target) {
        Matcher matcher = pattern.matcher(regionName);
        if (!matcher.matches()) return false;
        target.put(matcher.group(1), regionName);
        return true;
    }

    /** 抽出一组图标 region 再按内容名另存，返回实际落盘数量 */
    private static int exportIcons(AtlasDump.AtlasData atlas, Map<String, String> mapping,
                                   Path rawDir, Path targetDir) throws IOException {
        Files.createDirectories(targetDir);
        if (mapping.isEmpty()) return 0;
        AtlasDump.extract(atlas, rawDir, List.copyOf(mapping.values()), true);
        int count = 0;
        for (var entry : mapping.entrySet()) {
            Path source = rawDir.resolve(entry.getValue() + ".png");
            if (!Files.exists(source)) continue;
            Files.copy(source, targetDir.resolve(entry.getKey() + ".png"), StandardCopyOption.REPLACE_EXISTING);
            count++;
        }
        return count;
    }

    private static int countPng(Path dirPath) throws IOException {
        if (!Files.isDirectory(dirPath)) return 0;
        try (var files = Files.list(dirPath)) {
            return (int) files.filter(path -> path.getFileName().toString().endsWith(".png")).count();
        }
    }

    private static void writeMeta(Path metaPath, String version, String jarFileName, int blocks,
                                  int blockIcons, int itemIcons, int liquidIcons, int parts,
                                  int icons) throws IOException {
        StringBuilder sb = new StringBuilder(256);
        sb.append("{\n");
        sb.append("    \"version\": ").append(Boot.q(version)).append(",\n");
        sb.append("    \"jar\": ").append(Boot.q(jarFileName)).append(",\n");
        sb.append("    \"generatedBy\": \"PackBuilder\",\n");
        sb.append("    \"blocks\": ").append(blocks).append(",\n");
        sb.append("    \"blockIcons\": ").append(blockIcons).append(",\n");
        sb.append("    \"itemIcons\": ").append(itemIcons).append(",\n");
        sb.append("    \"liquidIcons\": ").append(liquidIcons).append(",\n");
        sb.append("    \"parts\": ").append(parts).append(",\n");
        sb.append("    \"icons\": ").append(icons).append("\n");
        sb.append("}\n");
        Files.writeString(metaPath, sb.toString(), StandardCharsets.UTF_8);
    }

    private static void deleteRecursively(Path dirPath) throws IOException {
        if (!Files.exists(dirPath)) return;
        try (var paths = Files.walk(dirPath)) {
            for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) {
                Files.deleteIfExists(path);
            }
        }
    }

    private static void deleteQuietly(Path dirPath) {
        if (dirPath == null) return;
        try {
            deleteRecursively(dirPath);
        } catch (IOException ignored) {
            // 临时目录清理失败不影响产物
        }
    }
}
