import 'dart:convert';

import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'readme_loader.dart';

/// GitHub README 渲染器（自研，替代 `markdown → flutter_html` 管线）。
///
/// 为什么自研：GitHub 上的 README 是「markdown + 直写 HTML」混排，社区包
/// 对表格 / 代码块 / `<details>` / 相对链接 / 主题样式的适配都不好。
/// 这里直接遍历 markdown 的 AST 渲染成 Widget：
///
/// - 块级：标题 / 段落 / 列表（含嵌套与任务清单）/ 代码块 / 引用 / 分割线 / 表格
/// - 行内：粗体 / 斜体 / 删除线 / 行内代码 / 链接 / 图片
/// - 直写 HTML（`UnparsedContent`）：`<br> <img> <a> <b> <i> <code> <sub> <sup>`
///   以及容器 `<div align|center> <details><summary>`；不认识的标签剥掉只留内容
/// - 图片交给 [ModReadmeNetworkImage]（相对路径按仓库解析、支持 SVG 与徽章）
/// - 链接：绝对地址直接打开，相对路径按仓库拼成 GitHub 地址
class ModReadmeView extends StatefulWidget {
  const ModReadmeView({
    super.key,
    required this.data,
    required this.mod,
    this.onLinkTap,
  });

  /// README 原文（markdown）
  final String data;
  final ModOfficialListMeta mod;

  /// 覆盖默认的链接打开行为（默认用系统浏览器/内嵌 webview 打开）
  final void Function(String url)? onLinkTap;

  /// 相对链接 / 相对图片按仓库的哪个分支解析
  static String branchOf(ModOfficialListMeta mod) => mod.mainBranchCache ?? 'main';

  /// 把 README 里的链接解析成可打开的绝对地址。
  ///
  /// - `#anchor` → null（暂不支持页内跳转）
  /// - `https://…` / `mailto:` 等 → 原样
  /// - `./x.md`、`docs/x.md` → GitHub 仓库地址（按文件/目录判断 blob / tree）
  static String? resolveLink(ModOfficialListMeta mod, String href) {
    final link = href.trim();
    if (link.isEmpty || link.startsWith('#')) return null;
    if (Uri.tryParse(link)?.hasScheme ?? false) return link;
    if (link.startsWith('//')) return 'https:$link';

    final repo = 'https://github.com/${mod.repo}';
    final branch = branchOf(mod);
    final path = link.replaceFirst(RegExp(r'^\./'), '');
    if (path.endsWith('/')) return '$repo/tree/$branch/$path';
    // 有后缀（x.md / x.png）视为文件，无后缀视为目录
    return path.contains('.')
        ? '$repo/blob/$branch/$path'
        : '$repo/tree/$branch/$path';
  }

  /// HTML 小解析器（暴露出来给测试用）
  @visibleForTesting
  static List<ReadmeHtmlNode>? parseHtml(String html) => _parseHtml(html);

  @override
  State<ModReadmeView> createState() => _ModReadmeViewState();
}

class _ModReadmeViewState extends State<ModReadmeView> {
  /// 链接的点击识别器要在 dispose 里释放
  final _recognizers = <TapGestureRecognizer>[];

  late List<md.Node> _blocks = _parse(widget.data);

