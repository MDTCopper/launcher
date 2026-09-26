/// Mindustry 大版本（`version.properties` 的 `number`）：按 build 号划分
///
/// 区间是从官方 release 名反推的 —— 名字里就带着大版本（`v8 Build 159.7`、
/// `7.0 Build 146`），是历史事实、不会变。
///
/// 表按**从新到旧**排：查找（第一个「build ≥ 起点」即命中）与列表显示共用这一份顺序，
/// 上界则由相邻那档的起点推出来，不用另写一遍
enum MindustryMajorVersion {
  /// v147 起：目前没有比 v8 更新的大版本，将来出的新版本会一直落进这档
  v8Plus(label: 'v8 或以上', minBuild: 147),

  /// v127–v146
  v7(label: 'v7', minBuild: 127),

  /// v105–v126
  v6(label: 'v6', minBuild: 105),

  /// v97–v104：模组系统自 v97 起
  v5(label: 'v5', minBuild: 97),

  /// v41–v96：其中 v70 起传统像素风结束
  v4(label: 'v4', minBuild: 41),

  /// v40 及更早：官方 v1–v3 的原始版本
  v3OrOlder(label: 'v3 及更早', minBuild: 0);

  const MindustryMajorVersion({required this.label, required this.minBuild});

  /// 段标题
  final String label;

  /// 该大版本的起始 build（含）
  final double minBuild;

  /// 上界（不含）：就是相邻那档的起点；最新那档没有上界
  double? get maxBuild {
    final index = values.indexOf(this);
    if (index <= 0) return null;
    return values[index - 1].minBuild;
  }

  /// 按 build 号判定大版本
  static MindustryMajorVersion ofBuild(double build) {
    for (final major in values) {
      if (build >= major.minBuild) return major;
    }
    return v3OrOlder;
  }

  /// 按 release tag 判定，正式版 tag 形如 `v159.7`
  ///
  /// 解析不出 build 号时返回 null，交由调用方决定兜底
  static MindustryMajorVersion? ofTag(String tag) {
    final build = double.tryParse(tag.replaceFirst('v', ''));
    if (build == null) return null;
    return ofBuild(build);
  }
}
