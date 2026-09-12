import 'dart:convert';

/// 自定设置分类（不照搬游戏内分类，按使用频率 / 用途划分）。
enum SettingCategory {
  common('常用'),
  game('游戏'),
  graphics('图像'),
  info('信息'),
  sound('音频'),
  system('系统');

  const SettingCategory(this.title);

  final String title;
}

/// 设置值类型。
enum SettingType {
  bool,
  int,
  options, // 固定字符串选项（如语言）
}

/// 单条设置元数据：驱动 game_setting_page 数据化渲染。
///
/// key 为 Mindustry settings.bin 的原始键名；title 为中文标题；
/// category 决定归属哪个分类；type 决定渲染控件。
class SettingSpec {
  final String key;
  final String title;
  final SettingCategory category;
  final SettingType type;

  /// 整数滑块的取值范围；非 int 类型为 null。
  final int? min;
  final int? max;
  final int? step;

  /// 显示单位（如 `%`、`x`、`秒`）；仅 int 类型有意义。
  final String unit;

  /// 显示比率：显示值 = 原始值 × [displayRatio]（如屏幕抖动 0.25 显示为 x）；
  /// 仅 int 类型有意义，默认 1。
  final double displayRatio;

  /// options 类型的候选项；其它类型为 null。
  final List<String>? options;

  const SettingSpec._({
    required this.key,
    required this.title,
    required this.category,
    required this.type,
    this.min,
    this.max,
    this.step,
    this.unit = '',
    this.displayRatio = 1.0,
    this.options,
  });

  const SettingSpec.bool(String key, String title, SettingCategory category)
    : this._(
        key: key,
        title: title,
        category: category,
        type: SettingType.bool,
      );

  const SettingSpec.intSlider(
    String key,
    String title,
    SettingCategory category, {
    required int min,
    required int max,
    int step = 1,
    String unit = '',
    double displayRatio = 1.0,
  }) : this._(
         key: key,
         title: title,
         category: category,
         type: SettingType.int,
         min: min,
         max: max,
         step: step,
         unit: unit,
         displayRatio: displayRatio,
       );

