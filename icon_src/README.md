# 桌面图标源图（`icon_src/`）

系统桌面图标（安卓自适应图标）由这里的 `1024×1024` 源图合成，**一主题 = 一个物品 + 对应传送带**：

| 主题（`ThemeColor`） | 物品 | 传送带 |
| --- | --- | --- |
| copper | `copper.png` | `conveyor.png`（基础传送带） |
| titanium | `titanium.png` | `titanium-conveyor.png` |
| thorium | `thorium.png` | `armored-conveyor.png`（装甲传送带） |
| plastanium | `plastanium.png` | `plastanium-conveyor.png` |

## 合成规则（改图后按这个重出）

1. 传送带铺满 `1024×1024` 当底，物品原图 `1024×1024` 原位置盖上去（1:1，不缩放、不重排）
2. 因为 Android 自适应图标只显示 108dp 画布中间的 **72dp**，整张合成图要缩到画布的 `72/108`、居中 —— 这样真机上看到的就是完整原图
3. 每个密度 `108/162/216/324/432` 各出一张前景：`mipmap-<density>/ic_launcher_foreground.png`（copper）、`ic_launcher_foreground_<theme>.png`（其余三个）
4. 背景层共用 `mipmap-<density>/ic_launcher_background.png`（基础传送带铺满），可见区里会被前景完全盖住，只防个别 launcher 露出 72dp 以外

重出命令（Windows，`System.Drawing`；脚本在 `tool/gen_launcher_icons.ps1`）：

```powershell
pwsh -File tool/gen_launcher_icons.ps1
```

## 注意

- 图标跟随 App 内主题：切换主题时靠清单里四个 `activity-alias` 换桌面入口，见 `android/app/src/main/kotlin/io/github/copper/launcher/shortcut/LauncherIcon.kt`
- `assets/images/{copper,titanium,thorium,plastanium}.png` 是 App 界面里用的 **32×32 像素图**，跟这里的高清图标不是一套，别替换
- 桌面端（Windows/Linux）图标只用铜块本体（`assets/images/app_icon.png` / `windows/runner/resources/app_icon.ico`），不用这里的传送带合成图
