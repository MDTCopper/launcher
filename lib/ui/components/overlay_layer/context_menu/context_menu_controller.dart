import 'dart:async';

import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_entry.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_panel.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_position.dart';
import 'package:flutter/material.dart';

/// 全局菜单控制器：整个应用只有 [instance] 这一个实例
///
/// 一个实例管一条「根菜单 + 若干级子菜单」的链，同时管正在播退场的旧实例；
/// 同级菜单再来一个时，旧的那份不是就地丢掉，而是先播完自己的退场动画 ——
/// 这就是「同一时刻可以有多个菜单实例」的唯一用途
///
/// 名字带 Global 前缀是为了避开 Flutter 自带的 `ContextMenuController`
///
/// 本身是 [ChangeNotifier]：isShowing / depth 变了就通知，页面可以直接监听它
class GlobalContextMenuController extends ChangeNotifier {
  GlobalContextMenuController._();

  static final GlobalContextMenuController instance =
      GlobalContextMenuController._();

  /// 当前活跃的菜单链
  _ContextMenuSession? _active;

  /// 正在播退场的会话，播完各自移除
  final List<_ContextMenuSession> _retiring = [];

  /// 悬停展开 / 收起的等待定时器，按层级记
  final Map<int, Timer> _pendingOpen = {};
  final Map<int, Timer> _pendingClose = {};

  /// 第几次 show；关闭层靠它认「这一次派发里有没有新菜单顶上来」
  int _showGeneration = 0;

  /// 是否有菜单正在显示（正在退场的旧实例不算）
  bool get isShowing => _active?.panels.isNotEmpty ?? false;

  /// 当前展开到第几级：根菜单为 1，展开一级子菜单为 2
  int get depth => _active?.panels.length ?? 0;

