import mindustry.Vars;
import mindustry.world.Block;
import mindustry.world.blocks.logic.CanvasBlock;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * CPU-only 导出 canvas / large-canvas 的调色板与几何参数
 *
 * 用法：java -cp &lt;jar&gt;;&lt;classes&gt; CanvasDump &lt;out.json&gt;
 *
 * canvas 方块存 8 色调色板，并按 config 里的 byte[] 在预览中画 12x12 索引像素图
 */
public class CanvasDump {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("usage: CanvasDump <out.json>");
            System.exit(2);
        }
        Boot.bootstrap(false);
        StringBuilder sb = new StringBuilder(1 << 12);
        sb.append("{\"canvases\":[");
        boolean first = true;
        for (Block block : Vars.content.blocks()) {
            if (!(block instanceof CanvasBlock canvas)) continue;
            if (!first) sb.append(",");
            first = false;
            sb.append("{\"name\":").append(Boot.q(canvas.name));
            sb.append(",\"size\":").append(canvas.size);
            sb.append(",\"canvasSize\":").append(canvas.canvasSize);
            sb.append(",\"bitsPerPixel\":").append(canvas.bitsPerPixel);
            sb.append(",\"padding\":").append(canvas.padding);
            sb.append(",\"palette\":[");
            for (int i = 0; i < canvas.palette.length; i++) {
                if (i > 0) sb.append(",");
                sb.append(canvas.palette[i]);
            }
            sb.append("]}");
        }
        sb.append("]}\n");
        Path out = Path.of(args[0]);
        if (out.getParent() != null) Files.createDirectories(out.getParent());
        Files.writeString(out, sb.toString(), StandardCharsets.UTF_8);
        System.out.printf("[OUT] %s bytes=%d%n", out.toAbsolutePath(), Files.size(out));
    }
}
