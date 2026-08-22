---
name: copper-conventions
description: Copper Launcher（Flutter Mindustry 启动器）项目的协作约定与架构指南。当在此项目中编写、修改或重构代码时使用：包含用户与 AI 的协作规则（不确定先问、明确指令才动手、废弃文件不擅自删、先查 Flutter 内置组件）、主题色板体系（item 系列 / 三层交互 / 双模式设计）、页面/路由结构、按钮/tile 组件体系、overlay Layer 浮层组件体系，以及本项目的技术坑。触发场景：改这个项目的 UI、路由、组件、主题，或重构代码。
---

# Copper Launcher 协作约定与架构指南

## 协作规则（用户与 AI 之间的约定）

1. **不确定就问**：遇到任务范围、实现取舍、涉及删除/移动既有代码的歧义时，停下来用 AskUserQuestion 问，不要默默选择。
2. **明确指令才动手**：没有得到用户明确指令（"开始 / 写吧 / 动手"）之前，只讨论方案、不动代码。
3. **废弃文件只报告不删除**：发现可疑废弃代码（重构遗留、零引用等），说明判断原因后由用户决定；用户确认"属于遗留产物"才可删除。
4. **先查 Flutter 内置组件**：实现功能前先检查 Flutter 是否有内置组件（如 MenuAnchor、showMenu、OverlayPortal 等），能就先告知用户，不重复造轮子。
5. **surgical changes**：只改与任务相关的代码，不顺手清理无关死代码、不"改进"相邻代码。
6. **bash 转义坑**：含 `$` 的 Dart 插值代码不要用 `bash -c "python -c '...'"` 双层传递（`$` 会被 bash 展开导致变量名被吞），改用 Edit/Write 工具或临时脚本文件。

## 项目架构

Flutter 多平台 Mindustry 游戏启动器，**自研 UI 风格（不按 Material 3）**，仅依赖 Flutter 的跨平台能力。全项目目标：`flutter analyze` 0 error。

### 主题系统（lib/ui/theme/）

- 三层结构：`Palette`（原始色）→ `AppColors`（语义色，ThemeExtension）→ Widget
- **Widget 禁止直接引用 Palette 原色**，必须通过 `AppColors.of(context)` 获取语义色
- 文本与图标**共色**：`itemPrimary` / `itemSecondary` / `itemHint` / `itemOnInteractive`（text 系列已改名）
- 交互色**三层强调**：`interactiveLow`（弱）/ `interactive`（主）/ `interactiveHigh`（强）；暗色下 high 更亮
- 滚动条状态色：`scrollbarThumb` / `scrollbarThumbHover` / `scrollbarThumbPressed`（**暗色按压更亮、亮色更暗**）+ `scrollbarTrack` / `scrollbarTrackHover`（槽比滑块淡，拉开区分度）
- 输入框状态色：`inputBorder`（比 border 明显）/ `inputBorderHover` / `inputBorderFocus`（主题色）/ `inputBackgroundFocus`（略透明主题色背景）
- **双模式设计**（按钮/浮层通用）：
  - 暗色：玻璃感——透明背景 + elevation 恒 0（ReboundContainer 暗色自动禁）
  - 浅色：云母片浮动感——不透明背景（模拟半透明主题色）+ hover 浮出 elevation
  - "不透明模拟半透明"：`Color.alphaBlend(interactive.withAlpha(100), baseColor)`，视觉等同半透明且 elevation 阴影不透传
- 主题色衍生：基于 `colors.interactive` 的 HSL 色相偏移可生成衬托色

### 页面结构（lib/ui/pages/）

- 每个分项一个目录：容器页（如 `setting.dart`、`resource.dart`、`more.dart`）+ 子页面（`xxx_page.dart`）
- 容器页 = 二级导航：`MainPageLayout` + `PageNavigationRail` + `NavigationTile` + 底部 `NavigationCollapseButton`
- 容器页在 `didChangeDependencies` 中根据进入时的路由名决定初始分项
- 二级导航折叠状态存于 `config.setting.personalizationOptions.subNavigationCollapse`

### 路由（lib/ui/vars.dart）

- 单表 `routeMap`（`const Map<String, Widget>`）
- 按"主要页面 + 其下分项"分组组织；分项路由 key 重定向到对应的容器页（容器页按路由名定位分项）
- 与主要页面强相关的独立页面（如模组下载 `/mod_view/download`）跟随在所属页面下
- 路由常量命名：`xxxPageRouteKey = '/xxx'`，定义在各容器页文件内

### 按钮 / tile 组件体系（lib/ui/components/）

- **`ReboundContainer`**（rebound/）：最底层，按压回弹 + 自带 Material/InkWell + elevation 逻辑（浅色 hover 浮出 / 暗色恒 0）+ `surfaceChild`（**交互隔离层**：点击不透传到 InkWell 不触发回弹）+ `surfaceAlignment`
- **`ReboundButton`**（button/rebound_button.dart）：无状态基础按钮，直接基于 ReboundContainer，双模式背景，接收任意 child
- **`IconTextButton`**：无状态图标 + 文本按钮（基于 ReboundButton）
- **`ActionButton`**：有选中态（点击切换、自持 `initialSelected`/`onChanged`）+ 禁用态（`enable`），基于 ReboundContainer，带 hint
- **`ItemTile`**（tile/）：列表项（leading/title/subtitle/trailing + `selected` 选中态 + `enable` 禁用态），基于 ReboundContainer
- 旧 `lib/ui/util/widget/`（feature_button、feature_list_tile 等）是**待重构区**，新代码不要依赖，后续迁移

