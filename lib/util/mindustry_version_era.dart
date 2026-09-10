/// Mindustry 版本时代：按 build 号划分
///
/// - v70（2019-04-02）pixelate 设置回归且默认关闭，传统像素风结束
/// - v97（2019-10-24）模组系统诞生，Java 模组同版本起支持
enum MindustryVersionEra {
  /// v97 起：支持模组
  modern(label: '现代版', summary: 'v97 起 · 支持模组', downloadHint: null),

  /// v70–v96：像素风已结束，但还没有模组系统
  classic(
    label: '经典',
    summary: 'v70–v96 · 不支持模组',
    downloadHint: '不支持载入模组（模组系统 v97 起才有）',
  ),

  /// v70 前：传统像素风，且无法载入模组
  ancient(
    label: '远古版',
    summary: 'v70 前 · 传统像素风 · 不支持模组',
    downloadHint: '不支持载入模组（模组系统 v97 起才有），画面为传统像素风',
  );

  const MindustryVersionEra({
    required this.label,
    required this.summary,
    required this.downloadHint,
  });

  /// 时代名
  final String label;

  /// 一句话说明，列表分段标题下展示
  final String summary;

  /// 下载前提示；null 表示该时代无需提示
  final String? downloadHint;

  /// v70：pixelate 默认关闭，传统像素风结束
  static const double classicStartBuild = 70;

  /// v97：模组系统诞生
  static const double modernStartBuild = 97;

  /// 按 build 号判定时代
  static MindustryVersionEra ofBuild(double build) {
    if (build >= modernStartBuild) return MindustryVersionEra.modern;
    if (build >= classicStartBuild) return MindustryVersionEra.classic;
    return MindustryVersionEra.ancient;
  }

  /// 按 release tag 判定时代，正式版 tag 形如 `v159.7` / `v88`
  ///
  /// 解析不出 build 号时返回 null，交由调用方决定兜底
  static MindustryVersionEra? ofTag(String tag) {
    final build = double.tryParse(tag.replaceFirst('v', ''));
    if (build == null) return null;
    return ofBuild(build);
  }
}
