import 'dart:io';
import 'dart:typed_data';

import 'package:copperlauncher_main/util/io/mindustry_save_file/settings_bin_codec.dart';
import 'package:json_annotation/json_annotation.dart';

part 'mindustry_settings.g.dart';

/// Mindustry settings.bin 数据类。
///
/// 提供对 [settings.bin] 文件的读写、键值对存取、
/// 以及常用设置项的成员变量直接访问。
///
/// **成员命名**: Dart 驼峰（如 [uiScale]），内部 `_data` 键保持 Mindustry 原始键名（如 `"uiscale"`）。
///
/// 用法：
/// ```dart
/// // 从文件加载
/// final settings = MindustrySettings.fromFile('path/to/settings.bin');
/// print(settings.uiScale);    // 100
///
/// // 修改并保存
/// settings.uiScale = 150;
/// settings.save();
///
/// // 使用 Patch 批量修改（null 保留原值）
/// settings.applyPatch(MindustrySettingsPatch()
///   ..uiScale = 150
///   ..fullscreen = true,
/// );
///
/// // 创建默认设置
/// final defaults = MindustrySettings.defaults();
/// defaults.saveTo('path/to/settings.bin');
/// ```
class MindustrySettings {
  /// 内部存储所有键值对。键名为 Mindustry 原始格式（如 `"uiscale"`）。
  final Map<String, dynamic> _data;

  /// 来源文件路径（用于 [save]）。
  String? _filePath;

  // ─────────────────────────────────────────
  // 构造函数
  // ─────────────────────────────────────────

  /// 从 Map 构建（内部使用）。
  MindustrySettings._(this._data, [this._filePath]);

