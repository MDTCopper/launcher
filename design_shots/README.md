# 设计样张

渲染出来的对照图，一代一个目录，方便横向翻。**图是生成的，不要手改**；重新出图：

> **标准设计尺寸：`760 × 450`**（桌面端最小窗口，≈ 手机横屏量级）。这个尺寸是**正常态**，
> 不触发窄屏排布；比它窄（如抽屉 360）走窄屏、比 1100 宽走宽屏。断点统一取 `TemplateBreakpoints`；
> 样张脚本默认就按 760 宽出图，宽屏 / 竖屏用 `WIDTH` / `PAGE_HEIGHT` 覆盖。

```powershell
$env:NO_PROXY='127.0.0.1,localhost'
$env:SHOT_TAG='05-xxx'   # 这一代叫什么，不给就写 latest
dart 'C:\Software\flutter\bin\cache\flutter_tools.snapshot' test test/design_render_test.dart
```

**整页复刻**另有入口（逻辑 1000×700、输出 2x，`design_shots/page/`）：

```powershell
$env:SHOT_TAG='page-01-version-setting'
dart 'C:\Software\flutter\bin\cache\flutter_tools.snapshot' test test/design_page_shot_test.dart
# 可选：PAGE=version|cloud|mod 换页面；PAGE_HEIGHT 拉高看折叠线以下
```

**App 内设计层页面**（`design_shots/screen/`，`SCREEN=catalog|mod|modview|drawer`，`TAB=1|2` 切标签页，
`WIDTH` / `PAGE_HEIGHT` 改画布尺寸——竖屏与抽屉宽度就靠它们）：

```powershell
$env:SHOT_TAG='screen-mod'; $env:SCREEN='mod'; $env:WIDTH='1000'; $env:PAGE_HEIGHT='700'
dart 'C:\Software\flutter\bin\cache\flutter_tools.snapshot' test test/design_lab_screens_shot_test.dart
```

