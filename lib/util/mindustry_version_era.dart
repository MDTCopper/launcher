/// Mindustry 版本时代：按 build 号划分
///
/// - v70（2019-04-02）pixelate 设置回归且默认关闭，传统像素风结束
/// - v97（2019-10-24）模组系统诞生，Java 模组同版本起支持
///
/// 枚举顺序就是列表里的显示顺序（新的在上）
enum MindustryVersionEra {
  /// v97 起：支持模组
  modern(label: '正式版', summary: 'v97 起 · 支持模组', downloadHint: null),

  /// v70–v96：像素风已结束，但还没有模组系统
  ancient(
    label: '远古版',
    summary: 'v70–v96 · 不支持模组',
    downloadHint: '不支持载入模组（模组系统 v97 起才有）',
  ),

  /// v70 前：官方 v1–v3 的原始版本，传统像素风（Classic 是官方叫法，不翻译）
  classic(
    label: 'Classic',
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

  /// v70：远古版起点，传统像素风在这一版结束
  static const double ancientStartBuild = 70;

  /// v97：模组系统诞生
  static const double modernStartBuild = 97;

  /// v126：官方加入 `MINDUSTRY_DATA_DIR`，数据目录自此可被外部指定
  /// （更早的版本只能靠 `AppData` / `XDG_DATA_HOME` 之类的隐式覆盖，
  /// 数据会被套一层 `Mindustry` 子目录）
  static const double dataDirOverrideStartBuild = 126;

  /// 数据目录能否被外部指定——决定「把文件放进版本数据目录」这类操作是否成立
  static bool supportsDataDirOverride(double build) =>
      build >= dataDirOverrideStartBuild;

  /// 按 build 号判定时代
  static MindustryVersionEra ofBuild(double build) {
    if (build >= modernStartBuild) return MindustryVersionEra.modern;
    if (build >= ancientStartBuild) return MindustryVersionEra.ancient;
    return MindustryVersionEra.classic;
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
