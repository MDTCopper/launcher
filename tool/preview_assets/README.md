# preview_assets —— 蓝图预览资产包生成工具

从 Mindustry 桌面版 `.jar` 生成 `lib/domain/preview` 渲染器需要的资产包：内容表、绘制规则数据、方块/物品/液体图标、绘制用原始贴图。

全程 **CPU-only**：只读 jar、不启动游戏、不建 GL 上下文、不弹窗口；不依赖 Python / System.Drawing。

## 依赖

| 依赖 | 说明 |
|---|---|
| JDK 17+ | 需要 `java`、`javac` 在 PATH（游戏 jar 的 class 版本是 61 = Java 17，工具用 `javac --release 17` 编译） |
| PowerShell 5.1（Windows PowerShell）或 PowerShell 7 | 脚本不要求 7 的语法，本机已在 5.1 验证 |
| 游戏 jar | 例如 `data/mindustrys/mindustry-v160.7-314baa30.jar`（v7/v8 桌面版，含 `sprites/sprites.aatls`） |

## 快速开始

在仓库根目录执行（Windows PowerShell 5.1 / PowerShell 7 均可）：

```powershell
# 直接调用（当前 shell）
.\tool\preview_assets\build_pack.ps1 `
  -JarPath data\mindustrys\mindustry-v160.7-314baa30.jar `
  -OutDirPath tmp\bp-research\m1\pack-nu `
  -Version v160.7

# 或用 pwsh 起独立进程（PATH 里有 pwsh 时）
pwsh -File tool/preview_assets/build_pack.ps1 `
  -JarPath data/mindustrys/mindustry-v160.7-314baa30.jar `
  -OutDirPath tmp/bp-research/m1/pack-nu `
  -Version v160.7
```

参数：

| 参数 | 必填 | 说明 |
|---|---|---|
| `-JarPath` | 是 | 游戏 jar 路径，相对路径按当前目录解析 |
| `-OutDirPath` | 是 | 产物目录；脚本只清理/覆盖自己管理的文件（`icons/`、`parts/`、5 个 json） |
| `-Version` | 否 | 写进 `meta.json` 的版本标签；缺省从 jar 文件名解析（`mindustry-v160.7-...jar` → `v160.7`；`Build 146` → `Build 146`），否则 `unknown` |
| `-WorkDirPath` | 否 | 中间产物目录（class、json、原始 PNG），缺省为临时目录；指定后可保留用于排查 |

生成一个版本的包约 20~35 秒（其中 JVM 引导 4 次、约 1 秒/次；图集裁切数千张 PNG 占大头）。

## 流程

1. `javac --release 17` 编译 `src/*.java` 到 `<WorkDir>/classes`
2. `AtlasDump index` 解析 jar 内 `sprites/sprites.aatls`，导出全部图集 region 表
3. `ContentDump` 导出 `content.json`（blocks / items / liquids + 连接标记）
4. `BlockDrawDump` / `CanvasDump` / `DrawerDump` 导出绘制规则相关 json
5. `AtlasDump extract`：
   - `parts/`：每个 block 名相关的 region（`<name>`、`<name>-*`、`<name><数字>`）加 12 个共享 region（`center/cross/laser/laser-end/block-1..4/reinforced-block-2..5`）
   - `icons/block`：优先 `block-<name>-full`，没有则 `block-<name>-ui`，存成 `<name>.png`
   - `icons/item`：`item-<name>-ui` → `<name>.png`；`icons/liquid`：`liquid-<name>-ui` → `<name>.png`
   - `icons/generic`：`center`、`cross` 两个标记图
6. 复制 json、写 `meta.json`

## 产物结构

```
<OutDir>/
├── content.json        # 内容表（blocks/items/liquids）
├── classes.json        # 每个方块的 drawPlan* 实现类与继承链（规则分派用）
├── canvas.json         # canvas / large-canvas 的调色板与几何
├── drawer-spec.json    # 每个方块的 drawer 树（drawPlan 组合用）
├── meta.json           # version / jar / 各项计数（blocks 是内容方块总数，图标数见 blockIcons）
├── icons/
│   ├── block/<name>.png
│   ├── item/<name>.png
│   ├── liquid/<name>.png
│   └── generic/{center,cross}.png
└── parts/
    └── <atlas-region-name>.png   # 绘制规则按 region 名直接取图
```

v160.7 的参考计数：`blocks=447`（content 方块总数；meta 的 `blockIcons=411` 才是方块图标文件数）、`items=22`、`liquids=11`、`icons/block=411`、`icons/item=22`、`icons/liquid=11`、`parts=2884`、`classes.json=447 条`、`canvas.json=2 条`、`drawer-spec.json=85 条`。

