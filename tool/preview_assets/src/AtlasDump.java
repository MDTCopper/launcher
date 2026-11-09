import arc.files.Fi;
import arc.graphics.Pixmap;
import arc.graphics.PixmapIO;
import arc.graphics.g2d.PixmapRegion;
import arc.graphics.g2d.TextureAtlas;
import arc.struct.Seq;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * CPU-only 图集工具：解析游戏 jar 内的 Arc 图集并按 region 名裁切成 PNG（无 GL、无窗口）
 *
 * 桌面 jar 不提供单个贴图文件，sprites 全打包在 sprites/sprites.aatls（二进制，头 AATLS）
 * 和若干页面 PNG 里；老版本（v6）用文本格式 sprites/sprites.atlas
 *
 * usage:
 *   AtlasDump index   &lt;jar&gt; &lt;out.json&gt;
 *       导出图集页面与全部 region 表（name/page/x/y/w/h/ow/oh/rotate/offset）
 *   AtlasDump extract &lt;jar&gt; &lt;outDir&gt; &lt;namesFile&gt; [--exact]
 *       按名单裁切 region 成单个 PNG；默认按"region 名等于前缀、或以 前缀- 开头、
 *       或 前缀+数字"匹配，--exact 只匹配完全相同的名字
 *
 * 坐标约定：AATLS 里 region.top 是图像坐标（左上角），裁剪直接用 (x=left, y=top)
 * （v6 的文本 .atlas 是 libGDX 坐标，左下角，本工具不处理文本格式）
 */