  /// 从 [settings.bin] 文件路径加载。
  ///
  /// 如果文件不存在或读取失败，返回空实例（getter 使用默认值）。
  factory MindustrySettings.fromFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return MindustrySettings._({}, path);
      }
      final bytes = file.readAsBytesSync();
      return MindustrySettings.fromBytes(bytes, path);
    } catch (_) {
      return MindustrySettings._({}, path);
    }
  }

  /// 创建具有所有默认值的设置实例。
  factory MindustrySettings.defaults() {
    return MindustrySettings._({
      // ── 游戏 ──
      'saveinterval': 60,
      'autotarget': true,
      'keyboard': false,
      'crashreport': true,
      'communityservers': true,
      'savecreate': true,
      'blockreplace': true,
      'conveyorpathfinding': true,
      'hints': true,
      'logichints': true,
      'backgroundpause': true,
      'buildautopause': false,
      'distinctcontrolgroups': true,
      'doubletapmine': false,
      'commandmodehold': true,
      'modcrashdisable': true,
      'playerlimit': 16,
      'steampublichost': false,
      'console': false,

      // ── 图形 ──
      'uiscale': 100,
      'uiscalechanged': false,
      'screenshake': 4,
      'bloomintensity': 6,
      'bloomblur': 2,
      'fpscap': 240,
      'chatopacity': 100,
      'lasersopacity': 100,
      'preferredlaseropacity': 100,
      'unitlaseropacity': 100,
      'bridgeopacity': 100,
      'maxmagnificationmultiplierpercent': 100,
      'maxzoomingamemultiplier': 1.0,
      'minmagnificationmultiplierpercent': 100,
      'minzoomingamemultiplier': 1.0,
      'vsync': true,
      'fullscreen': false,
      'borderlesswindow': false,
      'landscape': false,
      'effects': true,
      'atmosphere': true,
      'drawlight': true,
      'destroyedblocks': true,
      'blockstatus': false,
      'playerchat': true,
      'coreitems': true,
      'minimap': true,
      'smoothcamera': true,
      'detach-camera': false,
      'position': false,
      'mouseposition': false,
      'fps': false,
      'playerindicators': true,
      'indicators': true,
      'showweather': true,
      'animatedwater': true,
      'animatedshields': true,
      'bloom': true,
      'pixelate': false,
      'linear': true,
      'skipcoreanimation': false,
      'hidedisplays': false,
      'macnotch': false,
      'swapdiagonal': false,

      // ── 音频 ──
      'alwaysmusic': false,
      'musicvol': 100,
      'sfxvol': 100,
      'ambientvol': 100,

      // ── 系统 ──
      'locale': 'default',
      'blocksync': true,
      'lastBuild': 0,
      'lastBuildString': '',
    });
  }

  // ─────────────────────────────────────────
  // 原始数据访问
  // ─────────────────────────────────────────

  /// 获取内部 Map（只读参考）。键名为 Mindustry 原始格式。
  Map<String, dynamic> get data => _data;

  /// 获取所有键。
  Iterable<String> get keys => _data.keys;

  /// 按键获取值。
  dynamic operator [](String key) => _data[key];

  /// 按键设置值。
  void operator []=(String key, dynamic value) => _data[key] = value;

  /// 判断键是否存在。
  bool containsKey(String key) => _data.containsKey(key);

  /// 删除键。
  void remove(String key) => _data.remove(key);

  // ─────────────────────────────────────────
  // 持久化
  // ─────────────────────────────────────────

  /// 保存到原始来源路径。
  ///
  /// 若未设置路径（非文件加载），抛出 [StateError]。
  void save() {
    if (_filePath == null) {
      throw StateError('未设置文件路径，请使用 saveTo(path)');
    }
    saveTo(_filePath!);
  }

  /// 保存到指定路径。
  void saveTo(String path) {
    _filePath = path;
    final bytes = SettingsBinCodec.encode(_data);
    final file = File(path);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    File(path).writeAsBytesSync(bytes);
  }

  /// 异步保存到原始来源路径。
  Future<void> saveAsync() async {
    if (_filePath == null) {
      throw StateError('未设置文件路径，请使用 saveToAsync(path)');
    }
    await saveToAsync(_filePath!);
  }

  /// 异步保存到指定路径。
  Future<void> saveToAsync(String path) async {
    _filePath = path;
    final bytes = SettingsBinCodec.encode(_data);
    final file = File(path);
    if (!(await file.exists())) {
      await file.create(recursive: true);
    }
    await File(path).writeAsBytes(bytes);
  }

  // ─────────────────────────────────────────
  // 便捷工厂
  // ─────────────────────────────────────────

  /// 从 Uint8List 字节加载。
  factory MindustrySettings.fromBytes(Uint8List bytes, [String? path]) {
    final decoded = SettingsBinCodec.decode(bytes);
    return MindustrySettings._(decoded, path);
  }

  /// 复制当前实例。
  MindustrySettings copy() {
    return MindustrySettings._(Map<String, dynamic>.from(_data), _filePath);
  }

  /// 使用 [patch] 覆盖设置。仅替换 patch 中非 null 的字段。
  ///
  /// ```dart
  /// settings.applyPatch(MindustrySettingsPatch()
  ///   ..fullscreen = true
  ///   ..uiScale = 150,
  /// );
  /// ```
  void applyPatch(MindustrySettingsPatch patch) {
    patch._applyTo(this);
  }

  // ═══════════════════════════════════════════
  // 常用设置成员变量
  // ═══════════════════════════════════════════

  // ── 游戏设置 ──

  /// 自动保存间隔
  int get saveInterval => _data['saveinterval'] as int? ?? 60;

  set saveInterval(int v) => _data['saveinterval'] = v;

  /// 移动端：自动瞄准。
  bool get autoTarget => _data['autotarget'] as bool? ?? true;

  set autoTarget(bool v) => _data['autotarget'] = v;

  /// 移动端：键盘模式。
  bool get keyboard => _data['keyboard'] as bool? ?? false;

  set keyboard(bool v) => _data['keyboard'] = v;

  /// 崩溃报告。
  bool get crashReport => _data['crashreport'] as bool? ?? true;

  set crashReport(bool v) => _data['crashreport'] = v;

  /// 社区服务器列表。
  bool get communityServers => _data['communityservers'] as bool? ?? true;

  set communityServers(bool v) => _data['communityservers'] = v;

  /// 创建保存。
  bool get saveCreate => _data['savecreate'] as bool? ?? true;

  set saveCreate(bool v) => _data['savecreate'] = v;

  /// 方块替换。
  bool get blockReplace => _data['blockreplace'] as bool? ?? true;

  set blockReplace(bool v) => _data['blockreplace'] = v;

  /// 传送带寻路。
  bool get conveyorPathfinding => _data['conveyorpathfinding'] as bool? ?? true;

  set conveyorPathfinding(bool v) => _data['conveyorpathfinding'] = v;

  /// 提示。
  bool get hints => _data['hints'] as bool? ?? true;

  set hints(bool v) => _data['hints'] = v;

  /// 逻辑提示。
  bool get logicHints => _data['logichints'] as bool? ?? true;

  set logicHints(bool v) => _data['logichints'] = v;

  /// 后台暂停。
  bool get backgroundPause => _data['backgroundpause'] as bool? ?? true;

  set backgroundPause(bool v) => _data['backgroundpause'] = v;

  /// 建造自动暂停。
  bool get buildAutoPause => _data['buildautopause'] as bool? ?? false;

  set buildAutoPause(bool v) => _data['buildautopause'] = v;

  /// 分离控制组。
  bool get distinctControlGroups =>
      _data['distinctcontrolgroups'] as bool? ?? true;

  set distinctControlGroups(bool v) => _data['distinctcontrolgroups'] = v;

  /// 双击挖矿。
  bool get doubleTapMine => _data['doubletapmine'] as bool? ?? false;

  set doubleTapMine(bool v) => _data['doubletapmine'] = v;

  /// 长按指挥模式。
  bool get commandModeHold => _data['commandmodehold'] as bool? ?? true;

  set commandModeHold(bool v) => _data['commandmodehold'] = v;

  /// Mod 崩溃时禁用。
  bool get modCrashDisable => _data['modcrashdisable'] as bool? ?? true;

  set modCrashDisable(bool v) => _data['modcrashdisable'] = v;

  /// Steam：玩家上限 (2-32)。
  int get playerLimit => _data['playerlimit'] as int? ?? 16;

  set playerLimit(int v) => _data['playerlimit'] = v;

  /// Steam：公开主机。
  bool get steamPublicHost => _data['steampublichost'] as bool? ?? false;

  set steamPublicHost(bool v) => _data['steampublichost'] = v;

  /// 控制台。
  bool get console => _data['console'] as bool? ?? false;

  set console(bool v) => _data['console'] = v;

  // ── 图形设置 ──

  /// UI 缩放百分比 (25-300)。
  int get uiScale => _data['uiscale'] as int? ?? 100;

  set uiScale(int v) => _data['uiscale'] = v;

  /// UI 缩放是否被手动改变。
  bool get uiScaleChanged => _data['uiscalechanged'] as bool? ?? false;

  set uiScaleChanged(bool v) => _data['uiscalechanged'] = v;

  /// 屏幕震动 (0-8) x 0.25 %
  int get screenShake => _data['screenshake'] as int? ?? 4;

  set screenShake(int v) => _data['screenshake'] = v;

  /// 泛光强度 (0-16) x 25%
  int get bloomIntensity => _data['bloomintensity'] as int? ?? 6;

  set bloomIntensity(int v) => _data['bloomintensity'] = v;

  /// 泛光模糊 (1-16)。
  int get bloomBlur => _data['bloomblur'] as int? ?? 2;

  set bloomBlur(int v) => _data['bloomblur'] = v;

  /// FPS 上限 (10-245, >240=无限制)
  int get fpsCap => _data['fpscap'] as int? ?? 240;

  set fpsCap(int v) => _data['fpscap'] = v;

  /// 聊天不透明度 (0-100)。
  int get chatOpacity => _data['chatopacity'] as int? ?? 100;

  set chatOpacity(int v) => _data['chatopacity'] = v;

  /// 激光不透明度 (0-100)
  int get lasersOpacity => _data['lasersopacity'] as int? ?? 100;

  set lasersOpacity(int v) => _data['lasersopacity'] = v;

  /// 用户偏好激光不透明度
  int get preferredLaserOpacity =>
      _data['preferredlaseropacity'] as int? ?? 100;

  set preferredLaserOpacity(int v) => _data['preferredlaseropacity'] = v;

  /// 单位激光不透明度 (0-100)
  int get unitLaserOpacity => _data['unitlaseropacity'] as int? ?? 100;

  set unitLaserOpacity(int v) => _data['unitlaseropacity'] = v;

  /// 桥梁不透明度 (0-100)。
  int get bridgeOpacity => _data['bridgeopacity'] as int? ?? 100;

  set bridgeOpacity(int v) => _data['bridgeopacity'] = v;

  /// 最大缩放倍数百分比 (100-200)
  int get maxMagnificationMultiplierPercent =>
      _data['maxmagnificationmultiplierpercent'] as int? ?? 100;

  set maxMagnificationMultiplierPercent(int v) =>
      _data['maxmagnificationmultiplierpercent'] = v;

  /// 最大缩放倍数
  double get maxZoomInGameMultiplier =>
      (_data['maxzoomingamemultiplier'] as num?)?.toDouble() ?? 1.0;

  set maxZoomInGameMultiplier(double v) => _data['maxzoomingamemultiplier'] = v;

  /// 最小缩放倍数百分比 (100-300)
  int get minMagnificationMultiplierPercent =>
      _data['minmagnificationmultiplierpercent'] as int? ?? 100;

  set minMagnificationMultiplierPercent(int v) =>
      _data['minmagnificationmultiplierpercent'] = v;

  /// 最小缩放倍数
  double get minZoomInGameMultiplier =>
      (_data['minzoomingamemultiplier'] as num?)?.toDouble() ?? 1.0;

  set minZoomInGameMultiplier(double v) => _data['minzoomingamemultiplier'] = v;

  /// 垂直同步
  bool get vsync => _data['vsync'] as bool? ?? true;

  set vsync(bool v) => _data['vsync'] = v;

  /// 全屏
  bool get fullscreen => _data['fullscreen'] as bool? ?? false;

  set fullscreen(bool v) => _data['fullscreen'] = v;

  /// 无边框窗口
  bool get borderlessWindow => _data['borderlesswindow'] as bool? ?? false;

  set borderlessWindow(bool v) => _data['borderlesswindow'] = v;

  /// 强制横屏（移动端）
  bool get landscape => _data['landscape'] as bool? ?? false;

  set landscape(bool v) => _data['landscape'] = v;

  /// 特效
  bool get effects => _data['effects'] as bool? ?? true;

  set effects(bool v) => _data['effects'] = v;

  /// 大气效果
  bool get atmosphere => _data['atmosphere'] as bool? ?? true;

  set atmosphere(bool v) => _data['atmosphere'] = v;

  /// 光照渲染。
  bool get drawLight => _data['drawlight'] as bool? ?? true;

  set drawLight(bool v) => _data['drawlight'] = v;

  /// 方块残骸。
  bool get destroyedBlocks => _data['destroyedblocks'] as bool? ?? true;

  set destroyedBlocks(bool v) => _data['destroyedblocks'] = v;

  /// 方块状态显示。
  bool get blockStatus => _data['blockstatus'] as bool? ?? false;

  set blockStatus(bool v) => _data['blockstatus'] = v;

  /// 玩家聊天。
  bool get playerChat => _data['playerchat'] as bool? ?? true;

  set playerChat(bool v) => _data['playerchat'] = v;

  /// 核心物品显示。
  bool get coreItems => _data['coreitems'] as bool? ?? true;

  set coreItems(bool v) => _data['coreitems'] = v;

  /// 小地图。
  bool get minimap => _data['minimap'] as bool? ?? true;

  set minimap(bool v) => _data['minimap'] = v;

  /// 平滑镜头。
  bool get smoothCamera => _data['smoothcamera'] as bool? ?? true;

  set smoothCamera(bool v) => _data['smoothcamera'] = v;

  /// 分离镜头。
  bool get detachCamera => _data['detach-camera'] as bool? ?? false;

  set detachCamera(bool v) => _data['detach-camera'] = v;

  /// 坐标显示。
  bool get position => _data['position'] as bool? ?? false;

  set position(bool v) => _data['position'] = v;

  /// 鼠标坐标。
  bool get mousePosition => _data['mouseposition'] as bool? ?? false;

  set mousePosition(bool v) => _data['mouseposition'] = v;

  /// FPS 显示。
  bool get fps => _data['fps'] as bool? ?? false;

  set fps(bool v) => _data['fps'] = v;

  /// 玩家指示器。
  bool get playerIndicators => _data['playerindicators'] as bool? ?? true;

  set playerIndicators(bool v) => _data['playerindicators'] = v;

  /// 指示器。
  bool get indicators => _data['indicators'] as bool? ?? true;

  set indicators(bool v) => _data['indicators'] = v;

  /// 天气效果。
  bool get showWeather => _data['showweather'] as bool? ?? true;

  set showWeather(bool v) => _data['showweather'] = v;

  /// 动态水面。
  bool get animatedWater => _data['animatedwater'] as bool? ?? true;

  set animatedWater(bool v) => _data['animatedwater'] = v;

  /// 动态护盾。
  bool get animatedShields => _data['animatedshields'] as bool? ?? true;

  set animatedShields(bool v) => _data['animatedshields'] = v;

  /// 泛光效果。
  bool get bloom => _data['bloom'] as bool? ?? true;

  set bloom(bool v) => _data['bloom'] = v;

  /// 像素化。
  bool get pixelate => _data['pixelate'] as bool? ?? false;

  set pixelate(bool v) => _data['pixelate'] = v;

  /// 线性过滤。
  bool get linear => _data['linear'] as bool? ?? true;

  set linear(bool v) => _data['linear'] = v;

  /// 跳过核心动画。
  bool get skipCoreAnimation => _data['skipcoreanimation'] as bool? ?? false;

  set skipCoreAnimation(bool v) => _data['skipcoreanimation'] = v;

  /// 隐藏显示屏。
  bool get hideDisplays => _data['hidedisplays'] as bool? ?? false;

  set hideDisplays(bool v) => _data['hidedisplays'] = v;

  /// Mac 刘海屏适配。
  bool get macNotch => _data['macnotch'] as bool? ?? false;

  set macNotch(bool v) => _data['macnotch'] = v;

  /// 对角交换。
  bool get swapDiagonal => _data['swapdiagonal'] as bool? ?? false;

  set swapDiagonal(bool v) => _data['swapdiagonal'] = v;

  // ── 音频设置 ──

  /// 始终播放音乐。
  bool get alwaysMusic => _data['alwaysmusic'] as bool? ?? false;

  set alwaysMusic(bool v) => _data['alwaysmusic'] = v;

  /// 音乐音量 (0-100)。
  int get musicVol => _data['musicvol'] as int? ?? 100;

  set musicVol(int v) => _data['musicvol'] = v;

  /// 音效音量 (0-100)。
  int get sfxVol => _data['sfxvol'] as int? ?? 100;

  set sfxVol(int v) => _data['sfxvol'] = v;

  /// 环境音量 (0-100)。
  int get ambientVol => _data['ambientvol'] as int? ?? 100;

  set ambientVol(int v) => _data['ambientvol'] = v;

  // ── 系统设置 ──

  /// 语言。
  String get locale => _data['locale'] as String? ?? 'default';

  set locale(String v) => _data['locale'] = v;

  /// 方块同步。
  bool get blockSync => _data['blocksync'] as bool? ?? true;

  set blockSync(bool v) => _data['blocksync'] = v;

  /// 上次构建号。
  int get lastBuild => _data['lastBuild'] as int? ?? 0;

  set lastBuild(int v) => _data['lastBuild'] = v;

  /// 上次构建版本字符串。
  String get lastBuildString => _data['lastBuildString'] as String? ?? '';

  set lastBuildString(String v) => _data['lastBuildString'] = v;

  /// 解锁数据（可能为 UBJson Map）。
  dynamic get unlocks => _data['unlocks'];

  set unlocks(dynamic v) => _data['unlocks'] = v;

  //
  // /// 用户服务 ID。
  // String? get usid => _data['usid'] as String?;
  // set usid(String? v) => _data['usid'] = v;
  //
  // /// 用户 UUID。
  // String? get uuid => _data['uuid'] as String?;
  // set uuid(String? v) => _data['uuid'] = v;

  // ─────────────────────────────────────────
  // 辅助方法
  // ─────────────────────────────────────────

  /// 获取布尔设置。
  bool getBool(String key, [bool orDefault = false]) =>
      _data[key] as bool? ?? orDefault;

  /// 获取整数设置。
  int getInt(String key, [int orDefault = 0]) =>
      _data[key] as int? ?? orDefault;

  /// 获取浮点设置。
  double getDouble(String key, [double orDefault = 0.0]) {
    final v = _data[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return orDefault;
  }

  /// 获取字符串设置。
  String getString(String key, [String orDefault = '']) =>
      _data[key] as String? ?? orDefault;

  /// 设置值。
  void set(String key, dynamic value) => _data[key] = value;

  /// 将未知键保留但同步默认值到已知键。
  ///
  /// 这对加载旧版或损坏的 settings.bin 很有用：
  /// 保留用户数据中未知键不变，同时为缺失的已知键填充默认值。
  void ensureDefaults() {
    final defaults = MindustrySettings.defaults()._data;
    for (final entry in defaults.entries) {
      _data.putIfAbsent(entry.key, () => entry.value);
    }
  }

  @override
  String toString() {
    final sb = StringBuffer('MindustrySettings(${_data.length} keys)');
    if (_filePath != null) {
      sb.write(' [$_filePath]');
    }
    return sb.toString();
  }
}

