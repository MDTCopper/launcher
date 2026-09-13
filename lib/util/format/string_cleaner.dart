import 'package:xml/xml.dart';

/// 去除 Mindustry / Arc 的颜色标记（markup）标签，保留可见文本。
///
/// 贪婪匹配：从 `[` 开始，内部 `[` 计入嵌套深度、`[[` 视为转义跳过，
/// 直到配对 `]` 闭合；若整段内容判定为「颜色相关」（含 #hex、颜色名、
/// `[]` 弹栈等），整段剥离，否则按普通字面保留。
String removeColorTags(String input) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < input.length) {
    if (input[i] != '[') {
      buffer.write(input[i]);
      i++;
      continue;
    }
    final end = _matchColorGroup(input, i);
    if (end > i) {
      i = end; // 整组剥掉
    } else {
      buffer.write('[');
      i++;
    }
  }
  return buffer.toString();
}

/// 从 [start]（指向 `[`）尝试匹配一整组颜色标签，返回剥除结束位置；
/// 无法判定为颜色标签时返回 0（保留 `[` 字面）。
int _matchColorGroup(String input, int start) {
  var depth = 1;
  var i = start + 1;
  while (i < input.length) {
    final ch = input[i];
    if (ch == '[') {
      // `[[` 转义：跳过两位（字面左括号），不计嵌套，但继续向闭合前进
      if (i + 1 < input.length && input[i + 1] == '[') {
        i += 2;
        continue;
      }
      depth++;
      i++;
    } else if (ch == ']') {
      depth--;
      i++;
      if (depth == 0) {
        final content = input.substring(start + 1, i - 1);
        return _isColorGroup(content) ? i : 0;
      }
    } else {
      i++;
    }
  }
  return 0; // 未闭合：保留原样
}

/// 判断 `[content]` 是否为颜色相关组合：
/// - hex 颜色 `#RRGGBB` / `#RRGGBBAA`
/// - 命名颜色（字母数字下划线，如 red / accent / lightgray）
/// - 弹栈 `[]`、或以上组合嵌套（内部含 `[`、`]` 视为嵌套标签）
bool _isColorGroup(String content) {
  final normalized = content.replaceAll('[', '').replaceAll(']', '');
  if (normalized.isEmpty) return true; // `[]` 弹栈
  if (normalized.startsWith('#')) {
    final hex = normalized.substring(1);
    if (hex.length == 6 || hex.length == 8) {
      return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
    }
  }
  return RegExp(r'^[A-Za-z0-9_]+$').hasMatch(normalized);
}

String removeNewlines(String input) {
  return input.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String sanitizeText(String input) {
  final regex = RegExp(
    r'[\uFFFD\u0000-\u0008\u000B-\u000C\u000E-\u001F\uE000-\uF8FF\uD800-\uDFFF]',
  );
  return input.replaceAll(regex, '');
}

String generalizeText(String str, {bool removeNewLine = false}) {
  if (str.isEmpty) return str;
  str = removeColorTags(sanitizeText(str));
  if (removeNewLine) return removeNewlines(str);
  return str;
}



/// 修正 SVG 里被 `transform="scale(...)"` 缩放的文字。
///
/// shields.io 这类徽章有两种写法：
/// - `<text transform="scale(.1)">`（缩放写在 text 上）
/// - `<g transform="scale(.1)"><text …></g>`（缩放写在祖先 g 上）
///
/// flutter_svg 对后者不生效（g 的缩放没作用到文字），文字会按原始字号
/// 直接画出来——于是「徽章上的字超大、徽标大小正常」。这里把累计缩放
/// 烘焙进 text 的 font-size / x / y / textLength，并去掉这些 scale
final _scalePattern = RegExp(r'scale\s*\(\s*([\d.]+)\s*\)');

/// 元素内部是否只有文本相关节点（没有图形 / 图片）
bool _svgOnlyTextInside(XmlElement element) => element.descendantElements.every(
  (it) => const {'g', 'text', 'title', 'tspan', 'desc'}.contains(it.name.local),
);

/// 向上找最近的 font-size（自身优先）
double? _svgInheritedFontSize(XmlElement element) {
  var current = element;
  while (current.parent != null) {
    final value = current.getAttribute('font-size');
    final number = value == null ? null : double.tryParse(value);
    if (number != null) return number;
    final parent = current.parentElement;
    if (parent == null) break;
    current = parent;
  }
  return null;
}

/// 去掉 transform 里的 scale(...)；没有别的内容就删除整个属性
void _svgStripScale(XmlElement element) {
  final transform = element.getAttribute('transform');
  if (transform == null) return;
  final left = transform.replaceAll(RegExp(r'scale\s*\([^)]*\)'), '').trim();
  if (left.isEmpty) {
    element.removeAttribute('transform');
  } else {
    element.setAttribute('transform', left);
  }
}

String fixSvgTextScale(String svgString) {
  try {
    final document = XmlDocument.parse(svgString);

    for (final textNode in document.findAllElements('text')) {
      // 1. 累计自身与祖先上的 scale
      final holders = <XmlElement>{};
      var scale = 1.0;

      void collect(XmlElement element) {
        final transform = element.getAttribute('transform');
        if (transform == null) return;
        for (final match in _scalePattern.allMatches(transform)) {
          scale *= double.parse(match.group(1)!);
          holders.add(element);
        }
      }

      collect(textNode);
      var parent = textNode.parentElement;
      while (parent != null) {
        collect(parent);
        parent = parent.parentElement;
      }
      if (scale == 1.0 || holders.isEmpty) continue;

      // 2. 祖先里若还画了别的东西（徽标 / 图形），去掉它的缩放会牵连它们 → 放弃
      if (holders.any(
        (it) => !identical(it, textNode) && !_svgOnlyTextInside(it),
      )) {
        continue;
      }

      // 3. 字号：继承值 × 累计缩放，显式写到 text 上
      final inherited = _svgInheritedFontSize(textNode);
      if (inherited != null) {
        textNode.setAttribute(
          'font-size',
          (inherited * scale).toStringAsFixed(2),
        );
      }

      // 4. x / y / textLength 同步缩放
      for (final attr in const ['x', 'y', 'textLength']) {
        final value = textNode.getAttribute(attr);
        final number = value == null ? null : double.tryParse(value);
        if (number != null) {
          textNode.setAttribute(attr, (number * scale).toStringAsFixed(2));
        }
      }

      // 5. 去掉这些元素上的 scale（保留 translate 等其它变换）
      for (final holder in holders) {
        _svgStripScale(holder);
      }
    }

    return document.toXmlString();
  } catch (e) {
    return svgString;
  }
}

///修复不规范的json格式
String parseBrokenJson(String json) {
  return json
      .replaceAll(RegExp(r'//.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'"\s+"'), '","')
      .replaceAll(RegExp(r',\s*}'), '}');
}