public class AtlasDump {
    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: AtlasDump <index|extract> <jar> <out> [namesFile] [--exact]");
            System.exit(2);
        }
        String mode = args[0];
        File jar = new File(args[1]);
        String out = args[2];
        boolean exact = false;
        for (int i = 3; i < args.length; i++) {
            if ("--exact".equals(args[i])) exact = true;
        }

        Path work = Files.createTempDirectory("mindustry-atlas");
        AtlasData data = loadAtlas(jar, work);

        switch (mode) {
            case "index" -> index(data, Path.of(out));
            case "extract" -> {
                if (args.length < 4) throw new IllegalArgumentException("extract needs <namesFile>");
                extract(data, Path.of(out), Path.of(args[3]), exact);
            }
            default -> throw new IllegalArgumentException("unknown mode " + mode);
        }
    }

    // ---------------------------------------------------------------- 图集加载

    /** 把 jar 内 sprites/* 解到临时目录，再用游戏自己的 TextureAtlasData 解析（纯 CPU 读取） */
    static AtlasData loadAtlas(File jarFile, Path work) throws Exception {
        Path sprites = work.resolve("sprites");
        Files.createDirectories(sprites);
        try (ZipFile zip = new ZipFile(jarFile)) {
            Enumeration<? extends ZipEntry> en = zip.entries();
            while (en.hasMoreElements()) {
                ZipEntry e = en.nextElement();
                String name = e.getName();
                if (!name.startsWith("sprites/") || e.isDirectory()) continue;
                if (!name.endsWith(".png") && !name.endsWith(".atlas") && !name.endsWith(".aatls")) continue;
                Path dst = work.resolve(name);
                Files.createDirectories(dst.getParent());
                try (InputStream is = zip.getInputStream(e)) {
                    Files.copy(is, dst, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
        Path atlasFile = null;
        for (String name : new String[]{"sprites.aatls", "sprites.atlas"}) {
            Path p = sprites.resolve(name);
            if (Files.exists(p)) { atlasFile = p; break; }
        }
        if (atlasFile == null) throw new IOException("no atlas file inside jar");

        long t0 = System.nanoTime();
        TextureAtlas.TextureAtlasData td =
                new TextureAtlas.TextureAtlasData(new Fi(atlasFile.toFile()), new Fi(sprites.toFile()), false);
        Seq<TextureAtlas.TextureAtlasData.Region> regions = td.getRegions();
        Seq<TextureAtlas.TextureAtlasData.AtlasPage> pages = td.getPages();
        System.out.printf("[ATLAS] %s regions=%d pages=%d parse=%.1f ms%n",
                atlasFile.getFileName(), regions.size, pages.size, Boot.ms(t0));
        return new AtlasData(td, pages, regions, sprites);
    }

    static class AtlasData {
        final TextureAtlas.TextureAtlasData td;
        final Seq<TextureAtlas.TextureAtlasData.AtlasPage> pages;
        final Seq<TextureAtlas.TextureAtlasData.Region> regions;
        final Path spritesDir;
        final Map<TextureAtlas.TextureAtlasData.AtlasPage, Pixmap> pagePixmaps = new HashMap<>();

        AtlasData(TextureAtlas.TextureAtlasData td, Seq<TextureAtlas.TextureAtlasData.AtlasPage> pages,
                  Seq<TextureAtlas.TextureAtlasData.Region> regions, Path spritesDir) {
            this.td = td;
            this.pages = pages;
            this.regions = regions;
            this.spritesDir = spritesDir;
        }

        /** 页面 PNG 按需解码并缓存（纯 CPU，Arc 自带 PNG 解码） */
        Pixmap page(TextureAtlas.TextureAtlasData.AtlasPage p) {
            return pagePixmaps.computeIfAbsent(p, pg -> new Pixmap(pg.textureFile));
        }

        PixmapRegion pixmapRegion(TextureAtlas.TextureAtlasData.Region r) {
            return new PixmapRegion(page(r.page), r.left, r.top, r.width, r.height);
        }
    }

    // ---------------------------------------------------------------- index 模式

    static void index(AtlasData d, Path out) throws IOException {
        StringBuilder sb = new StringBuilder(1 << 21);
        sb.append("{\"atlasPages\":[");
        boolean first = true;
        for (var p : d.pages) {
            if (!first) sb.append(",");
            first = false;
            sb.append("{\"file\":").append(Boot.q(p.textureFile.name()))
              .append(",\"w\":").append(p.width).append(",\"h\":").append(p.height).append("}");
        }
        sb.append("],\"regions\":[");
        first = true;
        for (var r : d.regions) {
            if (!first) sb.append(",");
            first = false;
            sb.append("{\"name\":").append(Boot.q(r.name))
              .append(",\"page\":").append(Boot.q(r.page.textureFile.name()))
              .append(",\"x\":").append(r.left).append(",\"y\":").append(r.top)
              .append(",\"w\":").append(r.width).append(",\"h\":").append(r.height)
              .append(",\"ow\":").append(r.originalWidth).append(",\"oh\":").append(r.originalHeight)
              .append(",\"rotate\":").append(r.rotate)
              .append(",\"offX\":").append(r.offsetX).append(",\"offY\":").append(r.offsetY)
              .append("}");
        }
        sb.append("]}");
        if (out.getParent() != null) Files.createDirectories(out.getParent());
        Files.writeString(out, sb.toString(), StandardCharsets.UTF_8);
        System.out.printf("[INDEX] %s bytes=%d regions=%d%n", out.toAbsolutePath(), Files.size(out), d.regions.size);
    }

    // -------------------------------------------------------------- extract 模式

    static void extract(AtlasData d, Path outDir, Path namesFile, boolean exact) throws IOException {
        List<String> names = new ArrayList<>();
        for (String line : Files.readAllLines(namesFile, StandardCharsets.UTF_8)) {
            line = line.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            names.add(line);
        }
        Files.createDirectories(outDir);
        int written = 0, skippedRotate = 0;
        for (var r : d.regions) {
            if (!names.isEmpty() && !matches(r.name, names, exact)) continue;
            if (r.rotate) { skippedRotate++; continue; }
            // crop 是原始像素复制；不要用 draw(PixmapRegion) —— 它对半透明像素会做混合，
            // 导致图标/贴图边缘与原图不一致（block 图标不透明所以看不出来，item 图标就看得出）
            Pixmap p = d.page(r.page).crop(r.left, r.top, r.width, r.height);
            PixmapIO.writePng(new Fi(outDir.resolve(r.name + ".png").toFile()), p);
            p.dispose();
            written++;
        }
        System.out.printf("[EXTRACT] dir=%s written=%d skippedRotate=%d exact=%s%n",
                outDir.toAbsolutePath(), written, skippedRotate, exact);
    }

    static boolean matches(String name, List<String> names, boolean exact) {
        for (String p : names) {
            if (name.equals(p)) return true;
            if (exact) continue;
            if (name.startsWith(p + "-")) return true;
            if (name.length() > p.length() && name.startsWith(p)) {
                String rest = name.substring(p.length());
                if (rest.chars().allMatch(Character::isDigit)) return true;
            }
        }
        return false;
    }
}
