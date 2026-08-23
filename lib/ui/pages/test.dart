import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/menu_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/scroll/list_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/info/notification.dart';
import 'package:copper_launcher/ui/util/info/task_drawer_opener.dart';
import 'package:copper_launcher/ui/util/info/task_list.dart';
import 'package:flutter/material.dart';

/// 测试页：浮层体系（PopupOverlay 及 Menu / Dropdown / Hint / ActionSlide）测试用例集中地。
class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => TestState();
}

class TestState extends State<Test> {
  final PopupOverlayController customController = PopupOverlayController();
  final ScrollController listController = ScrollController();

  int _menuLog = 0;
  int _dropdownValue = 1;
  int _customClick = 0;
  String _slideLog = '（未点击）';

  @override
  void dispose() {
    listController.dispose();
    super.dispose();
  }

  Widget _card({
    required String title,
    required String desc,
    required Widget child,
  }) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _triggerBox(String label, {double width = 220, double height = 90}) {
    final colors = AppColors.of(context);
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.interactive.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.interactive.withAlpha(120)),
      ),
      child: Text(label),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );

  /// 通用菜单项（右键菜单回归用）。
  List<Widget> _buildMenu(BuildContext context, PopupOverlayController controller) {
    return [
      for (int i = 0; i < 5; i++)
        ReboundMenuButton(
          label: '菜单项 $i',
          onTap: () {
            setState(() => _menuLog = i);
            controller.dismiss();
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CopperSingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ════════ 1. PopupOverlay 基础：按钮打开自定义浮层 ════════
          _sectionTitle('1. PopupOverlay 基础（控制器 + 自定义浮层）'),
          _card(
            title: '自定义浮层（点击 / 外部 / Esc 关闭）',
            desc: '按钮触发 open()；浮层内按钮点 dismiss() 关闭。点击浮层外或按 Esc 也会关闭（onClose 已挂接日志）。',
            child: Row(
              children: [
                PopupOverlay(
                  controller: customController,
                  overlayChildBuilder: (context, anchorRect) => Container(
                    width: 240,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).cardBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.of(context).border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('自定义浮层内容', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('点击次数：$_customClick'),
                        const SizedBox(height: 8),
                        ReboundMenuButton(
                          label: '点我 +1',
                          onTap: () => setState(() => _customClick++),
                        ),
                        const SizedBox(height: 8),
                        ReboundMenuButton(label: '关闭', onTap: customController.dismiss),
                      ],
                    ),
                  ),
                  onClose: () => debugPrint('[PopupOverlay] onClose 触发'),
                  child: ReboundMenuButton(
                    label: '打开自定义浮层',
                    onTap: () => customController.open(),
                  ),
                ),
                const SizedBox(width: 16),
                Text('最近点击次数：$_customClick'),
              ],
            ),
          ),

          // ════════ 2. PopupOverlay 翻转：锚点贴近四角 ════════
          _sectionTitle('2. AnchorFlipPositionDelegate（翻转 / 贴边）'),
          _card(
            title: '四角锚点翻转测试',
            desc: '四个触发器各自独立控制器，浮层放不下时应自动翻转方向、贴安全边距内，不超出屏幕。',
            child: SizedBox(
              height: 240,
              child: Stack(
                children: [
                  _FlipTrigger(label: '左上角', dx: -1, dy: -1),
                  _FlipTrigger(label: '右上角', dx: 1, dy: -1),
                  _FlipTrigger(label: '左下角', dx: -1, dy: 1),
                  _FlipTrigger(label: '右下角', dx: 1, dy: 1),
                ],
              ),
            ),
          ),

          // ════════ 3. PopupOverlay 锚点移动自动关闭 ════════
          _sectionTitle('3. 锚点移动自动关闭'),
          _card(
            title: '锚点随列表滚动移动时自动关闭',
            desc: '锚点 = 列表内的一项。打开浮层后滚动列表，锚点移动触发自动 dismiss（与 MenuAnchor 同款行为）。',
            child: SizedBox(
              height: 240,
              child: CopperListView(
                controller: listController,
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('↓ 打开下方浮层后，滚动此列表 ↓'),
                  ),
                  for (int i = 0; i < 30; i++)
                    i == 3
                        ? _AnchorInList(i: i)
                        : Container(
                            height: 36,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 8),
                            child: Text('滚动项 $i'),
                          ),
                ],
              ),
            ),
          ),

          // ════════ 4. MenuLayer 右键菜单 ════════
          _sectionTitle('4. MenuLayer 右键菜单'),
          _card(
            title: '右键 / 长按弹出，菜单位置自适应',
            desc: '对目标框点右键（桌面）或长按（移动端）弹出菜单。最近点击菜单项：$_menuLog。锚点优先级：左上→右上→左下→右下。',
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                MenuLayer(
                  menuBuilder: _buildMenu,
                  child: _triggerBox('右键弹出菜单（5 项）'),
                ),
                MenuLayer(
                  rightClickTrigger: false,
                  longPressTrigger: true,
                  menuBuilder: _buildMenu,
                  child: _triggerBox('仅长按触发'),
                ),
              ],
            ),
          ),

          // ════════ 5. DropdownLayer 下拉选择 ════════
          _sectionTitle('5. DropdownLayer 下拉选择'),
          _card(
            title: '下拉展开 / 选择 / 翻转',
            desc: '点击头部展开，选择后关闭并回调 onSelect。当前值：$_dropdownValue。优先下方展开，下方没空间翻到上方；滚轮滚动外部会像点击外部一样自动关闭；关闭瞬间箭头/高亮立即复位。',
            child: DropdownLayer<int>(
              initialValue: _dropdownValue,
              options: [
                for (int i = 0; i < 10; i++)
                  DropdownOption(value: i, label: '选项 $i'),
              ],
              width: 260,
              onSelect: (v) => setState(() => _dropdownValue = v),
            ),
          ),

          // ════════ 6. HintLayer 悬停提示 ════════
          _sectionTitle('6. HintLayer 悬停 / 长按提示'),
          _card(
            title: '四方位环绕定位（auto）',
            desc: '鼠标悬停触发，提示框围绕锚点自动选择合适方位；移出即消失。',
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                HintLayer(
                  hint: '上方提示',
                  waitDuration: const Duration(milliseconds: 100),
                  child: _triggerBox('悬停 1（auto）', width: 150, height: 60),
                ),
                HintLayer(
                  hint: '固定显示在下方',
                  preferPosition: HintPosition.bottom,
                  waitDuration: const Duration(milliseconds: 100),
                  child: _triggerBox('悬停 2（bottom）', width: 150, height: 60),
                ),
                HintLayer(
                  hint: '固定显示在左侧',
                  preferPosition: HintPosition.left,
                  waitDuration: const Duration(milliseconds: 100),
                  child: _triggerBox('悬停 3（left）', width: 150, height: 60),
                ),
                HintLayer(
                  hint: '自定义样式提示',
                  waitDuration: const Duration(milliseconds: 100),
                  showAnimation: HintAnimation.slide,
                  hintWidget: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('slide 动画 + 自定义样式'),
                  ),
                  child: _triggerBox('悬停 4（slide）', width: 150, height: 60),
                ),
              ],
            ),
          ),

          // ════════ 7. ActionSlideLayer 滑动菜单 ════════
          _sectionTitle('7. ActionSlideLayer 滑动操作菜单'),
          _card(
            title: '左滑露出操作按钮',
            desc: '向左拖动 child 露出右侧操作按钮；超过阈值松手保持展开，点 child 收回。点击操作按钮有回弹反馈。最近点击：$_slideLog。菜单按钮置顶可点，非按钮区域事件默认透传。',
            child: SizedBox(
              width: 360,
              child: ActionSlideLayer(
                actions: [
                  _slideAction('收藏', Colors.blue, () => setState(() => _slideLog = '收藏')),
                  _slideAction('删除', Colors.red, () => setState(() => _slideLog = '删除')),
                ],
                child: Container(
                  height: 56,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: AppColors.of(context).interactive.withAlpha(30),
                  child: const Text('← 向左滑动试试'),
                ),
              ),
            ),
          ),
          // ════════ 8. 通知（NotificationWidget） ════════
          _sectionTitle('8. 通知（入场/退场动画 + 左滑删除）'),
          _card(
            title: '通知测试（左上角弹出）',
            desc: '点击按钮发通知（左上角出现，入场滑入+淡入，退场先收缩再滑走）。左滑通知超阈值松手删除，未达阈值回弹；点击通知触发回调并删除；长时长通知等待自动消失。',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ReboundButton(
                  onTap: () => addNotice(
                    icon: Icons.info_outline,
                    title: '普通通知',
                    content: '3 秒后自动消失，可以左滑删除',
                  ),
                  child: const Text('发普通通知'),
                ),
                ReboundButton(
                  onTap: () => addNotice(
                    icon: Icons.warning_amber,
                    title: '长时通知',
                    content: '10 秒才消失，方便慢慢滑动测试',
                    duration: const Duration(seconds: 10),
                  ),
                  child: const Text('发长时通知'),
                ),
                ReboundButton(
                  onTap: () => addNotice(
                    icon: Icons.check_circle,
                    title: '点击回调',
                    content: '点我试试（点击触发回调并删除）',
                    onTap: () => addNotice(
                      icon: Icons.thumb_up,
                      title: '你点了通知',
                      content: '这条是回调里发的',
                      duration: const Duration(seconds: 2),
                    ),
                  ),
                  child: const Text('点击回调通知'),
                ),
                ReboundButton(
                  onTap: () {
                    addNotice(
                      icon: Icons.bolt,
                      title: '连发 1',
                      content: '快速连发测试（条目独立，互不影响）',
                      duration: const Duration(seconds: 6),
                    );
                    addNotice(
                      icon: Icons.bolt,
                      title: '连发 2',
                      content: '与连发 1 同时在场',
                      duration: const Duration(seconds: 6),
                    );
                    addNotice(
                      icon: Icons.bolt,
                      title: '连发 3',
                      content: '与连发 1/2 同时在场',
                      duration: const Duration(seconds: 6),
                    );
                  },
                  child: const Text('连发 3 条'),
                ),
              ],
            ),
          ),
          _taskSection(),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  // ════════ 9. 任务系统（TaskManager + TaskList + TaskDrawer） ════════
  Widget _taskSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('9. 任务系统（TaskManager + TaskList + TaskDrawer）'),
        _card(
          title: '任务列表 / 任务抽屉 / 聚合进度',
          desc: '添加任务进 TaskList（展示入场/移除动画），TaskDrawer 显示进行中数量与聚合进度。任务数秒完成，可点“取消全部”让其离开进行中状态。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ReboundButton(
                    onTap: () => _addSimTask(TaskType.download, '模拟下载任务'),
                    child: const Text('+ 模拟下载'),
                  ),
                  const SizedBox(width: 8),
                  ReboundButton(
                    onTap: () => _addSimTask(TaskType.check, '模拟校验任务'),
                    child: const Text('+ 模拟校验'),
                  ),
                  const SizedBox(width: 8),
                  ReboundButton(
                    onTap: _cancelAll,
                    child: const Text('取消全部'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('任务抽屉：'),
                  const SizedBox(width: 8),
                  const TaskDrawerOpener(),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(height: 320, child: const TaskList()),
            ],
          ),
        ),
      ],
    );
  }

  /// 添加一个模拟任务：progress 逐帧推进，数秒后自然完成。
  void _addSimTask(TaskType type, String label) {
    addTask(
      SimpleTask(
        type: type,
        describe: label,
        futureTask: (t) async {
          for (var i = 0; i <= 10; i++) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (t.status != TaskStatus.process) return; // 已取消/暂停，提前结束
            t.progress = i / 10;
            t.updateDisplay();
          }
        },
      ),
    );
  }

  void _cancelAll() {
    for (final task in taskManager.currentTasks) {
      if (task.status == TaskStatus.process) {
        changeTaskStatus(task.id, TaskStatus.cancel);
      }
    }
  }

  /// 翻转测试触发器：dx/dy 表示水平 / 垂直的对齐方向。

  Widget _slideAction(String label, Color color, VoidCallback onTap) {
    return ReboundButton(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      pressedScale: 0.9,
      baseColor: color,
      child: SizedBox(
        width: 64,
        height: double.infinity,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

/// 四角翻转触发器：独立控制器，浮层放不下时自动翻转 / 贴边。
///
/// 注意：PopupOverlay 的 child 是锚点本身（按钮），
/// Align 必须在 PopupOverlay 外层——否则锚点矩形 = 整个 Stack 区域，
/// 翻转始终从卡片右下角起步，无法看出四角差异。
class _FlipTrigger extends StatefulWidget {
  final String label;
  final int dx;
  final int dy;

  const _FlipTrigger({required this.label, required this.dx, required this.dy});

  @override
  State<_FlipTrigger> createState() => _FlipTriggerState();
}

class _FlipTriggerState extends State<_FlipTrigger> {
  final PopupOverlayController _controller = PopupOverlayController();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(widget.dx.toDouble(), widget.dy.toDouble()),
      child: PopupOverlay(
        controller: _controller,
        overlayChildBuilder: (context, anchorRect) => Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.of(context).cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Text('${widget.label} 的浮层（应始终在屏幕内）'),
        ),
        child: ReboundMenuButton(
          label: widget.label,
          onTap: () => _controller.open(),
        ),
      ),
    );
  }
}

