import 'package:copper_launcher/data/mindustry/mindustry.dart';

/// 键位分组（键位表按这个顺序分组显示）
enum KeybindGroup {
  general('通用'),
  command('指挥'),
  blocks('建筑'),
  view('视角'),
  multiplayer('多人');

  const KeybindGroup(this.title);

  final String title;
}

/// 单条键位：名称 / 中文标题 / 分组 / 默认键
///
/// [name] 就是 settings.bin 里 `keybind-default-keyboard-<name>` 的后缀；
/// [defaultKey] / [defaultKeyMax] 是 arc `KeyCode` 的枚举名（见 `key_code.dart`），
/// 轴键位（[axis]）用 min / max 两个键，其余都是单键
class KeybindSpec {
  const KeybindSpec(
    this.name,
    this.title,
    this.group, {
    this.axis = false,
    required this.defaultKey,
    this.defaultKeyMax,
  });

  final String name;
  final String title;
  final KeybindGroup group;
  final bool axis;
  final String defaultKey;
  final String? defaultKeyMax;
}

/// 按游戏大版本取键位表；不支持的版本（v6 及更早）返回 null
///
/// 键位名与默认值取自各版本本体：v8（v160.7）比 v7（7.0 Build 146）多出
/// 单位指挥 / 姿态与若干视角键，顺序也不同，所以两版各存一份
List<KeybindSpec>? keybindCatalogFor(Mindustry version) {
  final major = version.versionNumber ?? _majorFromRelease(version.releaseInt);
  if (major >= 8) return keybindCatalogV8;
  if (major == 7) return keybindCatalogV7;
  return null;
}

/// 老配置没有大版本号时按 build 号猜：v7 从 136 起，v8 从 154 起
int _majorFromRelease(int release) {
  if (release >= 154) return 8;
  if (release >= 136) return 7;
  return 0;
}

