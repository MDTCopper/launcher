import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/setting_metadata.dart';
import 'package:copper_launcher/util/io/remote_data.dart';
import 'package:flutter/foundation.dart';

/// 版本设置适配：按 build 从 remote 读 `setting_adapter/<min>-<max>.json`。
///
/// 文件格式为「v136 基准 + 逐版本差量」（数据来自 Mindustry 版本考古记录）：
/// - `base`：v136 起可用的设置，每项含 `categories`（可属多个分类）
/// - `changes`：按 build 升序记录增删——`add` 为完整 spec（覆盖同名），
///   `remove` 为键名列表；`build` 不高于目标版本时全部应用
///
/// 兼容旧格式：仅有平铺 `settings` 的文件按无差量处理。
/// 解析结果按 build 缓存；索引 / 文件内容变化时自动失效。
class SettingAdapter {
  static String? _indexContent;
  static String? _fileContent;
  static final Map<int, List<SettingSpec>> _resolved = {};

  /// 按 build 读取该版本的可设置列表；无适配文件时返回 null
  static Future<List<SettingSpec>?> loadForBuild(int build) async {
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

  /// 索引覆盖的最小 build；低于它的版本没有适配数据，settings 覆写也无效
  static Future<int?> minSupportedBuild() async {
    final indexContent = await RemoteData.load(settingAdapterIndexFile);
    if (indexContent == null) return null;
    return minBuildOf(indexContent);
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
