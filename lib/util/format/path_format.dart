/// 路径文本格式化工具
library;

/// 让路径在 Text 换行时按目录层级断开，而非在分隔符后断出孤行。
///
/// Flutter 默认断行规则把 [`\`、`/`]（SY 类字符）视为可断点且断在其**后**，
/// Windows / Android 路径又全由分隔符构成 → 出现 `C:` 独占一行的奇怪断开。
///
/// 处理：每个分隔符前插 ZWSP（U+200B，可断点），后插 ZWNBSP（U+FEFF，禁止断开），
/// 断点被钳制到分隔符**之前** → 新行总以 `\` / `/` 开头（目录层级完整）：
/// `C:\aaa\bbb` / `\cccc\dddd`
String formatPathForWrap(String path) {
  return path.replaceAllMapped(
    RegExp(r'[\\/]'),
    (match) => '\u200B${match[0]}\uFEFF',
  );
}