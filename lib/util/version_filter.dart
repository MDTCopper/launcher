/// 语义化版本与版本过滤器
///
/// 语法按 Copper wiki 的 `developers/versions`：
/// - 语义化版本 `X.Y.Z`，缺省分量补 0，分量必须是整数；逐分量比较
/// - 过滤器：`=` `!=` `>` `>=` `<` `<=`、通配符 `1.*.0` / `1.x.0`、`^`、`~`、
///   区间 `a - b`、`&&`、`||`、括号、隐式与（相邻条件空格）、空串或 `*` 视为任意
/// - 单个字符串解析不出语义化版本时**回退为字符串精确匹配**；数组总是精确匹配
///
/// 游戏版本、加载器版本、模组依赖（`dependencies.mindustry` 等）都用这套写法
library;

/// 语义化版本：`X.Y.Z`
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// 解析：按点拆分、缺省分量补 0、每个分量必须是整数；解析不了返回 null
  static SemVer? tryParse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parts = text.split('.');
    if (parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      numbers.add(number);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return SemVer(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(SemVer other) => compareTo(other) < 0;

  bool operator <=(SemVer other) => compareTo(other) <= 0;

  bool operator >(SemVer other) => compareTo(other) > 0;

  bool operator >=(SemVer other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is SemVer &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// 版本过滤器：把表达式解析成一棵可判定的树
class VersionFilter {
  const VersionFilter._(
    this._matcher, {
    required this.expression,
    required this.matchesExactText,
    List<String> exactTexts = const [],
  }) : _exactTexts = exactTexts;

  final bool Function(SemVer version) _matcher;

  /// 原始表达式，便于日志与排查
  final String expression;

  /// 是否退化成字符串精确匹配（表达式里有解析不出语义化版本的部分）
  final bool matchesExactText;

  /// 字符串精确匹配时要比对的原文
  final List<String> _exactTexts;

  /// 解析表达式：[expression] 可以是字符串、字符串数组或 null
  ///
  /// - 字符串数组 → 精确匹配其中的任意一个
  /// - null / 空串 / `*` → 任意版本
  /// - 解析不出的字符串 → 整体退化为字符串精确匹配
  static VersionFilter parse(dynamic expression) {
    if (expression is List) {
      final wanted = expression.map((item) => '$item').toList();
      return VersionFilter._(
        (_) => false,
        expression: wanted.join(' | '),
        matchesExactText: true,
        exactTexts: wanted,
      );
    }

    final text = expression == null ? '' : '$expression'.trim();
    if (text.isEmpty || text == '*') {
      return VersionFilter._(
        (_) => true,
        expression: text,
        matchesExactText: false,
      );
    }

    final tokens = _tokenize(text);
    final node = tokens == null
        ? null
        : _FilterParser(tokens).parse();
    if (node == null) {
      return VersionFilter._(
        (_) => false,
        expression: text,
        matchesExactText: true,
        exactTexts: [text],
      );
    }
    return VersionFilter._(
      node.matches,
      expression: text,
      matchesExactText: false,
    );
  }

  /// [version] 是否满足这个过滤器
  ///
  /// [version] 为 null 时只有「任意版本」的过滤器会通过
  bool matches(String? version) {
    if (matchesExactText) {
      if (version == null) return false;
      return _exactTexts.contains(version.trim());
    }
    final parsed = SemVer.tryParse(version);
    if (parsed == null) return false;
    return _matcher(parsed);
  }

  @override
  String toString() => 'VersionFilter($expression)';
}

/// 把表达式拆成记号；出现无法处理的字符时返回 null（交给字符串回退）
List<String>? _tokenize(String text) {
  final tokens = <String>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
      buffer.clear();
    }
  }

  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char.trim().isEmpty) {
      flush();
      index++;
      continue;
    }
    if (char == '(' || char == ')') {
      flush();
      tokens.add(char);
      index++;
      continue;
    }
    //两字符运算符先匹配，避免把 >= 拆成 > 和 =
    final two = index + 1 < text.length ? text.substring(index, index + 2) : '';
    if (two == '>=' || two == '<=' || two == '!=' || two == '&&' || two == '||') {
      flush();
      tokens.add(two);
      index += 2;
      continue;
    }
    if ('=><^~'.contains(char)) {
      flush();
      tokens.add(char);
      index++;
      continue;
    }
    //版本 / 区间分隔符：数字、点、通配符、x、以及字符串版本里的其它字符
    if (RegExp(r'[0-9A-Za-z.*+\-_]').hasMatch(char)) {
      buffer.write(char);
      index++;
      continue;
    }
    return null;
  }
  flush();
  return tokens;
}

/// 过滤器里的一段版本：分量可以是具体数字或通配符
class _Pattern {
  const _Pattern(this.parts);

  /// null 表示该分量是通配符（`*` / `x`）
  final List<int?> parts;

  /// 解析失败（含非数字字符）返回 null
  static _Pattern? tryParse(String text) {
    final raw = text.split('.');
    if (raw.length > 3) return null;
    final parts = <int?>[];
    for (final part in raw) {
      final lower = part.toLowerCase();
      if (lower == '*' || lower == 'x') {
        parts.add(null);
        continue;
      }
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      parts.add(number);
    }
    return _Pattern(parts);
  }

  bool get isAny => parts.every((part) => part == null);

  /// 用于比较的具体值：通配符与缺省分量都按 0
  SemVer get asVersion => SemVer(
    _valueAt(0),
    _valueAt(1),
    _valueAt(2),
  );