// ═══════════════════════════════════════════
// 设置补丁类
// ═══════════════════════════════════════════

/// 用于批量修改 [MindustrySettings] 的补丁。
///
/// 所有字段可为 null。null 表示"不修改"。
/// 仅非 null 字段会被应用到目标 [MindustrySettings]。
///
/// 支持通过 [MindustrySettingsPatch.fromJson] 从 JSON 反序列化，
/// 也支持 [toJson] 序列化回 JSON（仅序列化非 null 字段）。
///
/// 用法：
/// ```dart
/// // 链式调用覆盖显示设置
/// settings.applyPatch(MindustrySettingsPatch()
///   ..fullscreen = true
///   ..fpsCap = 144
///   ..uiScale = 125
///   ..musicVol = 0,
/// );
///
/// // 从 JSON 反序列化
/// final patch = MindustrySettingsPatch.fromJson({
///   'fullscreen': true,
///   'fpsCap': 144,
/// });
/// ```
@JsonSerializable()
class MindustrySettingsPatch {
  // ── 游戏 ──

  /// 自动保存间隔（秒）
  @JsonKey(name: 'saveInterval')
  int? saveInterval;

  /// 移动端：自动瞄准
  @JsonKey(name: 'autoTarget')
  bool? autoTarget;

  /// 移动端：键盘模式。
  @JsonKey(name: 'keyboard')
  bool? keyboard;

