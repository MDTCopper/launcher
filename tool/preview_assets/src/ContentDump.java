import mindustry.Vars;
import mindustry.type.Item;
import mindustry.type.Liquid;
import mindustry.world.Block;
import mindustry.world.blocks.environment.Floor;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * CPU-only 内容表导出（无 GL、无窗口）
 *
 * 用法：java -cp &lt;jar&gt;;&lt;classes&gt; ContentDump &lt;out.json&gt;
 *
 * 导出全部原版方块（含地板/覆盖层）、物品、液体，字段覆盖预览渲染器需要的：
 * name/size/type/category/mapColor、旋转与连接标记（outputsLiquid/noSideBlend/isDuct/acceptsItems）、
 * 血量与仓储、建造信息、requires 等
 *
 * 引导步骤见 Boot.bootstrap（五步 CPU 配方），不依赖 Texture / Core.atlas / GL
 */
public class ContentDump {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("usage: ContentDump <out.json>");
            System.exit(2);
        }
        long t0 = System.nanoTime();
        double bootstrapMs = Boot.bootstrap(true);
        System.out.printf("[BOOT] %.1f ms blocks=%d floors=%d items=%d liquids=%d units=%d%n",
                bootstrapMs, Vars.content.blocks().size, countFloors(), Vars.content.items().size,
                Vars.content.liquids().size, Vars.content.units().size);

        StringBuilder sb = new StringBuilder(1 << 20);
        sb.append("{\n");
        sb.append("  \"generatedBy\": \"tool/preview_assets/src/ContentDump.java\",\n");
        sb.append("  \"jar\": ").append(Boot.q(Boot.locateJar().getName())).append(",\n");
        sb.append("  \"bootstrapMs\": ").append(String.format("%.1f", bootstrapMs)).append(",\n");
        sb.append("  \"counts\": {\"blocks\": ").append(Vars.content.blocks().size)
          .append(", \"floors\": ").append(countFloors())
          .append(", \"items\": ").append(Vars.content.items().size)
          .append(", \"liquids\": ").append(Vars.content.liquids().size)
          .append(", \"units\": ").append(Vars.content.units().size).append("},\n");

        // ---------------- 方块 ----------------
        sb.append("  \"blocks\": [\n");
        boolean first = true;
        for (Block b : Vars.content.blocks()) {
            if (!first) sb.append(",\n");
            first = false;
            sb.append("    {");
            sb.append("\"name\":").append(Boot.q(b.name));
            sb.append(",\"id\":").append(b.id);
            sb.append(",\"size\":").append(b.size);
            sb.append(",\"category\":").append(Boot.q(b.category == null ? null : b.category.name()));
            sb.append(",\"type\":").append(Boot.q(b.getClass().getSimpleName()));
            sb.append(",\"isFloor\":").append(b.isFloor());
            sb.append(",\"isOverlay\":").append(b.isOverlay());
            sb.append(",\"isAir\":").append(b.isAir());
            sb.append(",\"isMultiblock\":").append(b.isMultiblock());
            sb.append(",\"synthetic\":").append(b.synthetic());
            sb.append(",\"mapColor\":").append(Boot.rgb(b.mapColor));
            sb.append(",\"mapColorAlphaOpaque\":").append(b.hasColor);
            sb.append(",\"squareSprite\":").append(b.squareSprite);
            sb.append(",\"rotate\":").append(b.rotate);
            sb.append(",\"rotateDraw\":").append(b.rotateDraw);
            sb.append(",\"variants\":").append(b.variants);
            sb.append(",\"drawArrow\":").append(b.drawArrow);
            sb.append(",\"drawTeamOverlay\":").append(b.drawTeamOverlay);
            sb.append(",\"buildVisibility\":").append(Boot.q(b.buildVisibility == null ? null : b.buildVisibility.toString()));
            sb.append(",\"health\":").append(b.health);
            sb.append(",\"itemCapacity\":").append(b.itemCapacity);
            sb.append(",\"liquidCapacity\":").append(b.liquidCapacity);
            sb.append(",\"hasItems\":").append(b.hasItems);
            sb.append(",\"hasLiquids\":").append(b.hasLiquids);
            // 以下四个是预览绘制规则要用的连接标记（旧流程由 merge_flags.py 合并，现直接导出）
            sb.append(",\"outputsLiquid\":").append(b.outputsLiquid);
            sb.append(",\"noSideBlend\":").append(b.noSideBlend);
            sb.append(",\"isDuct\":").append(b.isDuct);
            sb.append(",\"acceptsItems\":").append(b.acceptsItems);
            sb.append(",\"hasPower\":").append(b.hasPower);
            sb.append(",\"consumesPower\":").append(b.consumesPower);
            sb.append(",\"outputsPower\":").append(b.outputsPower);
            sb.append(",\"buildTime\":").append(b.buildTime);
            sb.append(",\"buildCostMultiplier\":").append(b.buildCostMultiplier);
            sb.append(",\"cacheLayer\":").append(Boot.q(b.cacheLayer == null ? null : b.cacheLayer.toString()));
            sb.append(",\"group\":").append(Boot.q(b.group == null ? null : b.group.name()));
            sb.append(",\"offset\":").append(b.offset);
            sb.append(",\"clipSize\":").append(b.clipSize);
            sb.append(",\"lightRadius\":").append(b.lightRadius);
            sb.append(",\"fogRadius\":").append(b.fogRadius);
            sb.append(",\"solid\":").append(b.solid);
            sb.append(",\"underBullets\":").append(b.underBullets);
            sb.append(",\"teamPassable\":").append(b.teamPassable);
            sb.append(",\"placeableLiquid\":").append(b.placeableLiquid);
            sb.append(",\"allowDiagonal\":").append(b.allowDiagonal);
            sb.append(",\"inEditor\":").append(b.inEditor);
            sb.append(",\"update\":").append(b.update);
            sb.append(",\"destructible\":").append(b.destructible);
            sb.append(",\"breakable\":").append(b.breakable);
            sb.append(",\"rebuildable\":").append(b.rebuildable);
            sb.append(",\"configurable\":").append(b.configurable);
            sb.append(",\"saveConfig\":").append(b.saveConfig);
            sb.append(",\"copyConfig\":").append(b.copyConfig);
            sb.append(",\"unloadable\":").append(b.unloadable);
            sb.append(",\"hasShadow\":").append(b.hasShadow);
            sb.append(",\"customShadow\":").append(b.customShadow);
            sb.append(",\"outlineIcon\":").append(b.outlineIcon);
            sb.append(",\"lightColor\":").append(Boot.rgb(b.lightColor));
            sb.append(",\"requirements\":[");
            if (b.requirements != null) {
                for (int i = 0; i < b.requirements.length; i++) {
                    if (i > 0) sb.append(",");
                    sb.append("[").append(Boot.q(b.requirements[i].item.name)).append(",")
                      .append(b.requirements[i].amount).append("]");
                }
            }
            sb.append("]}");
        }
        sb.append("\n  ],\n");

        // ---------------- 物品 ----------------
        sb.append("  \"items\": [\n");
        first = true;
        for (Item it : Vars.content.items()) {
            if (!first) sb.append(",\n");
            first = false;
            sb.append("    {\"name\":").append(Boot.q(it.name))
              .append(",\"id\":").append(it.id)
              .append(",\"color\":").append(Boot.rgb(it.color))
              .append(",\"explosiveness\":").append(it.explosiveness)
              .append(",\"flammability\":").append(it.flammability)
              .append(",\"radioactivity\":").append(it.radioactivity)
              .append(",\"hardness\":").append(it.hardness)
              .append(",\"cost\":").append(it.cost)
              .append(",\"charge\":").append(it.charge)
              .append("}");
        }
        sb.append("\n  ],\n");

        // ---------------- 液体 ----------------
        sb.append("  \"liquids\": [\n");
        first = true;
        for (Liquid l : Vars.content.liquids()) {
            if (!first) sb.append(",\n");
            first = false;
            sb.append("    {\"name\":").append(Boot.q(l.name))
              .append(",\"id\":").append(l.id)
              .append(",\"color\":").append(Boot.rgb(l.color))
              .append(",\"gas\":").append(l.gas)
              .append(",\"flammability\":").append(l.flammability)
              .append(",\"explosiveness\":").append(l.explosiveness)
              .append(",\"temperature\":").append(l.temperature)
              .append(",\"heatCapacity\":").append(l.heatCapacity)
              .append(",\"viscosity\":").append(l.viscosity)
              .append(",\"coolant\":").append(l.coolant)
              .append(",\"hidden\":").append(l.hidden)
              .append("}");
        }
        sb.append("\n  ]\n}\n");

        Path out = Path.of(args[0]);
        if (out.getParent() != null) Files.createDirectories(out.getParent());
        Files.writeString(out, sb.toString(), StandardCharsets.UTF_8);
        System.out.printf("[OUT] %s bytes=%d wall=%.1f ms%n", out.toAbsolutePath(),
                Files.size(out), Boot.ms(t0));
    }

    private static int countFloors() {
        int n = 0;
        for (Block b : Vars.content.blocks()) if (b instanceof Floor) n++;
        return n;
    }
}
