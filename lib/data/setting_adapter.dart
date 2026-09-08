import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/util/io/remote_data.dart';

import 'setting_metadata.dart';

/// 版本设置适配：按 build 从 remote 读 `setting_adapter/<min>-<max>.json`
class SettingAdapter {
  /// 按 build 读取该版本的可设置列表；无适配文件时返回 null
  static Future<List<SettingSpec>?> loadForBuild(int build) async {
    final indexContent = await RemoteData.load(settingAdapterIndexFile);
    if (indexContent == null) return null;

    final index = decodeRemote(indexContent) as Map<String, dynamic>?;
    if (index == null) return null;

    final rules = index['rules'] as List<dynamic>? ?? const [];
    String? file;
    for (final rule in rules) {
      final item = rule as Map<String, dynamic>?;
      if (item == null) continue;
      final min = (item['min_build'] as num?)?.toInt();
      final max = (item['max_build'] as num?)?.toInt();
      if (min != null && max != null && build >= min && build <= max) {
        file = item['file'] as String?;
        break;
      }
    }
    if (file == null) return null;

    final content = await RemoteData.load('setting_adapter/$file');
    if (content == null) return null;
    return parseAdapterContent(content);
  }

  /// 解析 `setting_adapter/<min>-<max>.json` 内容为 [SettingSpec] 列表
  static List<SettingSpec>? parseAdapterContent(String content) {
    try {
      final decoded = decodeRemote(content) as Map<String, dynamic>?;
      if (decoded == null) return null;
      final settings = decoded['settings'] as List<dynamic>? ?? const [];
      return settings
          .map(
            (e) => e is Map<String, dynamic> ? SettingSpec.fromJson(e) : null,
          )
          .whereType<SettingSpec>()
          .toList();
    } catch (_) {
      return null;
    }
  }
}