  /// 发送崩溃报告。
  @JsonKey(name: 'crashReport')
  bool? crashReport;

  /// 显示社区服务器列表。
  @JsonKey(name: 'communityServers')
  bool? communityServers;

  /// 创建保存。
  @JsonKey(name: 'saveCreate')
  bool? saveCreate;

  /// 方块替换。
  @JsonKey(name: 'blockReplace')
  bool? blockReplace;

  /// 传送带寻路。
  @JsonKey(name: 'conveyorPathfinding')
  bool? conveyorPathfinding;

  /// 游戏内提示。
  @JsonKey(name: 'hints')
  bool? hints;

  /// 逻辑处理器提示。
  @JsonKey(name: 'logicHints')
  bool? logicHints;

  /// 窗口失焦时暂停游戏。
  @JsonKey(name: 'backgroundPause')
  bool? backgroundPause;

  /// 进入建造模式时自动暂停。
  @JsonKey(name: 'buildAutoPause')
  bool? buildAutoPause;

  /// 分离控制组（移动端）。
  @JsonKey(name: 'distinctControlGroups')
  bool? distinctControlGroups;

  /// 双击挖矿（移动端）。
  @JsonKey(name: 'doubleTapMine')
  bool? doubleTapMine;

  /// 长按进入指挥模式。
  @JsonKey(name: 'commandModeHold')
  bool? commandModeHold;