  @override
  void didUpdateWidget(covariant ModReadmeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _blocks = _parse(widget.data);
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  List<md.Node> _parse(String data) => md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parseLines(const LineSplitter().convert(data));

  ThemeData get _theme => Theme.of(context);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        for (final node in _blocks)
          ?_buildBlock(node, colors),
      ],
    );
  }

  // ── 块级 ──

  Widget? _buildBlock(md.Node node, AppColors colors) {
    if (node is md.Text) {
      final text = node.text.trim();
      return text.isEmpty ? null : _paragraph([node], colors);
    }
    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        final style = switch (level) {
          1 => _theme.textTheme.headlineMedium,
          2 => _theme.textTheme.headlineSmall,
          3 => _theme.textTheme.titleLarge,
          4 => _theme.textTheme.titleMedium,
          _ => _theme.textTheme.titleSmall,
        };
        return Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 8 : 4),
          child: Text.rich(
            TextSpan(
              children: _inlines(node.children ?? const <md.Node>[], colors),
              style: style?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        );

      case 'p':
        return _paragraph(node.children ?? const <md.Node>[], colors);

      case 'ul':
      case 'ol':
        return _buildList(node, colors, depth: 0);

      case 'pre':
        return _buildCodeBlock(node);

      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: colors.border, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              for (final child in node.children ?? const <md.Node>[])
                ?_buildBlock(child, colors),
            ],
          ),
        );

      case 'hr':
        return Divider(color: colors.border, height: 20);

      case 'table':
        return _buildTable(node, colors);

      case 'details':
        return _buildDetails(node, colors);

      default:
        // 未知块级：透明处理，只渲染内容（避免标签字面量漏到界面上）
        final children = node.children ?? const <md.Node>[];
        if (children.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            for (final child in children)
              ?_buildBlock(child, colors),
          ],
        );
    }
  }

  Widget _paragraph(List<md.Node> children, AppColors colors) => Text.rich(
    TextSpan(
      children: _inlines(children, colors),
      style: _theme.textTheme.bodyMedium?.copyWith(height: 1.6),
    ),
  );

  /// 列表（支持嵌套与任务清单；[depth] 用于缩进与切换符号）
  Widget _buildList(md.Element node, AppColors colors, {required int depth}) {
    final ordered = node.tag == 'ol';
    // 起点：<ol start="3">
    final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;

    final rows = <Widget>[];
    var number = start;
    for (final child in node.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'li') continue;

      final children = child.children ?? const <md.Node>[];
      // GFM 任务清单：li 内嵌 <input type="checkbox" checked>
      final checkbox = children.whereType<md.Element>().firstOrNullWhere(
        (it) => it.tag == 'input',
      );
      final checked = checkbox?.attributes.containsKey('checked') ?? false;
      final rest = [
        for (final it in children)
          if (!identical(it, checkbox))
            if (it is! md.Text || it.text.trim().isNotEmpty) it,
      ];

      // li 内可能直接嵌 子列表：拆开单独渲染，其余按行内/段落处理
      final nested = <md.Element>[];
      final inline = <md.Node>[];
      for (final it in rest) {
        if (it is md.Element && (it.tag == 'ul' || it.tag == 'ol')) {
          nested.add(it);
        } else {
          inline.add(it);
        }
      }

      rows.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 16.0, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: checkbox != null
                    ? Icon(
                        checked
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: colors.itemSecondary,
                      )
                    : Text(
                        ordered ? '${number++}.' : '•',
                        style: _theme.textTheme.bodyMedium?.copyWith(
                          color: colors.itemSecondary,
                        ),
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: _inlines(inline, colors),
                        style: _theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                    for (final sub in nested)
                      _buildList(sub, colors, depth: depth + 1),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  /// 代码块：等宽字体 + 背景 + 横向滚动（长行不折断，靠滚动看）
  Widget _buildCodeBlock(md.Element node) {
    final code = node.children?.whereType<md.Element>().firstOrNullWhere(
      (it) => it.tag == 'code',
    );
    // <pre><code class="language-dart">…</code></pre>
    final language = code?.attributes['class']?.replaceFirst(
      RegExp(r'^language-'),
      '',
    );

    final text = _textOf(code ?? node).replaceFirst(RegExp(r'\n$'), '');
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language != null && language.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 6),
              child: Text(
                language,
                style: _theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.of(context).itemHint,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              text,
              style: _theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 表格：首行作表头，超出宽度可横向滚动
  Widget _buildTable(md.Element node, AppColors colors) {
    final rows = <TableRow>[];
    var headerDone = false;

    void addRow(md.Element tr, {required bool header}) {
      final cells = [
        for (final cell in tr.children ?? const <md.Node>[])
          if (cell is md.Element && (cell.tag == 'td' || cell.tag == 'th'))
            cell,
      ];
      if (cells.isEmpty) return;
      rows.add(
        TableRow(
          children: [
            for (final cell in cells)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text.rich(
                  TextSpan(
                    children: _inlines(cell.children ?? const <md.Node>[], colors),
                    style: _theme.textTheme.bodySmall?.copyWith(
                      fontWeight: header ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    for (final section in node.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      if (section.tag == 'thead' || section.tag == 'tbody') {
        for (final tr in section.children ?? const <md.Node>[]) {
          if (tr is md.Element && tr.tag == 'tr') {
            addRow(tr, header: section.tag == 'thead' || !headerDone);
            headerDone = true;
          }
        }
      } else if (section.tag == 'tr') {
        addRow(section, header: !headerDone);
        headerDone = true;
      }
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: colors.border, width: 0.6),
        children: rows,
      ),
    );
  }

  /// `<details><summary>标题</summary>内容</details>`
  Widget _buildDetails(md.Element node, AppColors colors) {
    final children = node.children ?? const <md.Node>[];
    final summary = children.whereType<md.Element>().firstOrNullWhere(
      (it) => it.tag == 'summary',
    );
    final rest = [
      for (final it in children)
        if (!identical(it, summary)) it,
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border, width: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text.rich(
          TextSpan(
            children: _inlines(summary?.children ?? const <md.Node>[], colors),
            style: _theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              for (final child in rest)
                ?_buildBlock(child, colors),
            ],
          ),
        ],
      ),
    );
  }

  // ── 行内 ──

  List<InlineSpan> _inlines(List<md.Node> nodes, AppColors colors) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      _appendInline(node, colors, spans);
    }
    return spans;
  }

  void _appendInline(md.Node node, AppColors colors, List<InlineSpan> spans) {
    if (node is md.Text) {
      if (node.text.isNotEmpty) spans.add(TextSpan(text: node.text));
      return;
    }
    // 直写 HTML：逐段解析成 span / widget
    if (node is md.UnparsedContent) {
      _appendHtml(node.textContent, colors, spans);
      return;
    }
    if (node is! md.Element) return;

    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        spans.add(
          TextSpan(
            children: _inlines(children, colors),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      case 'em':
        spans.add(
          TextSpan(
            children: _inlines(children, colors),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      case 'del':
        spans.add(
          TextSpan(
            children: _inlines(children, colors),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      case 'code':
        spans.add(
          TextSpan(
            text: _textOf(node),
            style: _theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: _theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      case 'a':
        final href = node.attributes['href'];
        final url = href == null
            ? null
            : ModReadmeView.resolveLink(widget.mod, href);
        final text = _inlines(children, colors);
        if (url == null) {
          spans.add(TextSpan(children: text));
        } else {
          spans.add(
            TextSpan(
              children: text,
              style: TextStyle(color: _theme.colorScheme.primary),
              recognizer: _recognizerFor(url),
            ),
          );
        }
      case 'img':
        spans.add(_imageSpan(node, colors));
      case 'br':
        spans.add(const TextSpan(text: '\n'));
      case 'input':
        // 行内任务框（少见于非列表处）
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              node.attributes.containsKey('checked')
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 16,
              color: colors.itemSecondary,
            ),
          ),
        );
      default:
        // 容器标签（div/span/center/sub/sup…）透明处理
        spans.addAll(_inlines(children, colors));
    }
  }

  /// 直写 HTML 片段：先解析成小树，再按标签渲染；解析不了就剥标签留文本
  void _appendHtml(String html, AppColors colors, List<InlineSpan> spans) {
    final tree = _parseHtml(html);
    if (tree == null) {
      final plain = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (plain.isNotEmpty) spans.add(TextSpan(text: plain));
      return;
    }
    for (final node in tree) {
      _renderHtmlNode(node, colors, spans);
    }
  }

  void _renderHtmlNode(
    ReadmeHtmlNode node,
    AppColors colors,
    List<InlineSpan> spans,
  ) {
    if (node.tag == null) {
      if (node.text.isNotEmpty) spans.add(TextSpan(text: node.text));
      return;
    }

    List<InlineSpan> children() {
      final list = <InlineSpan>[];
      for (final child in node.children) {
        _renderHtmlNode(child, colors, list);
      }
      return list;
    }

    switch (node.tag) {
      case 'br':
        spans.add(const TextSpan(text: '\n'));
      case 'b':
      case 'strong':
        spans.add(
          TextSpan(
            children: children(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      case 'i':
      case 'em':
        spans.add(
          TextSpan(
            children: children(),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      case 'code':
        spans.add(
          TextSpan(
            children: children(),
            style: _theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: _theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      case 'sub':
        spans.add(_shiftedSpan(children(), 3));
      case 'sup':
        spans.add(_shiftedSpan(children(), -3));
      case 'a':
        final href = node.attributes['href'];
        final url = href == null
            ? null
            : ModReadmeView.resolveLink(widget.mod, href);
        spans.add(
          TextSpan(
            children: children(),
            style: url == null
                ? null
                : TextStyle(color: _theme.colorScheme.primary),
            recognizer: url == null ? null : _recognizerFor(url),
          ),
        );
      case 'img':
        spans.add(
          _imageSpanOf(
            node.attributes['src'] ?? '',
            double.tryParse(node.attributes['width'] ?? ''),
            double.tryParse(node.attributes['height'] ?? ''),
            colors,
          ),
        );
      default:
        // 容器标签（div / span / center / font…）：透明处理，只保留内容
        spans.addAll(children());
    }
  }

  InlineSpan _shiftedSpan(List<InlineSpan> children, double dy) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Transform.translate(
      offset: Offset(0, dy),
      child: Text.rich(
        TextSpan(children: children, style: _theme.textTheme.labelSmall),
      ),
    ),
  );

  InlineSpan _imageSpan(md.Element node, AppColors colors) {
    final src = node.attributes['src'];
    if (src == null || src.trim().isEmpty) {
      return const TextSpan(text: '');
    }
    final width = double.tryParse(node.attributes['width'] ?? '');
    final height = double.tryParse(node.attributes['height'] ?? '');
    return _imageSpanOf(src, width, height, colors);
  }

  InlineSpan _imageSpanOf(
    String src,
    double? width,
    double? height,
    AppColors colors,
  ) {
    final uri = Uri.tryParse(src.trim());
    if (uri == null) return const TextSpan(text: '');

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: ModReadmeNetworkImage(
          uri: uri,
          mod: widget.mod,
          width: width,
          height: height,
          onError: Icon(
            Icons.broken_image_outlined,
            size: 16,
            color: colors.itemHint,
          ),
        ),
      ),
    );
  }

  /// 取节点下的纯文本（代码块等）
  String _textOf(md.Node node) {
    final buffer = StringBuffer();
    void walk(md.Node node) {
      if (node is md.Text) {
        buffer.write(node.text);
      } else if (node is md.Element) {
        for (final child in node.children ?? const <md.Node>[]) {
          walk(child);
        }
      } else if (node is md.UnparsedContent) {
        buffer.write(node.textContent);
      }
    }

    walk(node);
    return buffer.toString();
  }

  TapGestureRecognizer _recognizerFor(String url) {
    final recognizer = TapGestureRecognizer();
    recognizer.onTap = () => _openLink(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _openLink(String url) async {
    final onLinkTap = widget.onLinkTap;
    if (onLinkTap != null) {
      onLinkTap(url);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.inAppWebView);
  }
}

/// 直写 HTML 的小节点树（[tag] 为 null 表示纯文本；仅渲染器内部与测试使用）
class ReadmeHtmlNode {
  final String? tag;
  final Map<String, String> attributes;
  final String text;
  final List<ReadmeHtmlNode> children;

  const ReadmeHtmlNode.text(this.text)
    : tag = null,
      attributes = const {},
      children = const [];

  const ReadmeHtmlNode.element(this.tag, this.attributes, this.children)
    : text = '';
}

/// 自闭合（无内容）标签
const _voidTags = {
  'br',
  'hr',
  'img',
  'input',
  'meta',
  'link',
  'wbr',
  'source',
};

/// 把 HTML 片段解析成节点树；含注释 / 残缺标签等无法处理时返回 null
List<ReadmeHtmlNode>? _parseHtml(String html) {
  if (html.contains('<!--') || html.contains('<?')) return null;

  final pattern = RegExp(
    r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^<>]*?)?)\s*(/?)\s*>',
  );
  final root = <ReadmeHtmlNode>[];
  final stack =
      <({String name, Map<String, String> attrs, List<ReadmeHtmlNode> children})>[];

  List<ReadmeHtmlNode> current() => stack.isEmpty ? root : stack.last.children;

  void addText(String raw) {
    if (raw.isEmpty) return;
    current().add(ReadmeHtmlNode.text(_decodeEntities(raw)));
  }

  var cursor = 0;
  for (final match in pattern.allMatches(html)) {
    addText(html.substring(cursor, match.start));
    cursor = match.end;

    final name = match.group(2)!.toLowerCase();
    final attrs = _parseAttributes(match.group(3) ?? '');

    if (match.group(1) == '/') {
      // 闭合：回退到最近的同名开标签，无匹配则忽略
      final index = stack.lastIndexWhere((it) => it.name == name);
      if (index < 0) continue;
      while (stack.length > index) {
        final frame = stack.removeLast();
        current().add(
          ReadmeHtmlNode.element(frame.name, frame.attrs, frame.children),
        );
      }
      continue;
    }

    if (match.group(4) == '/' || _voidTags.contains(name)) {
      current().add(ReadmeHtmlNode.element(name, attrs, const []));
      continue;
    }

    stack.add((name: name, attrs: attrs, children: <ReadmeHtmlNode>[]));
  }
  addText(html.substring(cursor));

  // 未闭合的标签收尾
  while (stack.isNotEmpty) {
    final frame = stack.removeLast();
    current().add(ReadmeHtmlNode.element(frame.name, frame.attrs, frame.children));
  }

  // 还有没被识别成标签的 `<`（残缺标签 / 裸小于号）时放弃，交给调用方剥标签
  if (html.replaceAll(pattern, '').contains('<')) return null;
  return root;
}

Map<String, String> _parseAttributes(String raw) {
  final map = <String, String>{};
  final pattern = RegExp(r'([a-zA-Z-]+)\s*=\s*"([^"]*)"');
  for (final match in pattern.allMatches(raw)) {
    map[match.group(1)!.toLowerCase()] = _decodeEntities(match.group(2)!);
  }
  // 无值属性（checked / open 等）
  for (final match in RegExp(r'(?:^|\s)([a-zA-Z-]+)(?=\s|$)').allMatches(raw)) {
    map.putIfAbsent(match.group(1)!.toLowerCase(), () => '');
  }
  return map;
}

String _decodeEntities(String text) => text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&times;', '×');

extension<T> on Iterable<T> {
  /// 第一个满足条件的元素（没有则 null）
  T? firstOrNullWhere(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