  /// 在 [position]（全局坐标）弹菜单
  ///
  /// [relocateOnReopen] 为 true 时，同级菜单再次出现会让**同一个面板**移动过去
  /// 并换成新内容；否则旧面板留在原地播退场，新面板在新位置入场
  Future<void> show({
    required BuildContext context,
    required Offset position,
    required List<ContextMenuEntry> entries,
    ContextMenuPositionDelegate? positionDelegate,
    bool relocateOnReopen = false,
    ContextMenuStyle style = const ContextMenuStyle(),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final anchor = ContextMenuAnchor.point(
      _toOverlayPosition(overlay, position),
    );
    final delegate =
        positionDelegate ?? ContextMenuPositionDelegate.forPlatform();
    _showGeneration++;

    if (relocateOnReopen && _relocate(anchor, entries)) {
      return _active!.closed.future;
    }

    _retireActive();
    final session = _ContextMenuSession(
      overlay: overlay,
      delegate: delegate,
      style: style,
    );
    _active = session;
    _addPanel(
      session,
      level: 0,
      anchor: anchor,
      entries: entries,
      barrier: true,
    );
    notifyListeners();
    return session.closed.future;
  }

  /// 收起整条菜单链
  ///
  /// [immediate] 为 true 时不播退场动画，连正在退场的旧实例一起清掉
  void dismiss({bool immediate = false}) {
    _cancelAllTimers();
    final session = _active;
    if (session != null) {
      _active = null;
      _retiring.add(session);
      for (final panel in session.panels.toList()) {
        _dismissPanel(session, panel, animate: !immediate);
      }
    }
    if (!immediate) {
      notifyListeners();
      return;
    }
    for (final retiring in _retiring.toList()) {
      final panels = [...retiring.panels, ...retiring.exiting];
      for (final panel in panels) {
        _removePanel(retiring, panel);
      }
    }
    notifyListeners();
  }

  Offset _toOverlayPosition(OverlayState overlay, Offset globalPosition) {
    final box = overlay.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return globalPosition;
    return box.globalToLocal(globalPosition);
  }

  /// 右键 / 中键落在关闭层上：等这一次事件派发走完再决定收不收
  ///
  /// 下层可能正是新的触发区，它在同一次派发里紧接着调 [show]，
  /// 那时就不该收，交给新菜单接管
  void dismissUnlessReplaced() {
    if (_active == null) return;
    final generation = _showGeneration;
    scheduleMicrotask(() {
      if (_showGeneration == generation) dismiss();
    });
  }

  _MenuPanel? _panelAt(int level) {
    if (level < 0) return null;
    final session = _active;
    if (session == null) return null;
    for (final panel in session.panels) {
      if (panel.state.level == level) return panel;
    }
    return null;
  }

  _MenuPanel _addPanel(
    _ContextMenuSession session, {
    required int level,
    required ContextMenuAnchor anchor,
    required List<ContextMenuEntry> entries,
    required bool barrier,
    int? parentIndex,
    bool sticky = false,
  }) {
    final state = ContextMenuPanelState(
      entries: entries,
      anchor: anchor,
      level: level,
      barrier: barrier,
      sticky: sticky,
    )..parentIndex = parentIndex;
    final panel = _MenuPanel(state: state);
    panel.entry = OverlayEntry(
      builder: (context) => ContextMenuPanel(
        entries: state.entries,
        anchor: state.anchor,
        level: state.level,
        activeIndex: state.activeIndex,
        visible: state.visible,
        barrier: state.barrier,
        delegate: session.delegate,
        style: session.style,
        callbacks: ContextMenuPanelCallbacks(
          onEntryActivated: (index, itemRect) =>
              _activateEntry(panel, index, itemRect),
          onEntryHover: (index, itemRect, inside) =>
              _handleEntryHover(panel, index, itemRect, inside),
          onPanelHover: (inside) => _handlePanelHover(panel, inside),
          onBarrierDown: dismissUnlessReplaced,
          onDismiss: () => dismiss(),
          onHidden: () => _handlePanelHidden(panel),
        ),
      ),
    );
    session.panels.add(panel);
    session.overlay.insert(panel.entry);
    return panel;
  }

  /// 旧菜单让位：子菜单直接销毁，根面板播完退场动画再移除
  void _retireActive() {
    final session = _active;
    if (session == null) return;
    // 悬停定时器留着会在新菜单上乱动手脚，先清掉
    _cancelAllTimers();
    _active = null;
    _retiring.add(session);
    for (final panel in session.panels.toList()) {
      if (panel.state.level == 0) {
        _dismissPanel(session, panel);
      } else {
        _removePanel(session, panel);
      }
    }
  }

  /// 同级菜单替换：复用同一个面板，移动过去并换内容，子菜单当场销毁
  bool _relocate(ContextMenuAnchor anchor, List<ContextMenuEntry> entries) {
    final session = _active;
    if (session == null || session.panels.isEmpty) return false;
    _cancelAllTimers();
    for (final panel
        in session.panels.where((p) => p.state.level > 0).toList()) {
      _removePanel(session, panel);
    }
    final root = session.panels.first;
    root.state
      ..entries = entries
      ..anchor = anchor
      ..activeIndex = null
      ..sticky = false;
    root.entry.markNeedsBuild();
    return true;
  }

  void _activateEntry(_MenuPanel panel, int index, Rect itemRect) {
    if (_isRetired(panel)) return;
    if (index < 0 || index >= panel.state.entries.length) return;
    switch (panel.state.entries[index]) {
      case ContextMenuAction entry:
        if (!entry.isEnabled) return;
        final onSelected = entry.onSelected;
        // 先收菜单再执行：回调里可能又要弹菜单（如跳到另一处右键）
        dismiss();
        onSelected?.call();
      case ContextMenuSubmenu entry:
        if (!entry.enabled) return;
        _toggleSubmenu(panel, index, itemRect);
      case ContextMenuDivider():
      case ContextMenuHeader():
        break;
    }
  }

  void _toggleSubmenu(_MenuPanel panel, int index, Rect itemRect) {
    final childLevel = panel.state.level + 1;
    final current = _panelAt(childLevel);
    // 已经为这个条目常驻展开，再点一次就是收起
    if (current != null &&
        current.state.visible &&
        current.state.parentIndex == index &&
        current.state.sticky) {
      _closeSubmenusFrom(childLevel);
      return;
    }
    _openSubmenu(panel, index, itemRect, sticky: true);
  }

  void _openSubmenu(
    _MenuPanel panel,
    int index,
    Rect itemRect, {
    required bool sticky,
  }) {
    final session = _active;
    if (session == null || panel.removed) return;
    if (index < 0 || index >= panel.state.entries.length) return;
    final entry = panel.state.entries[index];
    if (entry is! ContextMenuSubmenu || !entry.enabled) return;

    final childLevel = panel.state.level + 1;
    _cancelCloseTimer(childLevel);
    _cancelOpenTimer(childLevel);
    // 更深的层级一律销毁：子菜单换了内容，下一级就没有意义了
    _closeSubmenusFrom(childLevel + 1);

    if (panel.state.activeIndex != index) {
      panel.state.activeIndex = index;
      panel.entry.markNeedsBuild();
    }

    final existing = _panelAt(childLevel);
    if (existing == null) {
      _addPanel(
        session,
        level: childLevel,
        anchor: ContextMenuAnchor.item(itemRect),
        entries: entry.entries,
        barrier: false,
        parentIndex: index,
        sticky: sticky,
      );
      notifyListeners();
      return;
    }
    // 同一个子面板换个条目挂：位置与尺寸自己动画过去
    existing.state
      ..entries = entry.entries
      ..anchor = ContextMenuAnchor.item(itemRect)
      ..activeIndex = null
      ..parentIndex = index
      ..sticky = sticky;
    existing.entry.markNeedsBuild();
    notifyListeners();
  }

  void _handleEntryHover(
    _MenuPanel panel,
    int index,
    Rect itemRect,
    bool inside,
  ) {
    if (_isRetired(panel)) return;
    final childLevel = panel.state.level + 1;
    // 换条目 / 移开就撤掉上一条目排的展开，否则鼠标扫过去也会把下一级开出来
    _cancelOpenTimer(childLevel);
    if (!inside) {
      if (_hasTemporarySubmenu(childLevel, ofIndex: index)) {
        _scheduleClose(childLevel);
      }
      return;
    }
    // 进到这一级就说明指针还在这条链上，父级排的收起一并撤掉
    _cancelCloseTimersUpTo(childLevel);
    if (index < 0 || index >= panel.state.entries.length) return;
    final entry = panel.state.entries[index];
    if (entry is ContextMenuSubmenu && entry.enabled) {
      final current = _panelAt(childLevel);
      final alreadyOpen =
          current != null &&
          current.state.visible &&
          current.state.parentIndex == index;
      if (alreadyOpen) return;
      _scheduleOpen(
        childLevel,
        () => _openSubmenu(panel, index, itemRect, sticky: false),
      );
      return;
    }
    // 悬停到普通条目也排队收起：指针路过时不会把临时子菜单掐掉，常驻的不动
    if (_hasTemporarySubmenu(childLevel)) {
      _scheduleClose(childLevel);
    }
  }

  void _handlePanelHover(_MenuPanel panel, bool inside) {
    if (_isRetired(panel)) return;
    final level = panel.state.level;
    if (inside) {
      // 进到这一级就说明还在链上，撤掉祖先排的收起
      _cancelCloseTimersUpTo(level);
      return;
    }
    // 指针离开面板：排着队的展开也一起撤掉，否则人走了菜单还会自己开出来
    _cancelOpenTimer(level + 1);
    // 根面板上移开：收它的临时子菜单；子面板上移开：收它自己
    if (panel.state.sticky && level > 0) return;
    _scheduleClose(level == 0 ? 1 : level);
  }

  /// [ofIndex] 给了就只认挂在那个条目上的子菜单，不给就按层级认
  ///
  /// 离开条目必须认条目：不认的话，移开普通条目也会把别人的子菜单收掉
  bool _hasTemporarySubmenu(int level, {int? ofIndex}) {
    final submenu = _panelAt(level);
    if (submenu == null || !submenu.state.visible || submenu.state.sticky) {
      return false;
    }
    return ofIndex == null || submenu.state.parentIndex == ofIndex;
  }

  bool _isRetired(_MenuPanel panel) =>
      panel.removed || !panel.state.visible || !_isOpen(panel);

  bool _isOpen(_MenuPanel panel) => _active?.panels.contains(panel) ?? false;

  void _scheduleOpen(int level, VoidCallback action) {
    _cancelOpenTimer(level);
    final delay = _active?.style.hoverOpenDelay ?? Duration.zero;
    _pendingOpen[level] = Timer(delay, () {
      _pendingOpen.remove(level);
      action();
    });
  }

  /// 悬停收起只收临时的，点开过的常驻不许被定时器收掉
  void _scheduleClose(int level) {
    _cancelCloseTimer(level);
    final delay = _active?.style.hoverCloseDelay ?? Duration.zero;
    _pendingClose[level] = Timer(delay, () {
      _pendingClose.remove(level);
      _closeSubmenusFrom(level, onlyTemporary: true);
    });
  }

  void _cancelOpenTimer(int level) {
    _pendingOpen.remove(level)?.cancel();
  }

  void _cancelCloseTimer(int level) {
    _pendingClose.remove(level)?.cancel();
  }

  /// 撤掉 [level] 及更浅那些级别的收起
  ///
  /// 指针往更深一层走时用：只撤自己那一级的话，
  /// 父级排的收起到点会把整条链收没
  void _cancelCloseTimersUpTo(int level) {
    for (var target = 1; target <= level; target++) {
      _cancelCloseTimer(target);
    }
  }

  void _cancelAllTimers() {
    for (final timer in _pendingOpen.values) {
      timer.cancel();
    }
    for (final timer in _pendingClose.values) {
      timer.cancel();
    }
    _pendingOpen.clear();
    _pendingClose.clear();
  }

  /// 收掉 [level] 及更深的所有子菜单，并清掉父面板的展开标记
  ///
  /// [onlyTemporary] 为 true 时遇到常驻面板就停手：常驻还挂着，它下面那些也就还有意义
  void _closeSubmenusFrom(int level, {bool onlyTemporary = false}) {
    final session = _active;
    if (session == null) return;
    _cancelOpenTimer(level);
    _cancelCloseTimer(level);
    final parent = _panelAt(level - 1);
    final closing = <_MenuPanel>[];
    for (final panel in session.panels) {
      if (panel.state.level < level) continue;
      if (onlyTemporary && panel.state.sticky) break;
      closing.add(panel);
    }
    if (closing.isEmpty) return;
    if (parent != null && parent.state.activeIndex != null) {
      parent.state.activeIndex = null;
      parent.entry.markNeedsBuild();
    }
    for (final panel in closing) {
      _dismissPanel(session, panel);
    }
    notifyListeners();
  }

  /// 播退场；[animate] 为 false 直接移除
  void _dismissPanel(
    _ContextMenuSession session,
    _MenuPanel panel, {
    bool animate = true,
  }) {
    if (panel.removed) return;
    if (!animate) {
      _removePanel(session, panel);
      return;
    }
    panel.state
      ..visible = false
      // 退场中的面板不再拦点击，免得盖住新菜单的关闭层
      ..barrier = false;
    session.panels.remove(panel);
    if (!session.exiting.contains(panel)) session.exiting.add(panel);
    panel.entry.markNeedsBuild();
  }

  void _handlePanelHidden(_MenuPanel panel) {
    final session = _sessionOf(panel);
    if (session == null) return;
    _removePanel(session, panel);
  }

  _ContextMenuSession? _sessionOf(_MenuPanel panel) {
    if (_active?.panels.contains(panel) ?? false) return _active;
    if (_active?.exiting.contains(panel) ?? false) return _active;
    for (final session in _retiring) {
      if (session.panels.contains(panel) || session.exiting.contains(panel)) {
        return session;
      }
    }
    return null;
  }

  void _removePanel(_ContextMenuSession session, _MenuPanel panel) {
    if (panel.removed) return;
    panel.removed = true;
    panel.entry.remove();
    session.panels.remove(panel);
    session.exiting.remove(panel);
    if (session.panels.isEmpty && session.exiting.isEmpty) {
      session.complete();
      _retiring.remove(session);
    }
  }
}

/// 一条菜单链：根面板加上挂出来的各级子菜单
class _ContextMenuSession {
  _ContextMenuSession({
    required this.overlay,
    required this.delegate,
    required this.style,
  });

  final OverlayState overlay;
  final ContextMenuPositionDelegate delegate;
  final ContextMenuStyle style;

  /// 当前展开的链条，第一个是根面板
  final List<_MenuPanel> panels = [];

  /// 正在播退场、只为动画活着
  final List<_MenuPanel> exiting = [];

  /// 整条链收完（含退场动画）时完成
  final Completer<void> closed = Completer<void>();

  void complete() {
    if (!closed.isCompleted) closed.complete();
  }
}

/// 一个面板实例：状态 + 它在 overlay 里的 OverlayEntry
class _MenuPanel {
  _MenuPanel({required this.state});

  final ContextMenuPanelState state;
  late final OverlayEntry entry;
  bool removed = false;
}