  /// Mod 引发崩溃时自动禁用。
  @JsonKey(name: 'modCrashDisable')
  bool? modCrashDisable;

  /// Steam：联机玩家上限 (2-32)。
  @JsonKey(name: 'playerLimit')
  int? playerLimit;

  /// Steam：公开主机。
  @JsonKey(name: 'steamPublicHost')
  bool? steamPublicHost;

  /// 开启内置控制台。
  @JsonKey(name: 'console')
  bool? console;

  // ── 图形 ──

  /// UI 缩放百分比 (25-300)。
  @JsonKey(name: 'uiScale')
  int? uiScale;

  /// UI 缩放是否被手动改变过。
  @JsonKey(name: 'uiScaleChanged')
  bool? uiScaleChanged;

  /// 屏幕震动强度 (0-8)。
  @JsonKey(name: 'screenShake')
  int? screenShake;

  /// 泛光强度 (0-16)。
  @JsonKey(name: 'bloomIntensity')
  int? bloomIntensity;

  /// 泛光模糊程度 (1-16)。
  @JsonKey(name: 'bloomBlur')
  int? bloomBlur;

  /// FPS 上限 (10-245, >=246 无限制)。
  @JsonKey(name: 'fpsCap')
  int? fpsCap;

  /// 聊天框不透明度 (0-100)。
  @JsonKey(name: 'chatOpacity')
  int? chatOpacity;