/// 列表内的锚点项：打开浮层后滚动列表，锚点移动触发自动关闭。
class _AnchorInList extends StatefulWidget {
  final int i;

  const _AnchorInList({required this.i});

  @override
  State<_AnchorInList> createState() => _AnchorInListState();
}

class _AnchorInListState extends State<_AnchorInList> {
  final PopupOverlayController _controller = PopupOverlayController();

  @override
  Widget build(BuildContext context) {
    return PopupOverlay(
      controller: _controller,
      overlayChildBuilder: (context, anchorRect) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.of(context).cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.of(context).border),
        ),
        child: const Text('锚点移动时本浮层应自动关闭'),
      ),
      child: ReboundMenuButton(
        label: '锚点项（打开浮层后滚列表）',
        onTap: () => _controller.open(),
      ),
    );
  }
}

/// 简易菜单项按钮（本测试页专用）。
///
/// 注意：不要用 `Container(alignment: Alignment.center)`——
/// 内部会包 Align，松约束下会撑满父宽度。用 Row(mainAxisSize: min)
/// 保持自适应宽度，四角测试才能正确显示。
class ReboundMenuButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const ReboundMenuButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.interactive.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.interactive.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label, style: TextStyle(color: colors.itemPrimary))],
        ),
      ),
    );
  }
}
