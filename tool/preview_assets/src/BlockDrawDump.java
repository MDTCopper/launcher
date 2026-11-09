import mindustry.Vars;
import mindustry.entities.units.BuildPlan;
import mindustry.world.Block;
import arc.util.Eachable;

import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * CPU-only 导出每个方块的 drawPlan* 方法归属与类继承链
 *
 * 用法：java -cp &lt;jar&gt;;&lt;classes&gt; BlockDrawDump &lt;out.json&gt;
 *
 * 很多方块是匿名子类，getClass().getSimpleName() 为空；用 getClass().getName()
 * 加上 drawPlan* 方法真正的声明类，才能知道蓝图预览时实际跑的是哪份实现
 */
public class BlockDrawDump {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("usage: BlockDrawDump <out.json>");
            System.exit(2);
        }
        double bootstrapMs = Boot.bootstrap(false);
        System.out.printf("[BOOT] %.1f ms%n", bootstrapMs);

        StringBuilder sb = new StringBuilder(1 << 18);
        sb.append("{\"classes\":[\n");
        boolean first = true;
        for (Block b : Vars.content.blocks()) {
            if (!first) sb.append(",\n");
            first = false;
            sb.append("{\"name\":").append(Boot.q(b.name));
            sb.append(",\"class\":").append(Boot.q(b.getClass().getName()));
            sb.append(",\"chain\":[");
            Class<?> c = b.getClass();
            boolean firstChain = true;
            while (c != null && c != Object.class) {
                if (!firstChain) sb.append(",");
                firstChain = false;
                sb.append(Boot.q(c.getName()));
                c = c.getSuperclass();
            }
            sb.append("]");
            sb.append(",\"drawPlanRegion\":").append(declaring(b, "drawPlanRegion"));
            sb.append(",\"drawPlanConfig\":").append(declaring(b, "drawPlanConfig"));
            sb.append(",\"drawPlanConfigTop\":").append(declaring(b, "drawPlanConfigTop"));
            sb.append("}");
        }
        sb.append("\n]}\n");

        Path out = Path.of(args[0]);
        if (out.getParent() != null) Files.createDirectories(out.getParent());
        Files.writeString(out, sb.toString(), StandardCharsets.UTF_8);
        System.out.printf("[OUT] %s bytes=%d%n", out.toAbsolutePath(), Files.size(out));
    }

    private static String declaring(Block block, String method) {
        try {
            Method m = block.getClass().getMethod(method, BuildPlan.class, Eachable.class);
            Class<?> owner = m.getDeclaringClass();
            return Boot.q(owner.getName());
        } catch (NoSuchMethodException e) {
            return "null";
        }
    }
}