  /// 激光不透明度 (0-100)。
  @JsonKey(name: 'lasersOpacity')
  int? lasersOpacity;

  /// 用户设定的激光不透明度偏好。
  @JsonKey(name: 'preferredLaserOpacity')
  int? preferredLaserOpacity;

  /// 单位激光不透明度 (0-100)。
  @JsonKey(name: 'unitLaserOpacity')
  int? unitLaserOpacity;

  /// 桥梁不透明度 (0-100)。
  @JsonKey(name: 'bridgeOpacity')
  int? bridgeOpacity;

  /// 最大缩放倍数百分比 (100-200)。
  @JsonKey(name: 'maxMagnificationMultiplierPercent')
  int? maxMagnificationMultiplierPercent;

  /// 游戏内最大缩放倍数。
  @JsonKey(name: 'maxZoomInGameMultiplier')
  double? maxZoomInGameMultiplier;

  /// 最小缩放倍数百分比 (100-300)。
  @JsonKey(name: 'minMagnificationMultiplierPercent')
  int? minMagnificationMultiplierPercent;

  /// 游戏内最小缩放倍数。
  @JsonKey(name: 'minZoomInGameMultiplier')
  double? minZoomInGameMultiplier;

  /// 垂直同步。
  @JsonKey(name: 'vsync')
  bool? vsync;

  /// 全屏模式。
  @JsonKey(name: 'fullscreen')
  bool? fullscreen;

  /// 无边框窗口模式。
  @JsonKey(name: 'borderlessWindow')
  bool? borderlessWindow;

  /// 强制横屏（移动端）。
  @JsonKey(name: 'landscape')
  bool? landscape;

  /// 显示粒子特效。
  @JsonKey(name: 'effects')
  bool? effects;

  /// 显示大气效果。
  @JsonKey(name: 'atmosphere')
  bool? atmosphere;

  /// 光照渲染。
  @JsonKey(name: 'drawLight')
  bool? drawLight;

  /// 显示被摧毁方块的残骸。
  @JsonKey(name: 'destroyedBlocks')
  bool? destroyedBlocks;

  /// 方块状态覆盖层。
  @JsonKey(name: 'blockStatus')
  bool? blockStatus;

  /// 显示玩家聊天消息。
  @JsonKey(name: 'playerChat')
  bool? playerChat;

  /// 显示核心物品数量。
  @JsonKey(name: 'coreItems')
  bool? coreItems;

  /// 显示小地图。
  @JsonKey(name: 'minimap')
  bool? minimap;

  /// 平滑镜头移动。
  @JsonKey(name: 'smoothCamera')
  bool? smoothCamera;

