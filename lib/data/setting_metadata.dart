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

  static final Map<String, SettingCategory> _byName = {
    for (final value in values) value.name: value,
  };

  /// 按名字解析；未知返回 null
  static SettingCategory? tryParse(String name) => _byName[name];
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
/// [categories] 决定归属哪些分类——同一设置可属于多个分类
/// （如 screenshake 同时在游戏与图像），「常用」栏也是靠它叠加出来的；
/// type 决定渲染控件。
class SettingSpec {
  final String key;
  final String title;
  final List<SettingCategory> categories;
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
    required this.categories,
    required this.type,
    this.min,
    this.max,
    this.step,
    this.unit = '',
    this.displayRatio = 1.0,
    this.options,
  });

  const SettingSpec.bool(
    String key,
    String title,
    List<SettingCategory> categories,
  ) : this._(
        key: key,
        title: title,
        categories: categories,
        type: SettingType.bool,
      );

  const SettingSpec.intSlider(
    String key,
    String title,
    List<SettingCategory> categories, {
    required int min,
    required int max,
    int step = 1,
    String unit = '',
    double displayRatio = 1.0,
  }) : this._(
         key: key,
         title: title,
         categories: categories,
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
    List<SettingCategory> categories, {
    required List<String> options,
  }) : this._(
         key: key,
         title: title,
         categories: categories,
         type: SettingType.options,
         options: options,
       );

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'categories': categories.map((c) => c.name).toList(),
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
    final key = json['key'] as String?;
    final title = json['title'] as String?;
    if (key == null || title == null || type == null) return null;

    // categories 为列表；旧数据的单值 category 也兼容读取
    final names = <String>[
      for (final item in (json['categories'] as List<dynamic>? ?? const []))
        item.toString(),
      if (json['category'] is String) json['category'] as String,
    ];
    final categories = names
        .map(SettingCategory.tryParse)
        .whereType<SettingCategory>()
        .toList();
    if (categories.isEmpty) return null;

    switch (type) {
      case SettingType.bool:
        return SettingSpec.bool(key, title, categories);
      case SettingType.int:
        return SettingSpec.intSlider(
          key,
          title,
          categories,
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
          categories,
          options: (json['options'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
        );
    }
  }
}

