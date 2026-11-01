# 启动速度重测：游戏窗口出现前的准备阶段

任务 task-9（revision 2，in_progress）。口径改为用户口径：**从启动器进程创建 → Mindustry 游戏窗口真正出现（可见顶层窗口）**，不是游戏加载到可交互。
只改了 `tool/launch_speed_probe.ps1`，未改运行期代码，未 commit。

## 1. 结论速览

| 口径 | Debug | Release |
|---|---|---|
| **进程启动 → 游戏窗口出现（用户口径）** | **1942 ms**（中位 1951，n=3） | **1779 ms**（中位 1768，n=6；前 3 次均值 1817） |
| 其中：启动器侧准备（进程启动 → java 进程创建） | 1608 ms | 1372 ms |
| 　├ 引擎/进程创建（Windows 进程创建 + Flutter 引擎，Dart main 之前） | 1298 ms | 1303 ms |
| 　└ Dart 时间线（main → java 进程创建） | 310 ms | 69 ms |
| 其中：游戏侧（java 进程创建 → 窗口出现，JVM + SDL/GL 建窗） | 334 ms | 407 ms |
| 旧口径：进程启动 → 游戏可交互 | 5708 ms | 6668 ms（受系统负载影响大，仅供参考） |

**一句话**：窗口出现前，启动器侧 ~1.37 s 里 **约 1.2–1.3 s 是 Flutter 引擎/进程启动（发生在 Dart main 之前）**，Release 的 Dart 准备只剩 ~69 ms（缓存/预检/配置/云服务/起 JVM 决策全加起来）；游戏侧 JVM+建窗 ~0.4 s 不归启动器管。也就是说：**java -version 缓存、预检转发已经把 Dart 侧压到边缘，冷启动窗口前再想减时间，只能改「入口形态」（常驻进程/原生 stub），靠继续优化 Dart 代码最多再省 <70 ms。**

## 2. 方法与产物