/// v7 键位目录（Mindustry 7.0 Build 146）
const List<KeybindSpec> keybindCatalogV7 = [
  KeybindSpec(
    'move_x',
    '水平移动',
    KeybindGroup.general,
    axis: true,
    defaultKey: 'a',
    defaultKeyMax: 'd',
  ),
  KeybindSpec(
    'move_y',
    '竖直移动',
    KeybindGroup.general,
    axis: true,
    defaultKey: 's',
    defaultKeyMax: 'w',
  ),
  KeybindSpec(
    'mouse_move',
    '单位跟随鼠标',
    KeybindGroup.general,
    defaultKey: 'mouseBack',
  ),
  KeybindSpec(
    'pan',
    '鼠标控制镜头',
    KeybindGroup.general,
    defaultKey: 'mouseForward',
  ),
  KeybindSpec('boost', '启动助推', KeybindGroup.general, defaultKey: 'shiftLeft'),
  KeybindSpec(
    'command_mode',
    '指挥模式',
    KeybindGroup.general,
    defaultKey: 'shiftLeft',
  ),
  KeybindSpec(
    'control',
    '控制单位',
    KeybindGroup.general,
    defaultKey: 'controlLeft',
  ),
  KeybindSpec('respawn', '重生', KeybindGroup.general, defaultKey: 'v'),
  KeybindSpec('select', '选择/射击', KeybindGroup.general, defaultKey: 'mouseLeft'),
  KeybindSpec(
    'deselect',
    '取消选择',
    KeybindGroup.general,
    defaultKey: 'mouseRight',
  ),
  KeybindSpec(
    'break_block',
    '拆除建筑',
    KeybindGroup.general,
    defaultKey: 'mouseRight',
  ),
  KeybindSpec(
    'select_all_units',
    '选择所有单位',
    KeybindGroup.general,
    defaultKey: 'g',
  ),
  KeybindSpec(
    'select_all_unit_factories',
    '选择所有单位工厂',
    KeybindGroup.general,
    defaultKey: 'h',
  ),
  KeybindSpec(
    'pickupCargo',
    '拾取载荷',
    KeybindGroup.general,
    defaultKey: 'leftBracket',
  ),
  KeybindSpec(
    'dropCargo',
    '释放载荷',
    KeybindGroup.general,
    defaultKey: 'rightBracket',
  ),
  KeybindSpec('clear_building', '清除规划', KeybindGroup.general, defaultKey: 'q'),
  KeybindSpec(
    'pause_building',
    '暂停/继续建造',
    KeybindGroup.general,
    defaultKey: 'e',
  ),
  KeybindSpec('rotate', '旋转', KeybindGroup.general, defaultKey: 'scroll'),
  KeybindSpec(
    'rotateplaced',
    '旋转已放置的建筑（长按）',
    KeybindGroup.general,
    defaultKey: 'r',
  ),
  KeybindSpec(
    'diagonal_placement',
    '斜线建造',
    KeybindGroup.general,
    defaultKey: 'controlLeft',
  ),
  KeybindSpec('pick', '选择建筑', KeybindGroup.general, defaultKey: 'mouseMiddle'),
  KeybindSpec('rebuild_select', '重建建筑', KeybindGroup.general, defaultKey: 'b'),
  KeybindSpec(
    'schematic_select',
    '框选建筑',
    KeybindGroup.general,
    defaultKey: 'f',
  ),
  KeybindSpec(
    'schematic_flip_x',
    '水平翻转',
    KeybindGroup.general,
    defaultKey: 'z',
  ),
  KeybindSpec(
    'schematic_flip_y',
    '竖直翻转',
    KeybindGroup.general,
    defaultKey: 'x',
  ),
  KeybindSpec('schematic_menu', '蓝图目录', KeybindGroup.general, defaultKey: 't'),
  KeybindSpec(
    'category_prev',
    '上一分类',
    KeybindGroup.blocks,
    defaultKey: 'comma',
  ),
  KeybindSpec(
    'category_next',
    '下一分类',
    KeybindGroup.blocks,
    defaultKey: 'period',
  ),
  KeybindSpec(
    'block_select_left',
    '建筑朝向向左',
    KeybindGroup.blocks,
    defaultKey: 'left',
  ),
  KeybindSpec(
    'block_select_right',
    '建筑朝向向右',
    KeybindGroup.blocks,
    defaultKey: 'right',
  ),
  KeybindSpec(
    'block_select_up',
    '建筑朝向向上',
    KeybindGroup.blocks,
    defaultKey: 'up',
  ),
  KeybindSpec(
    'block_select_down',
    '建筑朝向向下',
    KeybindGroup.blocks,
    defaultKey: 'down',
  ),
  KeybindSpec(
    'block_select_01',
    '分类/建筑选择 1',
    KeybindGroup.blocks,
    defaultKey: 'num1',
  ),
  KeybindSpec(
    'block_select_02',
    '分类/建筑选择 2',
    KeybindGroup.blocks,
    defaultKey: 'num2',
  ),
  KeybindSpec(
    'block_select_03',
    '分类/建筑选择 3',
    KeybindGroup.blocks,
    defaultKey: 'num3',
  ),
  KeybindSpec(
    'block_select_04',
    '分类/建筑选择 4',
    KeybindGroup.blocks,
    defaultKey: 'num4',
  ),
  KeybindSpec(
    'block_select_05',
    '分类/建筑选择 5',
    KeybindGroup.blocks,
    defaultKey: 'num5',
  ),
  KeybindSpec(
    'block_select_06',
    '分类/建筑选择 6',
    KeybindGroup.blocks,
    defaultKey: 'num6',
  ),
  KeybindSpec(
    'block_select_07',
    '分类/建筑选择 7',
    KeybindGroup.blocks,
    defaultKey: 'num7',
  ),
  KeybindSpec(
    'block_select_08',
    '分类/建筑选择 8',
    KeybindGroup.blocks,
    defaultKey: 'num8',
  ),
  KeybindSpec(
    'block_select_09',
    '分类/建筑选择 9',
    KeybindGroup.blocks,
    defaultKey: 'num9',
  ),
  KeybindSpec(
    'block_select_10',
    '分类/建筑选择 10',
    KeybindGroup.blocks,
    defaultKey: 'num0',
  ),
  KeybindSpec('zoom', '缩放', KeybindGroup.view, defaultKey: 'scroll'),
  KeybindSpec('menu', '菜单', KeybindGroup.view, defaultKey: 'escape'),
  KeybindSpec('fullscreen', '切换全屏', KeybindGroup.view, defaultKey: 'f11'),
  KeybindSpec('pause', '暂停', KeybindGroup.view, defaultKey: 'space'),
  KeybindSpec('minimap', '打开小地图', KeybindGroup.view, defaultKey: 'm'),
  KeybindSpec('research', '打开科技树', KeybindGroup.view, defaultKey: 'j'),
  KeybindSpec('planet_map', '打开行星地图', KeybindGroup.view, defaultKey: 'n'),
  KeybindSpec('block_info', '显示建筑信息', KeybindGroup.view, defaultKey: 'f1'),
  KeybindSpec('toggle_menus', '显示/隐藏UI', KeybindGroup.view, defaultKey: 'c'),
  KeybindSpec('screenshot', '全地图截图', KeybindGroup.view, defaultKey: 'p'),
  KeybindSpec(
    'toggle_power_lines',
    '显示/隐藏电力连接线',
    KeybindGroup.view,
    defaultKey: 'f5',
  ),
  KeybindSpec(
    'toggle_block_status',
    '显示/隐藏建筑状态',
    KeybindGroup.view,
    defaultKey: 'f6',
  ),
  KeybindSpec(
    'player_list',
    '玩家列表',
    KeybindGroup.multiplayer,
    defaultKey: 'tab',
  ),
  KeybindSpec('chat', '聊天', KeybindGroup.multiplayer, defaultKey: 'enter'),
  KeybindSpec(
    'chat_history_prev',
    '聊天记录向前',
    KeybindGroup.multiplayer,
    defaultKey: 'up',
  ),
  KeybindSpec(
    'chat_history_next',
    '聊天记录向后',
    KeybindGroup.multiplayer,
    defaultKey: 'down',
  ),
  KeybindSpec(
    'chat_scroll',
    '聊天记录滚动',
    KeybindGroup.multiplayer,
    defaultKey: 'scroll',
  ),
  KeybindSpec(
    'chat_mode',
    '切换聊天模式',
    KeybindGroup.multiplayer,
    defaultKey: 'tab',
  ),
  KeybindSpec('console', '控制台', KeybindGroup.multiplayer, defaultKey: 'f8'),
];