`meta.json` 字段口径：`blocks` = content 方块总数，`blockIcons` / `itemIcons` / `liquidIcons` = 各类图标文件数，`icons` = 三者之和，`parts` = parts 目录 PNG 数。

## 与 `lib/domain/preview` 的对应关系

| 产物 | 渲染器侧 | 用途 |
|---|---|---|
| `content.json` | `blueprint_asset_pack.dart` → `BlueprintBlockInfo` | `size/type/rotate/rotateDraw/mapColor`、连接标记：`hasItems/hasLiquids/outputsLiquid/acceptsItems/noSideBlend/isDuct/squareSprite`；`items/liquids` 的 `id→name/color` |
| `classes.json` | `plan_draw_rule.dart` | 按 `drawPlanRegion` / `drawPlanConfig` / `drawPlanConfigTop` 的声明类 + `chain` 选择绘制规则 |
| `canvas.json` | `draw_rules/canvas_pixels.dart` | canvas 的 `size/canvasSize/bitsPerPixel/padding/palette` |
| `drawer-spec.json` | `draw_rules/drawer_composition.dart` | 按 drawer 树递归复刻官方 `drawPlan`（含 `outputLiquids` / `liquidOutputDirections`） |
| `icons/block|item|liquid/<name>.png` | `BlueprintAssetPack.blockIconPaths` 等 | 列表/缩略图里的方块与物品液体图标 |
| `icons/generic/{center,cross}.png` | `draw_rules/config_marks.dart`、`plan_draw_rule.dart` | 配置/选中标记 |
| `parts/<region>.png` | `draw_rules/connection_links.dart`、`transport_connectivity.dart`、`drawer_composition.dart` | 绘制规则按 region 名取图：方块本体、`-top/-outline/-arrow/-team`、`conveyor-<mask>-<frame>`、`laser`/`laser-end`、炮台底座 `block-<size>` 等 |
| `meta.json` | `BlueprintAssetPack.versionLabel` | 版本标签（缓存键/调试），不参与绘制 |

## 实现要点 / 已知限制

- **只导出 jar 内的原版内容**：`content.json` 来自 `ContentLoader.createBaseContent()`，不含 mod 内容；引用 mod 方块的蓝图由渲染器走占位逻辑。要让 mod 可渲染需要另外加载 mod 的 `sprites/` 与内容定义（当前工具不做）。
- **只支持二进制图集 `AATLS`**（v7/v8 桌面 jar）。v6 的 `sprites/sprites.atlas` 是文本格式，本工具不解析（`AtlasDump` 会报错退出）。
- **按版本各生成一份**：不同版本的方块名、尺寸、图标、贴图与字段都可能不同；`-Version` 只是标签，真正决定内容的是 `-JarPath`。
- **图标命名依赖图集约定**：`block-<name>-full` / `block-<name>-ui`；某个版本若缺某个方块的图标，该方块就没有 icon 文件（渲染器会回退到 parts 里的本体贴图或占位）。
- **旋转 region 跳过**：`AATLS` 中 `rotate=true` 的 region 不导出（当前 v7/v8 vanilla 图集里 block 相关 region 均为 `rotate=false`）。
- **裁剪用原始像素复制**（`Pixmap.crop`），不做 alpha 合成；历史 research 包用 System.Drawing / `Pixmap.draw` 合成，半透明像素会有 ±1~2 的颜色舍入差，视觉等价，新包更接近图集原图。
- **不导出团队调色板**（`Team.palettei`）：team 层贴图在 `parts/` 里，颜色映射由 Dart 侧规则处理。
- **`squareSprite` 语义**：本工具导出的是 `loadColors()` 之后的真实游戏值（`mapColor.a > 0.5` 时为 true）；历史 research 包因 `merge_flags.py` 用引导前的值而全为 true。渲染器当前不参与绘制分派，仅存档。
- 需要本机有可用的 `java`/`javac`；jar 为 GPLv3，随启动器分发/打包时沿用现有游戏 jar 的分发方式并注意合规。

## 源码

| 文件 | 作用 |
|---|---|
| `src/Boot.java` | CPU-only 内容引导（五步配方，无 GL）与 JSON/颜色小工具 |
| `src/ContentDump.java` | 导出 `content.json` |
| `src/BlockDrawDump.java` | 导出 `classes.json`（drawPlan* 实现归属与继承链） |
| `src/CanvasDump.java` | 导出 `canvas.json` |
| `src/DrawerDump.java` | 导出 `drawer-spec.json`（drawer 树） |
| `src/AtlasDump.java` | 图集 `index` / `extract`（CPU 解析 AATLS、裁切 PNG） |

所有 Java 工具都需要把游戏 jar 放在 classpath 最前面（`Boot.locateJar()` 取第一个 `.jar`）。