  const SettingSpec.options(
    String key,
    String title,
    SettingCategory category, {
    required List<String> options,
  }) : this._(
         key: key,
         title: title,
         category: category,
         type: SettingType.options,
         options: options,
       );

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'category': category.name,
    'type': type.name,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (step != null) 'step': step,
    if (unit.isNotEmpty) 'unit': unit,
    if (displayRatio != 1.0) 'displayRatio': displayRatio,
    if (options != null) 'options': options,
  };

  static SettingSpec? fromJson(Map<String, dynamic> json) {
    final type = SettingType.values.asNameMap()[json['type']];
    final category = SettingCategory.values.asNameMap()[json['category']];
    final key = json['key'] as String?;
    final title = json['title'] as String?;
    if (key == null || title == null || type == null || category == null) {
      return null;
    }
    switch (type) {
      case SettingType.bool:
        return SettingSpec.bool(key, title, category);
      case SettingType.int:
        return SettingSpec.intSlider(
          key,
          title,
          category,
          min: (json['min'] as num?)?.toInt() ?? 0,
          max: (json['max'] as num?)?.toInt() ?? 100,
          step: (json['step'] as num?)?.toInt() ?? 1,
          unit: (json['unit'] as String?) ?? '',
          displayRatio: (json['displayRatio'] as num?)?.toDouble() ?? 1.0,
        );
      case SettingType.options:
        return SettingSpec.options(
          key,
          title,
          category,
          options: (json['options'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
        );
    }
  }
}

/// 最新版本（跟随当前 Mindustry）的完整设置目录。
///
/// key 对齐 Mindustry `SettingsMenuDialog` 注册的键与默认值，
/// 分类按本项目自定规则划分。
const List<SettingSpec> mindustrySettingCatalog = [
  // ── 常用 ──
  SettingSpec.intSlider(
    'uiscale',
    '界面缩放比例',
    .common,
    min: 25,
    max: 300,
    step: 5,
    unit: '%',
  ),
  SettingSpec.bool('hints', '游戏提示', .common),
  SettingSpec.bool('detach-camera', '自由视角', .common),
  SettingSpec.bool('fps', '显示帧数和网络延迟', .common),
  SettingSpec.bool('smoothcamera', '平滑镜头', .common),
  SettingSpec.bool('minimap', '显示小地图', .common),
  SettingSpec.bool('position', '显示玩家坐标', .common),
  SettingSpec.bool('doubletapmine', '双击采矿', .common),
  SettingSpec.bool('macnotch', 'Mac 刘海屏适配', .common),

  // ── 游戏 ──
  SettingSpec.intSlider(
    'saveinterval',
    '自动保存时间',
    .game,
    min: 10,
    max: 600,
    step: 10,
    unit: '秒',
  ),
  SettingSpec.intSlider(
    'screenshake',
    '屏幕抖动',
    .game,
    min: 0,
    max: 8,
    unit: 'x',
    displayRatio: 0.25,
  ),
  SettingSpec.intSlider(
    'bloomintensity',
    '光效强度',
    .game,
    min: 0,
    max: 16,
    unit: '%',
    displayRatio: 25,
  ),
  SettingSpec.intSlider('bloomblur', '光效模糊', .game, min: 1, max: 16, unit: 'x'),
  SettingSpec.intSlider(
    'fpscap',
    '最大帧数',
    .game,
    min: 10,
    max: 245,
    step: 5,
    unit: 'fps',
  ),
  SettingSpec.intSlider(
    'lasersopacity',
    '电力连接线不透明度',
    .game,
    min: 0,
    max: 100,
    step: 5,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'unitlaseropacity',
    '单位采矿光束不透明度',
    .game,
    min: 0,
    max: 100,
    step: 5,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'bridgeopacity',
    '桥梁不透明度',
    .game,
    min: 0,
    max: 100,
    step: 5,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'maxmagnificationmultiplierpercent',
    '最小视距（最大缩放）',
    .game,
    min: 100,
    max: 200,
    step: 25,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'minmagnificationmultiplierpercent',
    '最大视距（最小缩放）',
    .game,
    min: 100,
    max: 300,
    step: 25,
    unit: '%',
  ),
  SettingSpec.bool('autotarget', '自动瞄准（移动端）', .game),
  SettingSpec.bool('keyboard', '键盘模式（移动端）', .game),
  SettingSpec.bool('crashreport', '发送崩溃报告', .game),
  SettingSpec.bool('communityservers', '显示社区服务器', .game),
  SettingSpec.bool('blockreplace', '自动选择合适的建筑', .game),
  SettingSpec.bool('conveyorpathfinding', '传送带寻路', .game),
  SettingSpec.bool('logichints', '逻辑处理器提示', .game),
  SettingSpec.bool('backgroundpause', '后台暂停', .game),
  SettingSpec.bool('buildautopause', '建造自动暂停', .game),
  SettingSpec.bool('distinctcontrolgroups', '每单位限制一个编队', .game),
  SettingSpec.bool('doubletapmine', '双击采矿', .game),
  SettingSpec.bool('commandmodehold', '长按保持指挥模式', .game),
  SettingSpec.bool('modcrashdisable', 'Mod 崩溃时禁用', .game),
  SettingSpec.intSlider('playerlimit', '联机玩家上限', .game, min: 2, max: 32),
  SettingSpec.bool('steampublichost', '公开主机', .game),
  SettingSpec.bool('console', '内置控制台', .game),

  // ── 图像 ──
  SettingSpec.intSlider(
    'screenshake',
    '屏幕抖动',
    .graphics,
    min: 0,
    max: 8,
    unit: 'x',
    displayRatio: 0.25,
  ),
  SettingSpec.intSlider(
    'bloomintensity',
    '光效强度',
    .graphics,
    min: 0,
    max: 16,
    unit: '%',
    displayRatio: 25,
  ),
  SettingSpec.intSlider(
    'bloomblur',
    '光效模糊',
    .graphics,
    min: 1,
    max: 16,
    unit: 'x',
  ),
  SettingSpec.intSlider(
    'fpscap',
    '最大帧数',
    .graphics,
    min: 10,
    max: 245,
    step: 5,
    unit: 'fps',
  ),
  SettingSpec.intSlider(
    'lasersopacity',
    '电力连接线不透明度',
    .graphics,
    min: 0,
    max: 100,
    step: 5,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'unitlaseropacity',
    '单位采矿光束不透明度',
    .graphics,
    min: 0,
    max: 100,
    step: 5,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'bridgeopacity',
    '桥梁不透明度',
    .graphics,
    min: 0,
    max: 100,
    step: 5,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'maxmagnificationmultiplierpercent',
    '最小视距（最大缩放）',
    .graphics,
    min: 100,
    max: 200,
    step: 25,
    unit: '%',
  ),
  SettingSpec.intSlider(
    'minmagnificationmultiplierpercent',
    '最大视距（最小缩放）',
    .graphics,
    min: 100,
    max: 300,
    step: 25,
    unit: '%',
  ),
  SettingSpec.bool('vsync', '垂直同步', .graphics),
  SettingSpec.bool('borderlesswindow', '无边框窗口', .graphics),
  SettingSpec.bool('landscape', '强制横屏（移动端）', .graphics),
  SettingSpec.bool('effects', '建筑特效', .graphics),
  SettingSpec.bool('atmosphere', '显示行星大气层', .graphics),
  SettingSpec.bool('drawlight', '绘制阴影/光照', .graphics),
  SettingSpec.bool('destroyedblocks', '显示已摧毁的建筑', .graphics),
  SettingSpec.bool('showweather', '显示天气效果', .graphics),
  SettingSpec.bool('animatedwater', '动态液体', .graphics),
  SettingSpec.bool('animatedshields', '动态力场', .graphics),
  SettingSpec.bool('bloom', '光效', .graphics),
  SettingSpec.bool('pixelate', '像素画面', .graphics),
  SettingSpec.bool('linear', '抗锯齿', .graphics),
  SettingSpec.bool('skipcoreanimation', '跳过核心发射/着陆动画', .graphics),
  SettingSpec.bool('macnotch', 'Mac 刘海屏适配', .graphics),
  SettingSpec.bool('swapdiagonal', '对角交换（移动端）', .graphics),

  // ── 信息 ──
  SettingSpec.intSlider(
    'chatopacity',
    '聊天界面不透明度',
    .info,
    min: 0,
    max: 100,
    step: 5,
    unit: '%',
  ),
  SettingSpec.bool('fps', '显示帧数和网络延迟', .info),
  SettingSpec.bool('playerchat', '显示玩家聊天气泡', .info),
  SettingSpec.bool('coreitems', '显示核心物资', .info),
  SettingSpec.bool('blockstatus', '显示建筑状态', .info),
  SettingSpec.bool('mouseposition', '显示鼠标坐标', .info),
  SettingSpec.bool('playerindicators', '玩家指示器', .info),
  SettingSpec.bool('indicators', '显示标记', .info),
  SettingSpec.bool('hidedisplays', '不显示逻辑绘图', .info),

  // ── 音频 ──
  SettingSpec.bool('alwaysmusic', '始终播放音乐', .sound),
  SettingSpec.intSlider(
    'musicvol',
    '音乐音量',
    .common,
    min: 0,
    max: 100,
    unit: '%',
  ),
  SettingSpec.intSlider('sfxvol', '音效音量', .sound, min: 0, max: 100, unit: '%'),
  SettingSpec.intSlider(
    'ambientvol',
    '环境音量',
    .sound,
    min: 0,
    max: 100,
    unit: '%',
  ),

  // ── 系统 ──
  SettingSpec.options(
    'locale',
    '语言',
    .system,
    options: ['default', 'zh_CN', 'en', 'ja', 'ko'],
  ),
  SettingSpec.bool('blocksync', '方块同步', .system),
];

/// 生成 `setting_adapter/<min>-<max>.json` 的内容。
///
/// 该方法供导出 / 发布 remote 数据用；页面侧读的是产物 JSON。
String generateAdapterJson({
  required int minBuild,
  required int maxBuild,
  List<SettingSpec> catalog = mindustrySettingCatalog,
  DateTime? updateTime,
}) {
  final payload = {
    'update_time': (updateTime ?? DateTime.now())
        .toIso8601String()
        .split('.')
        .first,
    'min_build': minBuild,
    'max_build': maxBuild,
    'settings': catalog.map((s) => s.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}