> 这两页已经在 App 里：debug 构建下左侧栏「发现」会多出 **模组下载（新）** 和 **组件目录** 两项，
> 对应路由 `/template_mod_download`、`/template_catalog`。

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
| `catalog/26-switch-stretch` | 暗色圆球掺主题色（38%）；开关加「球被拉伸」、横向拖动、松手弹簧回弹（四态见 `candidates/switch/states.png`） |
| `catalog/27-taller-handle` | 滑条竖杆 18 → **24**（比轨道高一截） |
| `catalog/28-batch1-chrome` | 批 1a——页面骨架（顶栏+滚动+回顶）、对话框壳、Toast 堆叠、空/错/载三态、图标按钮、tooltip、复选（含三态）、徽标；只加设计层，不动现有 UI |
| `catalog/29-danger-flag` | `danger` 从第四档面改成**标识**（面还是实心/标准/安静，只变红）；对话框里「取消 / 删除」同面不同色 |
| `catalog/30-compact-bar` | 顶栏改成 **40 高单行面包屑**（越靠右越当前、可点可跳），不再堆面包屑/标题/副标题三层 |
| `catalog/31-rail-placement` | 加 `TemplateSideRail`（折叠/导航/账户/任务四个槽位），并出「账户与任务放哪」三种摆法对照 |
| `catalog/32-chrome-final` | 外壳定稿——左上角「返回键 / 账户头像」先按共用位置理解；任务右上（左右抽屉）、折叠按钮挪到侧栏底部；侧栏收起成 24 宽窄条 |
| `catalog/33-logo-slot` | 澄清——侧栏顶部是**软件 logo**，返回键与 logo 共用那个位置；顶栏左侧只留账户 |
| `catalog/34-menus-cards` | 批 1b——右键菜单（复选/危险项/快捷键）、真下拉、提示条四语气（可关闭/行内动作）、列表卡与网格卡 |
| `catalog/35-rail-labels` | 侧栏展开是「图标 + 名称」长条（180 宽）、折叠只剩图标（56 宽）；页面左侧加圆角 |
| `catalog/36-corner-fix` | 圆角改到**内容区**（顶栏保持直角横贯、侧栏是包边），内容区在两者交界处倒角 |
| `catalog/37-no-divider` | 试**去掉边界线**——顶栏下边框、侧栏右分隔线关掉，只靠底色 + 圆角分隔 |
| `catalog/38-corner-stroke` | 试**圆角描边**：内容区 1px 边线跟着圆角走（顶栏/侧栏仍不画线） |
| `catalog/39-edge-left-top` | 内容区只圆**左上**（左下改直角）；描边只画**左 + 上**两条边 |
| `catalog/40-brand-rail` | 仿现有导航栏——侧栏顶部 logo + 「Copper」文字、返回键带「返回」字（收纳按钮曾试放顶栏） |
| `catalog/41-rail-bottom` | 收纳按钮回到侧栏底部（展开带「收纳菜单」文字、收起只剩图标）；移除版本号；顶栏左侧只留账户 |
| `catalog/42-route-stack` | 顶栏**路由线路**——整条栈（名称 + tag）、可点跳级、页面内路由用框包起来、页面内路由后还能再接外部路由 |
| `catalog/43-window-controls` | **当前**：窗控三键（最小化 / 最大化 / 关闭，关闭悬停变红底）；组件目录里与图标按钮、复选并排 |
| `shell/shell-08-route-stack` | 外壳实拍：路由线路（`主页 › 版本选择 › 版本设置 build 146 › [设置]`） |
| `shell/shell-09-window` | **当前外壳**：顶栏右侧三枚窗控；路由线路超长时靠右显示、左缘渐隐 |
| `shell/shell-04-brand` | 外壳特写：展开态（早期，收纳按钮在顶栏） |
| `shell/shell-05-collapsed` | 外壳特写：收起态（侧栏 56 宽只剩 logo，收纳按钮转向） |
| `shell/shell-01-border` | 外壳特写（1280×800）：内容区左上/左下都圆 + 四条边描边（已被 39 取代） |
| `shell/shell-02-plain` | 同外壳特写，内容区**不描边**（只靠底色差 + 圆角） |
| `shell/shell-03-stroke` | 左下直角 + 只画左/上边描边（收纳按钮在顶栏、有版本号） |
| `shell/shell-06-rail-bottom` | **当前外壳**：展开态——侧栏 logo + Copper、底部「« 收纳菜单」，顶栏只有账户 |
| `shell/shell-07-rail-bottom-collapsed` | **当前外壳**：收起态——侧栏 56 宽只剩 logo，底部只剩「»」图标 |
| `page/page-01-version-setting` | 第一张整页复刻：版本设置·启动（初版） |
| `page/page-02-memory-block` | 内存分配改竖排块（标题 / 解释 / 选项），游戏Java 下拉右对齐 |
| `page/page-03-aligned` | 行内边距统一（12），其余行与开关行左右边缘对齐 |
| `page/page-03-tall` | 同上的长图（1180 高），用来检查折线以下的高级选项与危险区 |
| `page/page-04-version-card` | **版本头也做成卡片**（与下面几段卡一致） |
| `page/page-05-version-card` | 同上，版本头改用通用 `TemplateCard` 组件 |
| `page/page-06-cloud` | 云存档总览复刻（初版） |
| `page/page-07-cloud` | 云存档总览：卡内段落 / 按钮 / 提示条内边距统一成 12 |
| `page/page-08-mod-download` | 模组下载复刻（按原页面结构） |
| `page/page-09-mod-redesign` | 模组下载**重构版**：单主行动 + 表格式版本列表 + 底部限流提示 |
| `catalog/44-tabs` | 组件目录新增「标签页（下划线式）」；目录本身挪进 `lib/`，App 内可打开 |
| `catalog/45-drawer-dropdowns` | 新增任务卡 / 日志卡（右侧抽屉）、多选下拉、可交互右键菜单区；进度条加不确定态 |
| `catalog/46-project-menu` | 任务卡改按 `LaunchMindustryTask` 形制（大标题 + 状态行 + 细进度 + 等宽按钮）；右键菜单改用**当前项目的 `ContextMenu`** |
| `catalog/47-task-card-v2` | 任务卡第二版——图标块 + 标题/状态徽标 + 右侧时间、进度条带百分比、说明/体积分栏、操作收在右下 |
| `catalog/48-page-parts` | 补分页器、折叠面板、图片位 / 头像（有图用图、没图退回图标或首字） |
| `catalog/49-note-colors` | 第四个语义色「提示 note」蓝调（徽标 / 提示条）；任务卡状态挪到时间下面、窄屏按钮通栏 |
| `catalog/50-form-status` | 输入族（多行 / 错误态 / 字数 / 密码显隐 / 后缀）、滑条刻度与量程、进度双段、状态点 / 数字徽章 / 胶囊标签 |
| `catalog/51-base-size` | 组件目录改按标准设计宽度 **760** 出图（原先 900）；顺带把放不下的两排改成 `Wrap` |
| `catalog/52-keys-color-drop` | 键帽 / 组合键与键位捕获、颜色选择（SV 面板 + 色相条 + 16 色点）、拖放区与窗口级拖放遮罩 |
| `catalog/53-table-segments` | 表格组件（表头 + 固定列 + 弹性列 + 行分隔 + 横向滚动）、分段带图标与多选分段 |
| `catalog/54-markdown` | 轻量 Markdown 渲染（标题 / 段落 / 列表 / 引用 / 代码块 / 分隔线 / 徽章 / 链接），模组页 Readme 已改用它 |
| `catalog/55-readme-project` | Readme 改用**项目现有的 `ReadmeView`**（markdown AST + 直写 HTML + 图片 / 链接解析），只把皮肤翻成它要的 `AppColors` / `ThemeData` |
| `screen/screen-mod-view` | **当前**：模组浏览页（`/template_mod_view`，760 基准宽）：标题卡 + 搜索筛选 + 列表/网格切换 + 翻页 |
| `screen/screen-mod-view-narrow` | 同一页窄屏（600 宽）：筛选换行、列表改成堆叠行 |
| `screen/screen-mod` | **App 内页面**：模组下载新页（宽屏版，1000×700） |
| `screen/screen-mod-base` | 同一页按**标准尺寸 760×450**（最小窗口首屏） |
| `screen/screen-mod-base-tall` | 同上拉高到 900 看折线以下 |
| `screen/screen-mod-portrait` | 同一页 **竖屏 / 窄窗版**（720×1180）：头卡堆叠、表头隐藏、逐行折叠、翻页竖排 |
| `screen/screen-mod-readme` | 同上切到 Readme 标签页 |
| `screen/screen-drawer-narrow` | 抽屉宽度（360）下的任务卡 / 日志卡：状态在时间下面、操作按钮单独通栏 |
| `screen/screen-catalog` | **App 内页面**：组件目录（`/template_catalog`，1000 宽） |
| `screen/screen-catalog-base` | 同一页按标准宽度 760（检查组件在最小窗口下的折行） |
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
