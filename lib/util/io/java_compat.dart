/// Mindustry 大版本 → 推荐 Java 大版本（阈值规则表）。
///
/// 老版本（io.anuke 时代，如 v88 的 number=4）用老 LWJGL，配现代 JVM 有
/// 原生兼容问题（实测 Java 23 报 "Unsupported JNI version"）；按**大版本**
/// （jar 内 version.properties 的 `number`，github tag 只有 build 号）给推荐 JVM。
///
/// 只存分界点而非逐版本枚举（Java 换代频率低，规则保持精简）：
/// - number < 6 → 推荐 Java 8（v5 及更早，含 v88；老 LWJGL 最稳）
/// - 6 ≤ number < 7 → 推荐 Java 11
/// - number ≥ 7 → 推荐 Java 17（v7/v8 现代版本）
class JavaCompat {
  /// 阈值规则：主版本 ≥ 该值时启用对应推荐（升序），低于首个规则的走默认老 JVM。
  static const List<({int minRelease, int javaMajor})> _rules = [
    (minRelease: 6, javaMajor: 11),
    (minRelease: 7, javaMajor: 17),
  ];

  /// 老版本默认推荐 Java（低于所有阈值）
  static const int defaultJavaMajor = 8;

  /// 按游戏主版本号查推荐 Java 大版本
  static int recommendedFor(int releaseInt) {
    var result = defaultJavaMajor;
    for (final rule in _rules) {
      if (releaseInt >= rule.minRelease) {
        result = rule.javaMajor;
      }
    }
    return result;
  }
}