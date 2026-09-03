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



String fixSvgTextScale(String svgString) {
  try {
    final document = XmlDocument.parse(svgString);
    final gNodeScaleMap = <XmlElement, double>{};

    // 1. 收集所有带 transform scale 的 text 节点，找到父 g 节点
    for (final textNode in document.findAllElements('text')) {
      final transform = textNode.getAttribute('transform');
      if (transform == null || !transform.contains('scale')) continue;

      final match = RegExp(r'scale\(([\d.]+)\)').firstMatch(transform);
      if (match == null) continue;
      final scale = double.parse(match.group(1)!);

      // 向上找最近的 <g> 父节点
      XmlElement? parentG = textNode.parentElement;
      while (parentG != null && parentG.name.local != 'g') {
        parentG = parentG.parentElement;
      }

      if (parentG != null && !gNodeScaleMap.containsKey(parentG)) {
        gNodeScaleMap[parentG] = scale;
      }
    }

    // 2. 每个 g 节点只改一次 fontSize
    for (final g in gNodeScaleMap.entries) {
      final fontSizeStr = g.key.getAttribute('font-size');
      if (fontSizeStr == null) continue;
      final fontSize = double.parse(fontSizeStr);
      g.key.setAttribute('font-size', (fontSize * g.value).toStringAsFixed(1));
    }

    // 3. 修正所有 text 的 x/y/textLength，并移除 transform
    for (final textNode in document.findAllElements('text')) {
      final transform = textNode.getAttribute('transform');
      if (transform == null || !transform.contains('scale')) continue;

      final match = RegExp(r'scale\(([\d.]+)\)').firstMatch(transform);
      if (match == null) continue;
      final scale = double.parse(match.group(1)!);

      final attrs = const ['x', 'y', 'textLength'];
      for (final attr in attrs) {
        final val = textNode.getAttribute(attr);
        if (val == null) continue;
        final numVal = double.tryParse(val);
        if (numVal != null) {
          textNode.setAttribute(attr, (numVal * scale).toStringAsFixed(1));
        }
      }
      textNode.removeAttribute('transform');
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

