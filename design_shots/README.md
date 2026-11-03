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
| `candidates/accent` | 主体色亮度候选（现状 / 更亮四档） |
| `candidates/disabled` | 禁用态候选（实心透明度 / 标准明度三版） |

更早的两代（禁用态整层、按钮面几轮）只在 `tmp/design_shots/` 里出现过，没搬进来。

## 口径现状（2026-11-03）

- 只有实心按钮带主题色；标准 = 控件面，安静 = 无面，破坏 = 无面 + 危险字
- 禁用：实心留 12% 主题色、标准比控件面暗一档，其余只有 38% 的字
- 分段选中格：上亮下暗的轻渐变（保留立体感）
- 线性条：默认高 12，位置可各自覆盖
- 开关：原生 `Switch`；独立设置 tile 高 48（= 原生开关默认点按高度）
