import arc.files.Fi;
import arc.graphics.Pixmap;
import arc.graphics.PixmapIO;
import mindustry.io.MapIO;
import mindustry.maps.Map;

import java.nio.file.Files;
import java.nio.file.Path;

/**
 * 把 .msav 地图导出成预览 PNG（纯 CPU，无 GL、无窗口）
 *
 * 用法：java -cp &lt;游戏 jar&gt;;&lt;工具 jar&gt; MapPreviewExport &lt;msav&gt; &lt;outPng&gt;
 *
 * 与游戏自己的 Maps.createNewPreview 等价，但绕开它后面的 Texture 上传：
 * MapIO.createMap 只读元数据 → Boot 五步引导 → MapIO.generatePreview 返回 Pixmap →
 * PixmapIO.writePng 落盘；生成结果与游戏 previews/&lt;名&gt;_v2.png 逐字节一致（研究实测）
 */
public class MapPreviewExport {
    public static void main(String[] args) {
        if (args.length < 2) {
            System.err.println("usage: MapPreviewExport <msav> <outPng>");
            System.exit(2);
        }
        long start = System.nanoTime();
        try {
            Path msavPath = Path.of(args[0]).toAbsolutePath().normalize();
            if (!Files.isRegularFile(msavPath)) throw new IllegalArgumentException("map not found: " + msavPath);
            Path outPath = Path.of(args[1]).toAbsolutePath().normalize();

            Map map = MapIO.createMap(new Fi(msavPath.toFile()), true);
            System.out.printf("[MapPreviewExport] map=%dx%d version=%d%n", map.width, map.height, map.version);

            double bootstrapMs = Boot.bootstrap(true);
            System.out.printf("[BOOT] %.1f ms%n", bootstrapMs);

            long renderStart = System.nanoTime();
            Pixmap pixmap = MapIO.generatePreview(map);
            System.out.printf("[MapPreviewExport] preview %dx%d (%.1f ms)%n",
                    pixmap.width, pixmap.height, Boot.ms(renderStart));

            if (outPath.getParent() != null) Files.createDirectories(outPath.getParent());
            Fi out = new Fi(outPath.toFile());
            PixmapIO.writePng(out, pixmap);
            pixmap.dispose();
            System.out.printf("[MapPreviewExport] done size=%d bytes in %.1f ms -> %s%n",
                    Files.size(outPath), Boot.ms(start), outPath);
        } catch (Throwable error) {
            System.err.println("[MapPreviewExport] failed: " + error);
            error.printStackTrace();
            System.exit(1);
        }
    }
}