  /// 分离镜头（调试用）。
  @JsonKey(name: 'detachCamera')
  bool? detachCamera;

  /// 显示玩家坐标。
  @JsonKey(name: 'position')
  bool? position;

  /// 显示鼠标坐标。
  @JsonKey(name: 'mousePosition')
  bool? mousePosition;

  /// 显示帧率。
  @JsonKey(name: 'fps')
  bool? fps;

  /// 显示玩家指示器。
  @JsonKey(name: 'playerIndicators')
  bool? playerIndicators;

  /// 显示各类指示器。
  @JsonKey(name: 'indicators')
  bool? indicators;

  /// 显示天气效果。
  @JsonKey(name: 'showWeather')
  bool? showWeather;

  /// 动态水面效果。
  @JsonKey(name: 'animatedWater')
  bool? animatedWater;

  /// 动态护盾效果。
  @JsonKey(name: 'animatedShields')
  bool? animatedShields;

  /// 泛光后期效果。
  @JsonKey(name: 'bloom')
  bool? bloom;

  /// 像素化渲染。
  @JsonKey(name: 'pixelate')
  bool? pixelate;

  /// 线性纹理过滤（关闭则为邻近过滤）。
  @JsonKey(name: 'linear')
  bool? linear;

  /// 跳过核心动画。
  @JsonKey(name: 'skipCoreAnimation')
  bool? skipCoreAnimation;

  /// 隐藏逻辑显示屏。
  @JsonKey(name: 'hideDisplays')
  bool? hideDisplays;

  /// Mac 刘海屏区域适配。
  @JsonKey(name: 'macNotch')
  bool? macNotch;

  /// 对角交换（移动端）。
  @JsonKey(name: 'swapDiagonal')
  bool? swapDiagonal;

  // ── 音频 ──

  /// 始终播放背景音乐（即使窗口失焦）。
  @JsonKey(name: 'alwaysMusic')
  bool? alwaysMusic;

  /// 音乐音量 (0-100)。
  @JsonKey(name: 'musicVol')
  int? musicVol;

  /// 音效音量 (0-100)。
  @JsonKey(name: 'sfxVol')
  int? sfxVol;

  /// 环境音效音量 (0-100)。
  @JsonKey(name: 'ambientVol')
  int? ambientVol;

  // ── 系统 ──

  /// 语言代码（如 `"zh_CN"`, `"en"`, `"default"`）。
  @JsonKey(name: 'locale')
  String? locale;

  /// 方块同步。
  @JsonKey(name: 'blockSync')
  bool? blockSync;

  /// 游戏构建号。
  @JsonKey(name: 'lastBuild')
  int? lastBuild;

  /// 游戏构建版本字符串。
  @JsonKey(name: 'lastBuildString')
  String? lastBuildString;

  /// 创建一个所有字段均为 null 的空补丁。
  MindustrySettingsPatch();

  /// 从 JSON Map 反序列化（由 `json_serializable` 生成）。
  factory MindustrySettingsPatch.fromJson(Map<String, dynamic> json) =>
      _$MindustrySettingsPatchFromJson(json);

  /// 序列化为 JSON Map。仅包含非 null 字段。
  Map<String, dynamic> toJson() {
    final json = _$MindustrySettingsPatchToJson(this);
    json.removeWhere((_, v) => v == null);
    return json;
  }

