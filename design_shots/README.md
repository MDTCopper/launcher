# 设计样张

渲染出来的对照图，一代一个目录，方便横向翻。**图是生成的，不要手改**；重新出图：

```powershell
$env:NO_PROXY='127.0.0.1,localhost'
$env:SHOT_TAG='05-xxx'   # 这一代叫什么，不给就写 latest
dart 'C:\Software\flutter\bin\cache\flutter_tools.snapshot' test test/design_render_test.dart
```

目录说明（`light.png` / `dark.png` 一对）：

| 目录 | 这一代改了什么 |
|---|---|
| `catalog/01-initial` | 第一版组件目录（默认 8 高的线性条、自定义开关、分段纯色之前的状态） |
| `catalog/02-thick-bars` | 线性条加粗试版：8 / 12 / 16 三档对照，页面里统一按 12 摆 |
| `catalog/03-flat-segment` | 分段选中格取消立体（纯色）＋选中底主题色压低（暗 0.10 / 亮 0.12） |
| `catalog/04-native-switch` | 分段恢复立体渐变；线性条默认 12；开关换 Flutter 原生 `Switch`；新增独立设置 tile（高 48） |
| `catalog/05-switch-outline` | 开关**开态**的描边跟着轨道一起消失（原来一律是灰边）；其余同 04 |
| `catalog/06-slider` | 拖动条加厚（轨道 12、滑块 20）；新增「滑块类型」小节：自绘 / 原生 M3 2024 / 2023 / 带刻度 |
| `catalog/07-copper-colors` | 皮肤改用 Copper **现在的** `AppColors` 拼（`TemplateSkin.fromAppColors`）；`SKIN=hct` 可切回生成式那套 |
| `catalog/08-seeded` | 现配色改成**种子**：只取 `interactive` 的色相 / 色度，其余由 A 路线按对比度重解；拖动条轨道 16、滑块 24 |
| `catalog/09-warm-seed` | 种子色相收到 66~70（08 的 73.6 整页发土黄）——中间尝试，表面仍是暖灰 |
| `catalog/10-grey-surfaces` | 表面改回纯灰（`neutralChroma: 0`），只有铜色来自种子 |
| `catalog/11-true-seed` | 实心照种子自己的明度出（不再为白字压暗），白字不够 4.5 就自动换深色字 |
| `catalog/12-mode-accent` | 过渡版：只为满足「实心与卡面 ≥3」而按模式调整明度（黄青会变） |
| `catalog/13-mode-accent` | 实心按模式分色——亮色统一压暗 6、暗色统一提亮 6，再保证与卡面 3:1，字自动挑 |
| `catalog/14-loose-contrast` | 实心与卡面的最小对比度放宽到 **2**（3 会把亮黄压成琥珀），高亮色保住饱和度 |
| `catalog/15-radix` | 换 **Radix Colors** 的现成 12 档色阶（`SKIN=radix`）：sand 中性 + amber 实心，字色按 11 / 12 档 |
| `catalog/16-warm-bright` | 回到第 6 版算法（暖中性 + 现配色明度），`ambience` 误作用在**表面**上（亮色更亮、暗色更暗）；顺带把演示里堆着的主题色块减掉 |
| `catalog/17-accent-shift` | 偏移只作用于**实心**——亮色加亮 6 档、暗色压暗 6 档；表面回到第 6 版 |
| `catalog/18-switch-mode` | 开关开态轨道按模式取色——亮色更亮、暗色更暗，滑块反色（读数偏「轨道是主题色」） |
| `catalog/19-switch-tinted` | 开关改成**主题色的底**——亮色浅铜底、暗色深铜底，铜色落在滑块上（读数偏「开关本体跟主题明暗」） |
| `catalog/20-user-tune` | 按用户调的种子 #D89148（chroma 41.1、表面色度 2、实心偏移 −5）渲染；实心字色按明暗（亮字 / 暗字）、开关槽=实色圆球亮/暗、滑条换 24 版竖杆、选中底加重到 0.20 / 0.18 |
| `catalog/21-thumb-soft` | 暗色开关圆球不再用页底（太黑），改取凹槽面；滑条竖杆同步 |
| `catalog/22-more-theme` | 再加一点点主题色——选中底 0.26 / 0.23、表面色度 2.6；调定版固化成 `TemplateSkin.tuned`（种子 #D89148） |
| `catalog/23-switch-icons` | 开关圆球里加图标：开 = 勾（铜色）、关 = 叉（取反差色） |
| `catalog/24-glyph-morph` | 开关换**自绘**（原生 `thumbIcon` 只收 `Icon`）——勾/叉自绘加粗到 15px、切换时端点插值形变 220ms；禁用态回到凹槽面 |
| `catalog/25-switch-edge` | 自研开关把边缘加厚到 **2px**（原生 1px），开态随描边一起淡出 |
| `catalog/26-switch-stretch` | **当前**：暗色圆球掺主题色（38%）；开关加「球被拉伸」、横向拖动、松手弹簧回弹（22% 视觉见 `candidates/switch/states.png`） |
| `candidates/accent` | 主体色亮度候选（现状 / 更亮四档） |
| `candidates/disabled` | 禁用态候选（实心透明度 / 标准明度三版） |
| `candidates/seed` | 种子配色：色相 / 色度四组对照（`compare.png`）、调试页样张（`seed_lab.png`）、六种种子 → 实心输出（`seed_output.png`）、实心与卡面最小对比度 3 / 2.5 / 2 / 1.6 对照（`accent_contrast.png`）、实心偏移 −6 / 0 / +6 对照（`accent_shift.png`） |
| `candidates/radix` | Radix 强调色候选：amber / yellow / bronze / gold × 亮暗（`accents.png`） |

更早的两代（禁用态整层、按钮面几轮）只在 `tmp/design_shots/` 里出现过，没搬进来。

## 口径现状（2026-11-03）

- 只有实心按钮带主题色；标准 = 控件面，安静 = 无面，破坏 = 无面 + 危险字
- 禁用：实心留 12% 主题色、标准比控件面暗一档，其余只有 38% 的字
- 分段选中格：上亮下暗的轻渐变（保留立体感）
- 线性条：默认高 12，位置可各自覆盖
- 开关：原生 `Switch`；独立设置 tile 高 48（= 原生开关默认点按高度）