- 数据根：`C:\Users\ASUS\Desktop\copper_launcher\data`（checkout 内产物会自动用 `<仓库>\data`）
- 版本：`f7078a96-d701-4593-a7b9-17d5946773ea`（tag=主线，Mindustry v160.7，jar=`mindustrys\mindustry-v160.7-314baa30.jar`）
- Java：`C:\Program Files\Java\jdk-23\bin\java.exe`（Java 23.0.1），日志显示「Java 环境校验命中缓存」
- 产物（复用现有构建，未重新构建；为避免测试期间被别的并行构建覆盖，冻结到 `tmp\perf_runner\` 后跑）：
  - Debug：`runner\Debug`，exe sha256 `F4F064F80F02…`，`kernel_blob.bin` 2026-11-01 21:00:50（sha256 `E1ADF498D7AB…`）
  - Release：`runner\Release`，exe sha256 `436CB3E73FE3…`，`app.so` 2026-11-01 19:05:55（sha256 `529E908ADB08…`）
- 每轮前：杀掉全部 `copper_launcher.exe`（含残留 UI/云服务）与**游戏本体** java（命令行含 mindustry/copper_loader；Gradle/Kotlin daemon 保留），删 `data\cloud-service`，确保是冷启动；若日志出现「快捷启动：UI 在线 / 云服务在线」（被转发给在线进程），该轮作废并重试（本次 9 轮全部为真正冷启动）。
- 窗口判定：Win32 `EnumWindows` + `GetWindowThreadProcessId` + `IsWindowVisible` + `GetWindowClass/Title/Rect`，**只认 java.exe 进程的可见顶层窗口**；主判定 = 窗口 pid == 日志「进程 ID：」里的游戏 pid，兜底 = 标题含 Mindustry / 类名 SDL*；排除 `ConsoleWindowClass` 黑窗、启动器自身 pid、启动前已存在的 java 窗口。轮询 20 ms（检测误差 ≤20 ms）。
- 时间线仍从启动器日志读（显式 UTF-8）：预检/基础路径/配置/云服务/游戏进程创建/游戏可交互；`Total time to load` 由游戏自报。
- 引擎时间反推：实测「进程启动 → java 进程创建（`Process.StartTime` 高精度）」− 日志时间线「main → 游戏进程创建」；另用「进程启动 → 日志文件创建时间 − Dart 起点」做第二估计，两者本次相差 −2 ms（Debug）/ ~45 ms，可信。

## 3. 每轮数字

### Debug（3 次）

| # | 进程→窗口 | 进程→java创建 | 引擎 | Dart(时间线) | 预检→路径→配置→云服务→起JVM前 | java→窗口 | 窗口→可交互 | 可交互(旧) | 游戏自报 load | 日志 |
|---|---|---|---|---|---|---|---|---|---|---|
| D1 | 1909 | 1590 | 1272 | 318 | 86 → 89 → 139 → 158 → 318 | 319 | 3532 | 5441 | 3248 | 11-01T21-59-57.022.log |
| D2 | 1951 | 1620 | 1312 | 308 | 83 → 86 → 134 → 151 → 308 | 331 | 3813 | 5764 | 3518 | 11-01T22-00-12.397.log |
| D3 | 1967 | 1614 | 1310 | 304 | 85 → 89 → 135 → 152 → 304 | 353 | 3953 | 5920 | 3651 | 11-01T22-00-27.858.log |
| 均值 | **1942** | 1608 | 1298 | 310 | 85 → 88 → 136 → 154 → 310 | 334 | 3766 | 5708 | 3472 | |

### Release（前 3 次=主表，后 3 次=补充）

| # | 进程→窗口 | 进程→java创建 | 引擎 | Dart(时间线) | 预检→路径→配置→云服务→起JVM前 | java→窗口 | 窗口→可交互 | 可交互(旧) | 游戏自报 load | 日志 |
|---|---|---|---|---|---|---|---|---|---|---|
| R1 | 1593 | 1220 | 1158 | 62 | 12 → 13 → 18 → 28 → 62 | 373 | 4139 | 5732 | 3907 | 11-01T22-00-50.519.log |
| R2 | 2066 | 1624 | 1558 | 66 | 12 → 12 → 18 → 28 → 66 | 442 | 5557 | 7623 | 5225 | 11-01T22-01-06.531.log |
| R3 | 1792 | 1333 | 1256 | 77 | 19 → 21 → 26 → 34 → 77 | 459 | 5060 | 6852 | 4780 | 11-01T22-01-23.792.log |
| 前3均值 | **1817** | 1392 | 1324 | 68 | 14 → 15 → 21 → 30 → 68 | 425 | 4919 | 6736 | 4637 | |
| R4（补） | 1768 | 1352 | 1281 | 71 | 12 → 12 → 18 → 29 → 71 | 416 | 5295 | 7063 | 4963 | 11-01T22-02-41.036.log |
| R5（补） | 1903 | 1482 | 1406 | 76 | 11 → 12 → 17 → 30 → 76 | 421 | 5700 | 7603 | 5363 | 11-01T22-02-58.360.log |
| R6（补） | 1550 | 1220 | 1161 | 59 | 7 → 9 → 13 → 24 → 59 | 330 | 3584 | 5134 | 3318 | 11-01T22-03-15.663.log |
| 6 次均值 | **1779** | 1372 | 1303 | 69 | 12 → 13 → 18 → 29 → 69 | 407 | 4889 | 6668 | 4593 | |

> Release 的「窗口→可交互 / 游戏自报 load」波动大（3584–5700 ms）：测试期间有别的 agent 并行开 Debug 版 UI（22:03:28 日志「启动器形态：云同步代理」）和系统负载，**但窗口出现时间稳定在 1550–2066 ms（中位 1768）**。Debug 3 轮非常稳（1909/1951/1967）。另有一次首次触碰冻结产物的 Debug 冒烟 2171 ms（含首次扫描/冷缓存，未计入）。

### 窗口出现前分段（均值/中位）

| 分段（外部时钟） | Debug | Release |
|---|---|---|
| Flutter 引擎 + Windows 进程创建（进程启动 → Dart main，估） | 1298 / 1310 | 1303 / 1256 |
| Dart：main → java 进程创建（日志时间线） | 310 / 308 | 69 / 66 |
| 　其中 预检（Log.init 后） | 85 | 12 |
| 　其中 Dart 起点→基础路径 | 3 | 1 |
| 　其中 →配置就绪（TokenEncryptor/读盘/备份） | 48 | 6 |
| 　其中 →云服务就绪 | 18 | 9 |
| 　其中 云服务就绪→java 创建（Java 校验缓存命中/云同步/settings/内存估算/起 JVM） | 156 | 40 |
| 游戏侧：java 进程创建 → 窗口出现（JVM + SDL/GL 建窗） | 334 / 331 | 407 / 416 |
| **进程启动 → 窗口出现** | **1942 / 1951** | **1779 / 1768** |
| （不计入用户口径）窗口 → 可交互（游戏资源/存档加载） | 3766 | 4889（噪声大） |

## 4. 窗口出现前：还能优化什么 / 不能优化什么

### 还能优化（启动器侧）

1. **唯一的大头：Flutter 引擎/进程启动 ~1.2–1.3 s（占窗口前 65–70%）**。它发生在 Dart `main()` 之前（Windows 进程创建 + Flutter embedder/引擎 + Debug 的 kernel JIT / Release 的 app.so 加载），**Dart 代码改不动**。要压它必须换入口形态：
   - 常驻托盘/后台进程（UI 或云服务在线时，桌面快捷方式只投 `--launch-version`，靠已有进程直接拉起游戏；预检转发已经做了，但**只在常驻时才生效**，本次冷启动口径测不到这部分收益）；
   - 或做原生轻量 stub（Win32/Go/Rust 小 exe）只读配置并起 java，绕过 Flutter 引擎；
   - 代价：常驻内存 / 多维护一套入口。
2. **Dart 侧冷启动准备 Release 只剩 ~69 ms**（预检 12 → 路径 1 → 配置 6 → 云服务 9 → 起 JVM 前决策 40）。继续抠的上限 **<70 ms**；其中配置读盘/备份、云服务目录初始化、启动决策已接近 IO 下限。`java -version` 缓存已经生效（日志「Java 环境校验命中缓存」，启动决策→起 JVM 仅 ~40 ms），预检转发也已把「无 UI/服务时本进程直接进云服务模式」走通（日志「快捷启动：没有 UI / 服务，本进程进入云服务模式」）。
3. Debug 的 Dart 时间线 ~310 ms 是 kernel_blob JIT 造成，**用户不用 Debug，不构成优化目标**；保留它是为了开发态对照。

### 不能优化（启动器侧动不了）

1. **游戏侧 java 进程创建 → 窗口出现 ~0.33 s（Debug）/ ~0.42 s（Release）**：JVM（Java 23）启动 + SDL/GL 建窗，由 JDK/游戏决定。启动器只能通过启动参数间接影响（AppCDS/CDS、`-XX:TieredStopAtLevel=1`、减少 `-Xmx` 预留等），属运行期/游戏参数，本任务不改，且预期只有几十 ms。
2. **窗口出现 → 可交互（游戏自报 load 3.3–5.4 s）**：不是用户口径，属游戏资源/存档加载与日志转发，启动器无法提前。
3. **Windows 进程创建/杀软扫描、Flutter 引擎初始化**：代码层面消不掉（已计入第 1 条引擎时间）。
4. 游戏窗口出现的**时机**本身（先黑窗后内容）由游戏决定，启动器最多保证不额外等待（当前已经没有额外等待）。

## 5. 窗口检测可靠性 / 替代口径

- 9 轮有效测试 **9/9 检测到窗口**，全部命中方式为 `game-pid`（日志「进程 ID：」= 窗口 pid），窗口 `class=SDL_app`、`title=Mindustry`、`2014x1166`；`FirstJavaWindowMs` 与窗口时点一致，未误判启动器窗口/黑窗（启动器冷启动路径本身无窗口，且排除了 ConsoleWindowClass）。
- 若某些版本窗口检测不稳（例如全屏独占、非 SDL 窗口、无标题窗口），替代口径：
  - **进程启动 → java 进程创建（实测，稳定）** + **java 创建 → 窗口出现的固定偏移**（本机 Debug 中位 331 ms、Release 中位 416 ms）≈ 窗口时点；
  - 或用游戏日志首行（SDL 初始化）时间做上界校核。
- 本轮 `TotalToWindowMs` 的检测误差 ≤ 20 ms（轮询间隔），日志时间线是毫秒级自报，游戏日志行时间戳为秒级（只用于校核，不用于口径）。

## 6. 本次改动（只动 tool/）

`tool/launch_speed_probe.ps1`（保留原参数与日志时间线行为，新增）：
- Win32 P/Invoke：`EnumWindows / GetWindowThreadProcessId / IsWindowVisible / GetWindowText / GetClassName / GetWindowRect` + `QueryFullProcessImageName`（判断窗口属主是不是 java.exe）；每 20 ms 轮询一次可见顶层窗口。
- 窗口判定：优先 `pid == 日志里的游戏 pid`，兜底标题/类名；排除黑窗、启动器自身、启动前已存在的 java 窗口；记录首个 java 窗口用于诊断。
- 每轮新增输出：`TotalToWindowMs`（用户口径）、`WindowPid/Title/Class/Size/Match`、`GameProcExtMs`、`WindowAfterProcMs`（JVM+建窗）、`EngineMs`（反推）、`DartStartMs`、`WindowTimelineMs`、`InteractiveAfterWindowMs`；汇总里给出窗口前分段与「引擎两种估计之差」自检。
- 冷启动保障：清理残留 `copper_launcher.exe`；**只杀游戏本体 java**（命令行含 mindustry/copper_loader），不再误杀 Gradle/Kotlin daemon；检测到「转发给在线 UI/服务」自动作废重试（最多 3 次）。
- 新增 `-RunnerRoot`、`-PollMs`、`-LogPollMs`，支持用冻结产物跑；`Start-Process` 改为重定向 stdout/stderr + `-NoNewWindow`（走 CreateProcess）——实测冻结副本走默认 ShellExecute 会卡住，这是本次踩到的坑，脚本已规避，启动器输出存 `tmp\probe-*.out/err.txt`。
- 保持 UTF-8 BOM（PS 5.1 源码解析）与日志显式 UTF-8 读取。

数据/证据文件：`tmp\perf_debug_3.txt`、`tmp\perf_release_3.txt`、`tmp\perf_release_3b.txt`、`tmp\perf_debug_final_check.txt`；对应运行日志见 `data\logs\`（上表 Log 列）。