  /// 将非 null 字段应用到 [target]。
  void _applyTo(MindustrySettings target) {
    // 游戏
    if (saveInterval != null) target.saveInterval = saveInterval!;
    if (autoTarget != null) target.autoTarget = autoTarget!;
    if (keyboard != null) target.keyboard = keyboard!;
    if (crashReport != null) target.crashReport = crashReport!;
    if (communityServers != null) target.communityServers = communityServers!;
    if (saveCreate != null) target.saveCreate = saveCreate!;
    if (blockReplace != null) target.blockReplace = blockReplace!;
    if (conveyorPathfinding != null) {
      target.conveyorPathfinding = conveyorPathfinding!;
    }
    if (hints != null) target.hints = hints!;
    if (logicHints != null) target.logicHints = logicHints!;
    if (backgroundPause != null) target.backgroundPause = backgroundPause!;
    if (buildAutoPause != null) target.buildAutoPause = buildAutoPause!;
    if (distinctControlGroups != null) {
      target.distinctControlGroups = distinctControlGroups!;
    }
    if (doubleTapMine != null) target.doubleTapMine = doubleTapMine!;
    if (commandModeHold != null) target.commandModeHold = commandModeHold!;
    if (modCrashDisable != null) target.modCrashDisable = modCrashDisable!;
    if (playerLimit != null) target.playerLimit = playerLimit!;
    if (steamPublicHost != null) target.steamPublicHost = steamPublicHost!;
    if (console != null) target.console = console!;

    // 图形
    if (uiScale != null) target.uiScale = uiScale!;
    if (uiScaleChanged != null) target.uiScaleChanged = uiScaleChanged!;
    if (screenShake != null) target.screenShake = screenShake!;
    if (bloomIntensity != null) target.bloomIntensity = bloomIntensity!;
    if (bloomBlur != null) target.bloomBlur = bloomBlur!;
    if (fpsCap != null) target.fpsCap = fpsCap!;
    if (chatOpacity != null) target.chatOpacity = chatOpacity!;
    if (lasersOpacity != null) target.lasersOpacity = lasersOpacity!;
    if (preferredLaserOpacity != null) {
      target.preferredLaserOpacity = preferredLaserOpacity!;
    }
    if (unitLaserOpacity != null) {
      target.unitLaserOpacity = unitLaserOpacity!;
    }
    if (bridgeOpacity != null) target.bridgeOpacity = bridgeOpacity!;
    if (maxMagnificationMultiplierPercent != null) {
      target.maxMagnificationMultiplierPercent =
          maxMagnificationMultiplierPercent!;
    }
    if (maxZoomInGameMultiplier != null) {
      target.maxZoomInGameMultiplier = maxZoomInGameMultiplier!;
    }
    if (minMagnificationMultiplierPercent != null) {
      target.minMagnificationMultiplierPercent =
          minMagnificationMultiplierPercent!;
    }
    if (minZoomInGameMultiplier != null) {
      target.minZoomInGameMultiplier = minZoomInGameMultiplier!;
    }
    if (vsync != null) target.vsync = vsync!;
    if (fullscreen != null) target.fullscreen = fullscreen!;
    if (borderlessWindow != null) target.borderlessWindow = borderlessWindow!;
    if (landscape != null) target.landscape = landscape!;
    if (effects != null) target.effects = effects!;
    if (atmosphere != null) target.atmosphere = atmosphere!;
    if (drawLight != null) target.drawLight = drawLight!;
    if (destroyedBlocks != null) target.destroyedBlocks = destroyedBlocks!;
    if (blockStatus != null) target.blockStatus = blockStatus!;
    if (playerChat != null) target.playerChat = playerChat!;
    if (coreItems != null) target.coreItems = coreItems!;
    if (minimap != null) target.minimap = minimap!;
    if (smoothCamera != null) target.smoothCamera = smoothCamera!;
    if (detachCamera != null) target.detachCamera = detachCamera!;
    if (position != null) target.position = position!;
    if (mousePosition != null) target.mousePosition = mousePosition!;
    if (fps != null) target.fps = fps!;
    if (playerIndicators != null) {
      target.playerIndicators = playerIndicators!;
    }
    if (indicators != null) target.indicators = indicators!;
    if (showWeather != null) target.showWeather = showWeather!;
    if (animatedWater != null) target.animatedWater = animatedWater!;
    if (animatedShields != null) target.animatedShields = animatedShields!;
    if (bloom != null) target.bloom = bloom!;
    if (pixelate != null) target.pixelate = pixelate!;
    if (linear != null) target.linear = linear!;
    if (skipCoreAnimation != null) {
      target.skipCoreAnimation = skipCoreAnimation!;
    }
    if (hideDisplays != null) target.hideDisplays = hideDisplays!;
    if (macNotch != null) target.macNotch = macNotch!;
    if (swapDiagonal != null) target.swapDiagonal = swapDiagonal!;

    // 音频
    if (alwaysMusic != null) target.alwaysMusic = alwaysMusic!;
    if (musicVol != null) target.musicVol = musicVol!;
    if (sfxVol != null) target.sfxVol = sfxVol!;
    if (ambientVol != null) target.ambientVol = ambientVol!;

    // 系统
    if (locale != null) target.locale = locale!;
    if (blockSync != null) target.blockSync = blockSync!;
    if (lastBuild != null) target.lastBuild = lastBuild!;
    if (lastBuildString != null) target.lastBuildString = lastBuildString!;
  }

  @override
  String toString() {
    final parts = <String>[];
    // 遍历所有公有字段，找出非 null 的
    if (saveInterval != null) parts.add('saveInterval=$saveInterval');
    if (autoTarget != null) parts.add('autoTarget=$autoTarget');
    if (fullscreen != null) parts.add('fullscreen=$fullscreen');
    if (uiScale != null) parts.add('uiScale=$uiScale');
    if (fpsCap != null) parts.add('fpsCap=$fpsCap');
    if (vsync != null) parts.add('vsync=$vsync');
    if (locale != null) parts.add('locale=$locale');
    if (musicVol != null) parts.add('musicVol=$musicVol');
    if (sfxVol != null) parts.add('sfxVol=$sfxVol');
    return 'MindustrySettingsPatch(${parts.isEmpty ? 'empty' : parts.join(", ")})';
  }
}