/// v8 键位目录（Mindustry v160.7）
const List<KeybindSpec> keybindCatalogV8 = [
  KeybindSpec(
    'move_x',
    '水平移动',
    KeybindGroup.general,
    axis: true,
    defaultKey: 'a',
    defaultKeyMax: 'd',
  ),
  KeybindSpec(
    'move_y',
    '竖直移动',
    KeybindGroup.general,
    axis: true,
    defaultKey: 's',
    defaultKeyMax: 'w',
  ),
  KeybindSpec(
    'mouse_move',
    '单位跟随鼠标',
    KeybindGroup.general,
    defaultKey: 'mouseBack',
  ),
  KeybindSpec(
    'pan',
    '鼠标控制镜头',
    KeybindGroup.general,
    defaultKey: 'mouseForward',
  ),
  KeybindSpec('boost', '启动助推', KeybindGroup.general, defaultKey: 'shiftLeft'),
  KeybindSpec('respawn', '重生', KeybindGroup.general, defaultKey: 'v'),
  KeybindSpec(
    'control',
    '控制单位',
    KeybindGroup.general,
    defaultKey: 'controlLeft',
  ),
  KeybindSpec('select', '选择/射击', KeybindGroup.general, defaultKey: 'mouseLeft'),
  KeybindSpec(
    'deselect',
    '取消选择',
    KeybindGroup.general,
    defaultKey: 'mouseRight',
  ),
  KeybindSpec(
    'break_block',
    '拆除建筑',
    KeybindGroup.general,
    defaultKey: 'mouseRight',
  ),
  KeybindSpec(
    'pickupCargo',
    '拾取载荷',
    KeybindGroup.general,
    defaultKey: 'leftBracket',
  ),
  KeybindSpec(
    'dropCargo',
    '释放载荷',
    KeybindGroup.general,
    defaultKey: 'rightBracket',
  ),
  KeybindSpec('clear_building', '清除规划', KeybindGroup.general, defaultKey: 'q'),
  KeybindSpec(
    'pause_building',
    '暂停/继续建造',
    KeybindGroup.general,
    defaultKey: 'e',
  ),
  KeybindSpec('rotate', '旋转', KeybindGroup.general, defaultKey: 'scroll'),
  KeybindSpec(
    'rotateplaced',
    '旋转已放置的建筑（长按）',
    KeybindGroup.general,
    defaultKey: 'r',
  ),
  KeybindSpec(
    'diagonal_placement',
    '斜线建造',
    KeybindGroup.general,
    defaultKey: 'controlLeft',
  ),
  KeybindSpec('pick', '选择建筑', KeybindGroup.general, defaultKey: 'mouseMiddle'),
  KeybindSpec('ping', '标记位置', KeybindGroup.general, defaultKey: 'p'),
  KeybindSpec('rebuild_select', '重建区域', KeybindGroup.general, defaultKey: 'b'),
  KeybindSpec(
    'schematic_select',
    '选择区域',
    KeybindGroup.general,
    defaultKey: 'f',
  ),
  KeybindSpec(
    'schematic_flip_x',
    '水平翻转',
    KeybindGroup.general,
    defaultKey: 'z',
  ),
  KeybindSpec(
    'schematic_flip_y',
    '竖直翻转',
    KeybindGroup.general,
    defaultKey: 'x',
  ),
  KeybindSpec('schematic_menu', '蓝图目录', KeybindGroup.general, defaultKey: 't'),
  KeybindSpec(
    'command_mode',
    '指挥模式',
    KeybindGroup.command,
    defaultKey: 'shiftLeft',
  ),
  KeybindSpec(
    'command_queue',
    '设置路径点',
    KeybindGroup.command,
    defaultKey: 'mouseMiddle',
  ),
  KeybindSpec(
    'create_control_group',
    '创建操控队伍',
    KeybindGroup.command,
    defaultKey: 'controlLeft',
  ),
  KeybindSpec(
    'select_all_units',
    '选择所有单位',
    KeybindGroup.command,
    defaultKey: 'g',
  ),
  KeybindSpec(
    'select_all_unit_factories',
    '选择所有单位工厂',
    KeybindGroup.command,
    defaultKey: 'h',
  ),
  KeybindSpec(
    'select_all_unit_transport',
    '选择所有运输单位',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'select_across_screen',
    '全屏选择（按住）',
    KeybindGroup.command,
    defaultKey: 'altLeft',
  ),
  KeybindSpec(
    'cancel_orders',
    '取消指令',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_stance_hold_fire',
    '姿态：停火',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_stance_pursue_target',
    '姿态：追击',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_stance_patrol',
    '姿态：巡逻',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_stance_ram',
    '姿态：突进',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_stance_boost',
    '姿态：助推',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_stance_hold_position',
    '姿态：驻守',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_move',
    '单位命令：移动',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_repair',
    '单位命令：修复',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_rebuild',
    '单位命令：重建',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_assist',
    '单位命令：协助建造',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_mine',
    '单位命令：采矿',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_enter_payload',
    '单位命令：进入载荷',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_load_units',
    '单位命令：拾取单位',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_load_blocks',
    '单位命令：拾取建筑',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_unload_payload',
    '单位命令：卸载载荷',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'unit_command_loop_payload',
    '单位命令：往返搬运单位',
    KeybindGroup.command,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'category_prev',
    '上一分类',
    KeybindGroup.blocks,
    defaultKey: 'comma',
  ),
  KeybindSpec(
    'category_next',
    '下一分类',
    KeybindGroup.blocks,
    defaultKey: 'period',
  ),
  KeybindSpec(
    'block_select_left',
    '建筑朝向向左',
    KeybindGroup.blocks,
    defaultKey: 'left',
  ),
  KeybindSpec(
    'block_select_right',
    '建筑朝向向右',
    KeybindGroup.blocks,
    defaultKey: 'right',
  ),
  KeybindSpec(
    'block_select_up',
    '建筑朝向向上',
    KeybindGroup.blocks,
    defaultKey: 'up',
  ),
  KeybindSpec(
    'block_select_down',
    '建筑朝向向下',
    KeybindGroup.blocks,
    defaultKey: 'down',
  ),
  KeybindSpec(
    'block_select_01',
    '分类/建筑选择 1',
    KeybindGroup.blocks,
    defaultKey: 'num1',
  ),
  KeybindSpec(
    'block_select_02',
    '分类/建筑选择 2',
    KeybindGroup.blocks,
    defaultKey: 'num2',
  ),
  KeybindSpec(
    'block_select_03',
    '分类/建筑选择 3',
    KeybindGroup.blocks,
    defaultKey: 'num3',
  ),
  KeybindSpec(
    'block_select_04',
    '分类/建筑选择 4',
    KeybindGroup.blocks,
    defaultKey: 'num4',
  ),
  KeybindSpec(
    'block_select_05',
    '分类/建筑选择 5',
    KeybindGroup.blocks,
    defaultKey: 'num5',
  ),
  KeybindSpec(
    'block_select_06',
    '分类/建筑选择 6',
    KeybindGroup.blocks,
    defaultKey: 'num6',
  ),
  KeybindSpec(
    'block_select_07',
    '分类/建筑选择 7',
    KeybindGroup.blocks,
    defaultKey: 'num7',
  ),
  KeybindSpec(
    'block_select_08',
    '分类/建筑选择 8',
    KeybindGroup.blocks,
    defaultKey: 'num8',
  ),
  KeybindSpec(
    'block_select_09',
    '分类/建筑选择 9',
    KeybindGroup.blocks,
    defaultKey: 'num9',
  ),
  KeybindSpec(
    'block_select_10',
    '分类/建筑选择 10',
    KeybindGroup.blocks,
    defaultKey: 'num0',
  ),
  KeybindSpec('zoom', '缩放', KeybindGroup.view, defaultKey: 'scroll'),
  KeybindSpec(
    'detach_camera',
    '切换自由视角',
    KeybindGroup.view,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'teleport_cursor',
    '传送到指针位置（沙盒模式）',
    KeybindGroup.view,
    defaultKey: 'unset',
  ),
  KeybindSpec('menu', '菜单', KeybindGroup.view, defaultKey: 'escape'),
  KeybindSpec('fullscreen', '切换全屏', KeybindGroup.view, defaultKey: 'f11'),
  KeybindSpec('pause', '暂停', KeybindGroup.view, defaultKey: 'space'),
  KeybindSpec('skip_wave', '跳波', KeybindGroup.view, defaultKey: 'unset'),
  KeybindSpec('minimap', '打开小地图', KeybindGroup.view, defaultKey: 'm'),
  KeybindSpec('research', '打开科技树', KeybindGroup.view, defaultKey: 'j'),
  KeybindSpec('planet_map', '打开行星地图', KeybindGroup.view, defaultKey: 'n'),
  KeybindSpec('block_info', '显示建筑信息', KeybindGroup.view, defaultKey: 'f1'),
  KeybindSpec('toggle_menus', '显示/隐藏界面', KeybindGroup.view, defaultKey: 'c'),
  KeybindSpec('screenshot', '全地图截图', KeybindGroup.view, defaultKey: 'f12'),
  KeybindSpec(
    'toggle_power_lines',
    '显示/隐藏电力连接线',
    KeybindGroup.view,
    defaultKey: 'f5',
  ),
  KeybindSpec(
    'toggle_block_status',
    '显示/隐藏建筑状态',
    KeybindGroup.view,
    defaultKey: 'f6',
  ),
  KeybindSpec(
    'player_list',
    '玩家列表',
    KeybindGroup.multiplayer,
    defaultKey: 'tab',
  ),
  KeybindSpec('chat', '聊天', KeybindGroup.multiplayer, defaultKey: 'enter'),
  KeybindSpec(
    'chat_history_prev',
    '聊天记录向前',
    KeybindGroup.multiplayer,
    defaultKey: 'up',
  ),
  KeybindSpec(
    'chat_history_next',
    '聊天记录向后',
    KeybindGroup.multiplayer,
    defaultKey: 'down',
  ),
  KeybindSpec(
    'chat_scroll',
    '聊天记录滚动',
    KeybindGroup.multiplayer,
    defaultKey: 'scroll',
  ),
  KeybindSpec(
    'chat_mode',
    '切换聊天模式',
    KeybindGroup.multiplayer,
    defaultKey: 'tab',
  ),
  KeybindSpec('console', '控制台', KeybindGroup.multiplayer, defaultKey: 'f8'),
  KeybindSpec(
    'debug_hitboxes',
    '切换调试碰撞箱',
    KeybindGroup.multiplayer,
    defaultKey: 'unset',
  ),
  KeybindSpec(
    'performance_metrics',
    '切换性能表现显示',
    KeybindGroup.multiplayer,
    defaultKey: 'unset',
  ),
];