  int _valueAt(int index) =>
      index < parts.length ? (parts[index] ?? 0) : 0;

  /// 按分量逐个匹配：通配符匹配任意，缺省的分量不管（视为通配）
  bool matchesVersion(SemVer version) {
    final values = [version.major, version.minor, version.patch];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      if (part == null) continue;
      if (part != values[index]) return false;
    }
    return true;
  }

  /// `^` 的上界：不动最左非零分量（`^1.2.3` → 2.0.0、`^0.2.3` → 0.3.0）
  SemVer caretUpperBound() {
    final version = asVersion;
    if (version.major != 0) return SemVer(version.major + 1, 0, 0);
    if (version.minor != 0) return SemVer(0, version.minor + 1, 0);
    return SemVer(0, 0, version.patch + 1);
  }

  /// `~` 的上界：同 minor 内（`~1.2.3` → 1.3.0）
  SemVer tildeUpperBound() {
    final version = asVersion;
    return SemVer(version.major, version.minor + 1, 0);
  }
}

/// 过滤器节点
abstract class _Node {
  bool matches(SemVer version);
}

class _Any implements _Node {
  const _Any();

  @override
  bool matches(SemVer version) => true;
}

class _Or implements _Node {
  const _Or(this.children);

  final List<_Node> children;

  @override
  bool matches(SemVer version) =>
      children.any((child) => child.matches(version));
}

class _And implements _Node {
  const _And(this.children);

  final List<_Node> children;

  @override
  bool matches(SemVer version) =>
      children.every((child) => child.matches(version));
}

class _Exact implements _Node {
  const _Exact(this.pattern);

  final _Pattern pattern;

  @override
  bool matches(SemVer version) => pattern.matchesVersion(version);
}

class _Compare implements _Node {
  const _Compare(this.operator, this.pattern);

  final String operator;
  final _Pattern pattern;

  @override
  bool matches(SemVer version) {
    final bound = pattern.asVersion;
    switch (operator) {
      case '>=':
        return version >= bound;
      case '>':
        return version > bound;
      case '<=':
        return version <= bound;
      case '<':
        return version < bound;
      case '!=':
        return version != bound;
      case '=':
        return version == bound;
    }
    return false;
  }
}

class _Caret implements _Node {
  const _Caret(this.pattern);

  final _Pattern pattern;

  @override
  bool matches(SemVer version) =>
      version >= pattern.asVersion && version < pattern.caretUpperBound();
}

class _Tilde implements _Node {
  const _Tilde(this.pattern);

  final _Pattern pattern;

  @override
  bool matches(SemVer version) =>
      version >= pattern.asVersion && version < pattern.tildeUpperBound();
}

class _Range implements _Node {
  const _Range(this.from, this.to);

  final _Pattern from;
  final _Pattern to;

  @override
  bool matches(SemVer version) =>
      version >= from.asVersion && version <= to.asVersion;
}

/// 递归下降解析：`or := and ('||' and)*`、`and := unary (('&&')? unary)*`
class _FilterParser {
  _FilterParser(this._tokens);

  final List<String> _tokens;
  int _index = 0;

  bool get _hasMore => _index < _tokens.length;

  String? get _peek => _hasMore ? _tokens[_index] : null;

  String _next() => _tokens[_index++];

  /// 解析失败返回 null（调用方改用字符串精确匹配）
  _Node? parse() {
    final node = _parseOr();
    if (node == null || _hasMore) return null;
    return node;
  }

  _Node? _parseOr() {
    final children = <_Node>[];
    final first = _parseAnd();
    if (first == null) return null;
    children.add(first);
    while (_peek == '||') {
      _next();
      final next = _parseAnd();
      if (next == null) return null;
      children.add(next);
    }
    return children.length == 1 ? children.first : _Or(children);
  }

  _Node? _parseAnd() {
    final children = <_Node>[];
    while (true) {
      final token = _peek;
      if (token == null || token == ')' || token == '||') break;
      if (token == '&&') {
        _next();
        if (children.isEmpty) return null;
        continue;
      }
      final node = _parseUnary();
      if (node == null) return null;
      children.add(node);
    }
    if (children.isEmpty) return null;
    return children.length == 1 ? children.first : _And(children);
  }

  _Node? _parseUnary() {
    final token = _peek;
    if (token == null) return null;

    if (token == '(') {
      _next();
      final inner = _parseOr();
      if (inner == null || _peek != ')') return null;
      _next();
      return inner;
    }

    if (token == '^' || token == '~') {
      _next();
      final pattern = _parsePattern();
      if (pattern == null) return null;
      return token == '^' ? _Caret(pattern) : _Tilde(pattern);
    }

    if (const ['=', '!=', '>', '>=', '<', '<='].contains(token)) {
      _next();
      final pattern = _parsePattern();
      if (pattern == null) return null;
      return _Compare(token, pattern);
    }

    final pattern = _parsePattern();
    if (pattern == null) return null;
    //区间：1.0.0 - 2.0.0
    if (_peek == '-') {
      _next();
      final to = _parsePattern();
      if (to == null) return null;
      return _Range(pattern, to);
    }
    if (pattern.isAny) return const _Any();
    return _Exact(pattern);
  }

  _Pattern? _parsePattern() {
    final token = _peek;
    if (token == null) return null;
    if (token == '(' || token == ')' || token == '&&' || token == '||') {
      return null;
    }
    _next();
    return _Pattern.tryParse(token);
  }
}
