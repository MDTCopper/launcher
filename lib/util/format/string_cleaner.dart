import 'package:xml/xml.dart';

String removeColorTags(String input) {
  final regex = RegExp(r'\[#([A-Za-z0-9]{6})\]|\[[A-Za-z0-9]+\]|\[\]');
  return input.replaceAll(regex, '');
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

String parseBrokenJson(String json) {
  return json
      .replaceAll(RegExp(r'//.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'"\s+"'), '","')
      .replaceAll(RegExp(r',\s*}'), '}');
}