/// 最新版本（跟随当前 Mindustry）的完整设置目录。
///
/// key 对齐 Mindustry `SettingsMenuDialog` 注册的键与默认值；
/// 分类按本项目自定规则划分，可多分类重复出现；
/// 「常用」栏由 remote 数据作者挑选（给键的 categories 加 common 即可），
/// 各版本差异由 remote/setting_adapter/136-999999.json 的基准 + 差量表达，
/// 此目录只代表最新版本，作为无适配数据时的兜底。
const List<SettingSpec> mindustrySettingCatalog = [
  // ── 游戏 ──
  SettingSpec.intSlider('saveinterval', '自动保存时间', [.game], min: 10, max: 600, step: 10, unit: '秒'),
  SettingSpec.bool('hints', '游戏提示', [.game, .common]),
  SettingSpec.bool('autotarget', '自动瞄准（移动端）', [.game]),
  SettingSpec.bool('keyboard', '键盘模式（移动端）', [.game]),
  SettingSpec.bool('savecreate', '自动创建存档', [.game]),
  SettingSpec.bool('blockreplace', '自动选择合适的建筑', [.game]),
  SettingSpec.bool('conveyorpathfinding', '传送带寻路', [.game]),
  SettingSpec.bool('backgroundpause', '后台暂停', [.game]),
  SettingSpec.bool('buildautopause', '建造自动暂停', [.game]),
  SettingSpec.bool('doubletapmine', '双击采矿', [.game, .common]),
  SettingSpec.bool('commandmodehold', '长按保持指挥模式', [.game]),
  SettingSpec.bool('modcrashdisable', 'Mod 崩溃时禁用', [.game]),
  SettingSpec.intSlider('playerlimit', '联机玩家上限', [.game], min: 2, max: 32, step: 1),
  SettingSpec.bool('console', '内置控制台', [.game]),
  SettingSpec.intSlider('screenshake', '屏幕抖动', [.game, .graphics, .common], min: 0, max: 8, step: 1, unit: 'x', displayRatio: 0.25),
  SettingSpec.intSlider('bloomintensity', '光效强度', [.game, .graphics, .common], min: 0, max: 16, step: 1, unit: '%', displayRatio: 25.0),
  SettingSpec.intSlider('bloomblur', '光效模糊', [.game, .graphics, .common], min: 1, max: 16, step: 1, unit: 'x'),
  SettingSpec.intSlider('fpscap', '最大帧数', [.game, .graphics], min: 10, max: 245, step: 5, unit: 'fps'),
  SettingSpec.intSlider('lasersopacity', '电力连接线不透明度', [.game, .graphics, .common], min: 0, max: 100, step: 5, unit: '%'),
  SettingSpec.intSlider('bridgeopacity', '桥梁不透明度', [.game, .graphics, .common], min: 0, max: 100, step: 5, unit: '%'),
  SettingSpec.bool('communityservers', '显示社区服务器', [.game]),
  SettingSpec.bool('distinctcontrolgroups', '每单位限制一个编队', [.game]),
  SettingSpec.intSlider('maxmagnificationmultiplierpercent', '最小视距（最大缩放）', [.game, .graphics, .common], min: 100, max: 200, step: 25, unit: '%'),
  SettingSpec.intSlider('minmagnificationmultiplierpercent', '最大视距（最小缩放）', [.game, .graphics, .common], min: 100, max: 300, step: 25, unit: '%'),
  SettingSpec.intSlider('unitlaseropacity', '单位采矿光束不透明度', [.game, .graphics, .common], min: 0, max: 100, step: 5, unit: '%'),
  SettingSpec.bool('touchscreen', '触屏模式（移动端）', [.game]),
  // ── 图像 ──
  SettingSpec.bool('fps', '显示帧数和网络延迟', [.graphics, .info, .common]),
  SettingSpec.bool('smoothcamera', '平滑镜头', [.graphics]),
  SettingSpec.bool('minimap', '显示小地图', [.graphics, .common]),
  SettingSpec.intSlider('uiscale', '界面缩放比例', [.graphics, .common], min: 25, max: 300, step: 5, unit: '%'),
  SettingSpec.bool('position', '显示玩家坐标', [.graphics]),
  SettingSpec.bool('vsync', '垂直同步', [.graphics, .common]),
  SettingSpec.bool('landscape', '强制横屏（移动端）', [.graphics, .common]),
  SettingSpec.bool('effects', '建筑特效', [.graphics]),
  SettingSpec.bool('atmosphere', '显示行星大气层', [.graphics]),
  SettingSpec.bool('destroyedblocks', '显示已摧毁的建筑', [.graphics]),
  SettingSpec.bool('showweather', '显示天气效果', [.graphics]),
  SettingSpec.bool('animatedwater', '动态液体', [.graphics]),
  SettingSpec.bool('animatedshields', '动态力场', [.graphics]),
  SettingSpec.bool('bloom', '光效', [.graphics]),
  SettingSpec.bool('pixelate', '像素画面', [.graphics]),
  SettingSpec.bool('linear', '抗锯齿', [.graphics]),
  SettingSpec.bool('skipcoreanimation', '跳过核心发射/着陆动画', [.graphics]),
  SettingSpec.bool('swapdiagonal', '对角交换（移动端）', [.graphics]),
  SettingSpec.bool('macnotch', 'Mac 刘海屏适配', [.graphics, .common]),
  SettingSpec.bool('drawlight', '绘制阴影/光照', [.graphics]),
  SettingSpec.bool('detach-camera', '自由视角', [.graphics, .common]),
  SettingSpec.bool('showotherbuildplans', '显示其他玩家的建筑规划', [.graphics]),
  SettingSpec.bool('showpings', '显示标记', [.graphics]),
  SettingSpec.intSlider('uiEdgePadding', 'UI 内边距', [.graphics], min: 0, max: 100, step: 1, unit: 'px'),
  SettingSpec.bool('drawhitboxes', '显示碰撞箱', [.graphics]),
  SettingSpec.bool('logiclocalization', '逻辑本地化', [.graphics]),
  // ── 信息 ──
  SettingSpec.intSlider('chatopacity', '聊天界面不透明度', [.info, .common], min: 0, max: 100, step: 5, unit: '%'),
  SettingSpec.bool('playerchat', '显示玩家聊天气泡', [.info]),
  SettingSpec.bool('coreitems', '显示核心物资', [.info]),
  SettingSpec.bool('blockstatus', '显示建筑状态', [.info, .common]),
  SettingSpec.bool('mouseposition', '显示鼠标坐标', [.info]),
  SettingSpec.bool('playerindicators', '玩家指示器', [.info, .common]),
  SettingSpec.bool('indicators', '敌人指示器', [.info, .common]),
  SettingSpec.bool('hidedisplays', '不显示逻辑绘图', [.info]),
  SettingSpec.bool('showperformance', '显示性能表现', [.info]),
  // ── 音频 ──
  SettingSpec.intSlider('musicvol', '音乐音量', [.sound], min: 0, max: 100, step: 1, unit: '%'),
  SettingSpec.intSlider('sfxvol', '音效音量', [.sound], min: 0, max: 100, step: 1, unit: '%'),
  SettingSpec.intSlider('ambientvol', '环境音量', [.sound], min: 0, max: 100, step: 1, unit: '%'),
  SettingSpec.bool('alwaysmusic', '始终播放音乐', [.sound]),
  // ── 系统 ──
  SettingSpec.options('locale', '语言', [.system], options: ['default', 'zh_CN', 'en', 'ja', 'ko']),
  SettingSpec.bool('blocksync', '方块同步', [.system]),
];