### overlay Layer 组件体系（lib/ui/components/overlay_layer/）

- **`PopupOverlay`**：基础底座（`OverlayPortal` + `CustomSingleChildLayout` 定位，布局管道提供尺寸、无需预测量；动画接口可感知 Placement；锚点移动自动关闭；点击外部 / Esc 关闭；`onClose` 回调；`overlayChildBuilder` 提供 `anchorRect`）
- **`MenuLayer`**：右键 / 长按菜单（缩放锚点 = 鼠标在菜单内的位置；专用位置策略按**锚点优先级**：左上→右上→左下→右下→左中→右中，菜单太大时沉底）
- **`HintLayer`**：悬停 / 长按提示（四方位环绕定位 + `HintAnimation` 接口）
- **`DropdownLayer`**：下拉选择（高度展开动画，菜单与锚点同宽）
- **`ActionSlideLayer`**：滑动菜单（左滑露出操作按钮，`ClipPath` 差集遮罩让 child 区域作为蒙版裁掉菜单层，透明背景不透出）
- 位置策略可注入：`PopupOverlayPositionDelegate`（默认 `AnchorFlipPositionDelegate`；MenuLayer 用锚点优先级 delegate；HintLayer 用环绕 delegate）

## 本机源码参考（Mindustry / Arc）

本机桌面有 Mindustry 与 Arc 的完整源码（git 浅克隆，shallow），作为游戏侧 API / 版本的参考依据：

- **Mindustry**：`C:\Users\ASUS\Desktop\Mindustry`（master 分支）
  - 关键目录：`core/src/`（游戏本体逻辑，如 `mindustry/` 包）、`desktop/src/`（桌面启动器入口）、`tools/`（构建工具）
  - 常用于：查版本号 / release 结构、游戏启动参数、JVM 配置、模组格式（`.jar` 与 `.hjson`）、服务端配置
- **Arc**：`C:\Users\ASUS\Desktop\Arc`（master 分支，Mindustry 底层框架）
  - 关键目录：`arc-core/src/`（渲染、窗口、输入、文件、音频等核心 API）、`backends/`（各平台后端）、`extensions/`、`natives/`
  - 常用于：查 arc 提供的底层能力（如 `Arc` 单例、`Core` 静态访问器）
- **Flutter SDK 源码**：`C:\Software\flutter`（本地安装，references 别名 `@flutter-sdk`）
  - 关键目录：`packages/flutter/lib/src/`（框架实现：`widgets/` 的 overlay/OverlayPortal、`gestures/` 的指针事件派发与 hit test、`rendering/` 的渲染管线）
  - 常用于：查 Flutter 内部行为（如 OverlayPortal hit test 是否阻断下层、PointerSignalEvent 派发路径、AnimationController TickerFuture 复用语义等），避免凭印象猜测框架行为
- **访问方式**：三者已在项目 `opencode.json` 的 `references` 中声明（`@mindustry` / `@arc` / `@flutter-sdk`），外部目录自动放行，可跨项目目录直接 read / grep / bash
- Mindustry / Arc 是**浅克隆**：`git log` 只有最新一条提交、无 tag，不要指望本地历史或版本标签；查版本请以最新提交或官方 release 为准

## 技术坑（已踩过，避免重犯）

- `CustomSingleChildLayout.getPositionForChild` 在**布局阶段**调用：内部不能同步写 ValueNotifier / setState，需 post-frame 延迟（否则报 "Build scheduled during frame"）
- `SingleTickerProviderStateMixin` 只允许一个 Ticker；多个 AnimationController 必须用 `TickerProviderStateMixin`
- InkWell 需要 Material ancestor 才能渲染高亮 / splash；`ReboundButton`/`ReboundContainer` 自带 Material + InkWell，浮层里可直接用
- `SizeTransition` 内部 `Align`（widthFactor 为 null）在有限宽度约束下会**撑满**：浮层宽度约束需放开（`maxWidth: infinity`）让它收缩到内容宽度，否则 childSize 失真导致定位 clamp 到边缘
- 浮层定位是布局快照：锚点被滚动 / 页面切换移动时需自动关闭（MenuAnchor 同款行为）
- 入场动画要等布局后的 Placement 就绪再 `forward()`（动画接口才能拿到正确的锚点方向 / 方位）
- `Tween` 的 end 不能为 null：传参前兜底（如 `widget.pressedScale ?? 0.90`）
- Stack 叠加层：透明背景的 child 不会遮挡下层组件——若需"child 盖住下层"，用 `ClipPath` 差集（`Path.combine(PathOperation.difference, ...)`）把 child 区域从下层裁掉（PS 遮罩思路）
- 右键菜单定位：菜单放不下时**不要翻到锚点另一侧**（会远离鼠标），按锚点优先级（左上→右上→左下→右下）选择生长角，都放不下时沉底
- 调试输出：布局 / 定位问题可临时加 `debugPrint` 定位，定位后删除；注意 bash 转义

## 常用验证

- 修改后跑 `flutter analyze`（目标 0 error；残余 warning 多为预先存在的遗留，不属于本次改动）
- 布局 / 定位问题：在 `_PopupOverlayLayout.getPositionForChild` 加临时 `debugPrint('anchor=... childSize=... overlay=... offset=...')` 定位，分析后删除
