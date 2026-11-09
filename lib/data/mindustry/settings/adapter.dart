import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/mindustry/settings/setting_metadata.dart';
import 'package:copper_launcher/data/net/data_index/data_index_client.dart';
import 'package:copper_launcher/util/io/remote_data.dart';
import 'package:flutter/foundation.dart';

/// 版本设置适配：优先读数据索引 `mindustry/setting-adapter/current.json`
/// （跟随最新 Mindustry 的一张完整表，每项带 `name`/`description` 的中英译文）。
///
/// 新表不再区分 build 范围：所有版本共用同一份设置项；`minSupportedBuild` 返回 null。
/// 数据索引不可用时回落到 launcher remote 的旧「base + changes」文件。
/// 解析结果按内容缓存，数据变化时自动失效。
class SettingAdapter {
  /// 数据索引里的最新版完整设置表（跟随最新 Mindustry，不再按 build 区间）
  static const String dataIndexTablePath =
      'mindustry/setting-adapter/current.json';

  static String? _tableContent;
  static List<SettingSpec>? _tableCache;

  static String? _indexContent;
  static String? _fileContent;
  static final Map<int, List<SettingSpec>> _resolved = {};

  /// 读取最新版完整设置表；数据索引不可用时回落到旧的 launcher remote 适配文件
  static Future<List<SettingSpec>?> loadForBuild(int build) async {
    final content = await DataIndexClient.loadText(
      dataIndexTablePath,
      maxAge: DataIndexClient.mindustryVersionsMaxAge,
    );
    if (content != null) {
      if (_tableContent != content) {
        _tableCache = applyTable(content);
        _tableContent = content;
      }
      if (_tableCache != null && _tableCache!.isNotEmpty) return _tableCache;
    }
    return _loadLegacy(build);
  }

  /// 最新完整表不再区分适配范围，所有版本共用；返回 null 表示不按 build 过滤
  static Future<int?> minSupportedBuild() async => null;

  /// 解析数据索引 current.json：`{settings:[{key,name:{en,zh_CN},description:{...}}]}`
  @visibleForTesting
  static List<SettingSpec>? applyTable(String content) {
    final dynamic decoded;
    try {
      decoded = decodeRemote(content);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final settings = decoded['settings'];
    if (settings is! List<dynamic>) return null;

    final specs = <SettingSpec>[];
    for (final item in settings) {
      if (item is! Map<String, dynamic>) continue;
      final spec = SettingSpec.fromJson(item);
      if (spec != null) specs.add(spec);
    }
    return specs.isEmpty ? null : specs;
  }

  static Future<List<SettingSpec>?> _loadLegacy(int build) async {
    final indexContent = await RemoteData.load(settingAdapterIndexFile);
    if (indexContent == null) return null;

    final file = _resolveFile(indexContent, build);
    if (file == null) return null;

    final content = await RemoteData.load('setting_adapter/$file');
    if (content == null) return null;

    // 内容未变且该 build 已算过 → 直接用缓存，避免每次进页面重算
    if (_indexContent == indexContent && _fileContent == content) {
      final cached = _resolved[build];
      if (cached != null) return cached;
    }

    final specs = applyDeltas(content, build);
    if (specs == null) return null;

    _indexContent = indexContent;
    _fileContent = content;
    _resolved[build] = specs;
    return specs;
  }

  /// 从索引内容里取最小的 `min_build`；无规则时返回 null
  @visibleForTesting
  static int? minBuildOf(String indexContent) {
    final dynamic index;
    try {
      index = decodeRemote(indexContent);
    } catch (_) {
      return null;
    }
    if (index is! Map<String, dynamic>) return null;

    int? min;
    for (final rule in (index['rules'] as List<dynamic>? ?? const [])) {
      final item = rule as Map<String, dynamic>?;
      final value = (item?['min_build'] as num?)?.toInt();
      if (value != null && (min == null || value < min)) min = value;
    }
    return min;
  }

  /// 从索引内容里找 [build] 对应的适配文件名；无命中返回 null
  static String? _resolveFile(String indexContent, int build) {
    final dynamic index;
    try {
      index = decodeRemote(indexContent);
    } catch (_) {
      return null;
    }
    if (index is! Map<String, dynamic>) return null;

    for (final rule in (index['rules'] as List<dynamic>? ?? const [])) {
      final item = rule as Map<String, dynamic>?;
      if (item == null) continue;
      final min = (item['min_build'] as num?)?.toInt();
      final max = (item['max_build'] as num?)?.toInt();
      if (min != null && max != null && build >= min && build <= max) {
        return item['file'] as String?;
      }
    }
    return null;
  }

  /// 解析适配文件并应用 [build] 之前的差量；格式非法返回 null
  ///
  /// 只认「base + changes」的新格式（见上）；旧格式返回 null
  @visibleForTesting
  static List<SettingSpec>? applyDeltas(String content, int build) {
    final dynamic decoded;
    try {
      decoded = decodeRemote(content);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final base = decoded['base'] as List<dynamic>?;
    if (base == null) return null;

    final state = <String, SettingSpec>{};
    for (final item in base) {
      if (item is! Map<String, dynamic>) continue;
      final spec = SettingSpec.fromJson(item);
      if (spec != null) state[spec.key] = spec;
    }
    if (state.isEmpty) return null;

    final changes = decoded['changes'] as List<dynamic>? ?? const [];
    for (final change in changes) {
      if (change is! Map<String, dynamic>) continue;
      final atBuild = (change['build'] as num?)?.toInt();
      if (atBuild == null || atBuild > build) continue;

      for (final key in (change['remove'] as List<dynamic>? ?? const [])) {
        state.remove(key.toString());
      }
      for (final add in (change['add'] as List<dynamic>? ?? const [])) {
        if (add is! Map<String, dynamic>) continue;
        final spec = SettingSpec.fromJson(add);
        if (spec != null) state[spec.key] = spec;
      }
    }

    return state.values.toList();
  }
}
