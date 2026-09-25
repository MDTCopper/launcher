import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

part 'mod.g.dart';

/// Mod 状态标记，对齐 Mindustry `Mods.ModState`。
///
/// settings.bin 只持久化是否启用（`mod-<name>-enabled`），
/// 其余状态（依赖缺失、内容错误等）是游戏加载时的运行时状态
enum ModState {
  /// 启用。
  enabled('启用'),

  /// 内容加载有错误，但仍可运行（算作启用）
  contentErrors('内容错误'),

  /// 缺少必需依赖
  missingDependencies('缺少依赖'),

  /// 依赖不完整（被禁用的依赖不能满足必需依赖）
  incompleteDependencies('依赖不完整'),

  /// 依赖关系存在循环
  circularDependencies('循环依赖'),

  /// 不受支持（游戏版本过低等）
  unsupported('不受支持'),

  /// 已禁用。
  disabled('已禁用');

  /// 显示名。
  final String label;

  const ModState(this.label);

  /// 是否视为启用（Mindustry：`enabled` 与 `contentErrors` 都算启用）。
  bool get isEnabled =>
      this == ModState.enabled || this == ModState.contentErrors;
}

/// 模组该放哪个目录：Copper 原生模组（`copper.mod.json`）进 `<数据目录>/copper/mods`，
/// 原版模组进 `<数据目录>/mods`
///
/// 导入、扫描、估算都从这里取路径，别各写各的
String modsDirIn(String dataPath, {required bool copper}) =>
    copper ? p.joinAll([dataPath, 'copper', 'mods']) : p.join(dataPath, 'mods');

@JsonSerializable()
class Mod {
  Mod({
    required this.java,
    required this.minGameVersion,
    required this.description,
    required this.path,
    required this.name,
    required this.version,
    required this.author,
    required this.hidden,
    required this.dependencies,
    this.gameVersionFilter,
    required this.conflicts,
    this.copper = false,
  });

  ///存储路径
  final String? path;

  @JsonKey(defaultValue: '未知模组')
  final String name;

  @JsonKey(defaultValue: '未知版本')
  final String version;

  @JsonKey(defaultValue: '未知作者')
  final String author;

  @JsonKey(defaultValue: '0')
  final String minGameVersion;

  @JsonKey(defaultValue: false)
  final bool java;

  @JsonKey(defaultValue: '')
  final String description;

  final bool? hidden;

  @JsonKey(includeFromJson: false, includeToJson: false)
  late final Uint8List? icon;

  @JsonKey(defaultValue: [])
  final List<dynamic> dependencies;

  /// Copper 模组对游戏本体的版本要求：`dependencies.mindustry` 的原始过滤表达式
  /// （单个字符串，或字符串数组 = 精确匹配列表），判定用 `VersionFilter`；
  /// 原版模组与没写要求的 Copper 模组为 null
  final dynamic gameVersionFilter;

  /// Copper 的 `conflicts`（显式冲突）摊平后的模组 id 列表；原版没有显式冲突
  @JsonKey(defaultValue: [])
  final List<dynamic> conflicts;

  /// 是不是 Copper 原生模组（元数据为 `copper.mod.json` / `copper.mod.hjson`）：
  /// 这类模组放在 `<数据目录>/copper/mods/`，由加载器加载
  @JsonKey(defaultValue: false)
  final bool copper;

  /// mod 状态标记。
  ///
  /// 非持久化运行时字段，由 [applyModStates] 设置；默认 [ModState.enabled]。
  /// 缺失依赖、循环依赖等运行时状态可在依赖解析后直接赋值。
  @JsonKey(includeFromJson: false, includeToJson: false)
  ModState state = ModState.enabled;

  /// 内部名，与 Mindustry settings 键 `mod-<internalName>-enabled` 一致
  /// （`meta.name` 小写化、空格转 `-`）。
  String get internalName => name.trim().toLowerCase().replaceAll(' ', '-');

  /// 通过 mod 状态列表（settings 的 `mod-<name>-enabled`）设置状态；
  /// 列表中缺失该 mod 时视为启用。
  void applyModStates(Map<String, bool> states) {
    state = (states[internalName] ?? true)
        ? ModState.enabled
        : ModState.disabled;
  }

  factory Mod.fromJson(Map<String, dynamic> json, {Uint8List? icon}) {
    json = json.map(((key, value) {
      //依赖、冲突与游戏版本要求都是多值形态（对象摊平 / 数组），不能当字符串处理
      if (key == 'dependencies' ||
          key == 'conflicts' ||
          key == 'gameVersionFilter') {
        return MapEntry(key, value);
      }
      return MapEntry(key, value.toString());
    }));
    json['java'] = bool.tryParse(json['java'] ?? '');
    json['hidden'] = bool.tryParse(json['hidden'] ?? '');
    json['copper'] = bool.tryParse(json['copper'] ?? '');
    return _$ModFromJson(json)..icon = icon;
  }

  Map<String, dynamic> toJson() => _$ModToJson(this);
}
