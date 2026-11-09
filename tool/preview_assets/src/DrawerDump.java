import arc.graphics.Color;
import arc.struct.Seq;
import mindustry.Vars;
import mindustry.world.Block;
import mindustry.world.draw.DrawBlock;
import mindustry.world.draw.DrawBlockParts;
import mindustry.world.draw.DrawTurret;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

/**
 * CPU-only 导出每个方块的 drawer 树（蓝图预览里真正负责绘制的那套对象）
 *
 * 用法：java -cp &lt;jar&gt;;&lt;classes&gt; DrawerDump &lt;out.json&gt;
 *
 * 官方链路：Block.drawPlanRegion → drawer.drawPlan(block, plan, eachable)（交给 drawer 的方块）
 * 只导出影响 drawPlan 的字段：字符串、数值、布尔、颜色、子 drawer；
 * TextureRegion 类字段在 Dart 侧按图集 region 名解析（见 drawer 组合规则）
 */
public class DrawerDump {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("usage: DrawerDump <out.json>");
            System.exit(2);
        }
        double bootstrapMs = Boot.bootstrap(false);
        System.out.printf(Locale.ROOT, "[BOOT] %.1f ms%n", bootstrapMs);

        StringBuilder sb = new StringBuilder(1 << 20);
        sb.append("{\"blocks\":[\n");
        boolean first = true;
        int count = 0;
        for (Block b : Vars.content.blocks()) {
            Object drawer = findDrawer(b);
            if (drawer == null) continue;
            if (!first) sb.append(",\n");
            first = false;
            count++;
            sb.append("{\"name\":").append(Boot.q(b.name));
            sb.append(",\"drawer\":");
            dumpDrawer(sb, drawer);
            // DrawLiquidOutputs 需要 crafter 的液体输出与方向
            Field liquids = findField(b.getClass(), "outputLiquids");
            Field dirs = findField(b.getClass(), "liquidOutputDirections");
            if (liquids != null) {
                liquids.setAccessible(true);
                Object value = liquids.get(b);
                sb.append(",\"outputLiquids\":");
                if (value == null) {
                    sb.append("null");
                } else {
                    Object[] arr = (Object[]) value;
                    sb.append("[");
                    for (int i = 0; i < arr.length; i++) {
                        if (i > 0) sb.append(",");
                        Field liquidField = arr[i].getClass().getField("liquid");
                        Object liquid = liquidField.get(arr[i]);
                        sb.append(Boot.q((String) liquid.getClass().getField("name").get(liquid)));
                    }
                    sb.append("]");
                }
            }
            if (dirs != null) {
                dirs.setAccessible(true);
                int[] value = (int[]) dirs.get(b);
                sb.append(",\"liquidOutputDirections\":");
                if (value == null) {
                    sb.append("null");
                } else {
                    sb.append("[");
                    for (int i = 0; i < value.length; i++) {
                        if (i > 0) sb.append(",");
                        sb.append(value[i]);
                    }
                    sb.append("]");
                }
            }
            sb.append("}");
        }
        sb.append("\n]}\n");

        Path out = Path.of(args[0]);
        if (out.getParent() != null) Files.createDirectories(out.getParent());
        Files.writeString(out, sb.toString(), StandardCharsets.UTF_8);
        System.out.printf(Locale.ROOT, "[OUT] %s blocks=%d bytes=%d%n", out.toAbsolutePath(), count, Files.size(out));
    }

    private static Object findDrawer(Block block) throws Exception {
        Field field = findField(block.getClass(), "drawer");
        if (field == null) return null;
        field.setAccessible(true);
        return field.get(block);
    }

    private static Field findField(Class<?> type, String name) {
        for (Class<?> c = type; c != null && c != Object.class; c = c.getSuperclass()) {
            try {
                return c.getDeclaredField(name);
            } catch (NoSuchFieldException ignored) {
                // 继续往父类找
            }
        }
        return null;
    }

    private static void dumpDrawer(StringBuilder sb, Object drawer) throws Exception {
        Class<?> type = drawer.getClass();
        sb.append("{\"class\":").append(Boot.q(resolvedName(type)));
        sb.append(",\"chain\":[");
        boolean firstChain = true;
        for (Class<?> c = type; c != null && c != Object.class; c = c.getSuperclass()) {
            if (!firstChain) sb.append(",");
            firstChain = false;
            sb.append(Boot.q(c.getSimpleName()));
        }
        sb.append("]");
        for (Class<?> c = type; c != null && c != DrawBlock.class && c != Object.class; c = c.getSuperclass()) {
            for (Field field : c.getDeclaredFields()) {
                if (Modifier.isStatic(field.getModifiers())) continue;
                if (!Modifier.isPublic(field.getModifiers())) field.setAccessible(true);
                String name = field.getName();
                Class<?> ft = field.getType();
                Object value = field.get(drawer);
                if (ft == String.class) {
                    appendKey(sb, name);
                    sb.append(Boot.q((String) value));
                } else if (ft == int.class || ft == long.class) {
                    appendKey(sb, name);
                    sb.append(value);
                } else if (ft == float.class || ft == double.class) {
                    appendKey(sb, name);
                    sb.append(((Number) value).doubleValue());
                } else if (ft == boolean.class) {
                    appendKey(sb, name);
                    sb.append(value);
                } else if (ft == Color.class) {
                    appendKey(sb, name);
                    sb.append(Boot.hex((Color) value));
                } else if (DrawBlock.class.isAssignableFrom(ft)) {
                    appendKey(sb, name);
                    if (value == null) sb.append("null");
                    else dumpDrawer(sb, value);
                } else if (ft.isArray() && DrawBlock.class.isAssignableFrom(ft.getComponentType())) {
                    appendKey(sb, name);
                    Object[] children = (Object[]) value;
                    sb.append("[");
                    if (children != null) {
                        for (int i = 0; i < children.length; i++) {
                            if (i > 0) sb.append(",");
                            if (children[i] == null) sb.append("null");
                            else dumpDrawer(sb, children[i]);
                        }
                    }
                    sb.append("]");
                } else if (Seq.class.isAssignableFrom(ft)) {
                    // parts 等序列不参与 drawPlan，只留数量
                    appendKey(sb, name);
                    sb.append("{\"count\":").append(value == null ? 0 : ((Seq<?>) value).size).append("}");
                } else if (ft.isArray()) {
                    appendKey(sb, name);
                    Object array = value;
                    sb.append("{\"count\":").append(array == null ? 0 : java.lang.reflect.Array.getLength(array)).append("}");
                }
                // TextureRegion 等运行时字段留到 Dart 侧按 region 名解析
            }
        }
        if (drawer instanceof DrawTurret) {
            appendKey(sb, "isTurretDrawer");
            sb.append("true");
        }
        if (drawer instanceof DrawBlockParts) {
            appendKey(sb, "isBlockPartsDrawer");
            sb.append("true");
        }
        sb.append("}");
    }

    /** 匿名 drawer 子类的 simpleName 为空，向上找到第一个有名字的父类 */
    private static String resolvedName(Class<?> type) {
        for (Class<?> c = type; c != null && c != Object.class; c = c.getSuperclass()) {
            String simple = c.getSimpleName();
            if (!simple.isEmpty()) return simple;
        }
        return type.getName();
    }

    private static void appendKey(StringBuilder sb, String name) {
        sb.append(",\"").append(name).append("\":");
    }
}
