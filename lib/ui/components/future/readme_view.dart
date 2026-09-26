import 'dart:convert';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'readme_loader.dart';
import 'readme_source.dart';

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
/// - 图片交给 [ReadmeNetworkImage]（相对路径按仓库解析、支持 SVG 与徽章）
/// - 链接：绝对地址直接打开，相对路径按仓库拼成 GitHub 地址
class ReadmeView extends StatefulWidget {
  const ReadmeView({
    super.key,
    required this.data,
    required this.source,
    this.onLinkTap,
  });

  /// README 原文（markdown）
  final String data;

  /// 相对链接 / 相对图片按哪个仓库解析
  final ReadmeSource source;

  /// 覆盖默认的链接打开行为（默认用系统浏览器/内嵌 webview 打开）
  final void Function(String url)? onLinkTap;

  /// 把 README 里的链接解析成可打开的绝对地址。
  ///
  /// - `#anchor` → null（暂不支持页内跳转）
  /// - `https://…` / `mailto:` 等 → 原样
  /// - `./x.md`、`docs/x.md` → GitHub 仓库地址（按文件/目录判断 blob / tree）
  static String? resolveLink(ReadmeSource source, String href) {
    final link = href.trim();
    if (link.isEmpty || link.startsWith('#')) return null;
    if (Uri.tryParse(link)?.hasScheme ?? false) return link;
    if (link.startsWith('//')) return 'https:$link';

    final repo = 'https://github.com/${source.repo}';
    final branch = source.branch;
    final path = link.replaceFirst(RegExp(r'^\./'), '');
    if (path.endsWith('/')) return '$repo/tree/$branch/$path';
    // 有后缀（x.md / x.png）视为文件，无后缀视为目录
    return path.contains('.')
        ? '$repo/blob/$branch/$path'
        : '$repo/tree/$branch/$path';
  }

  /// 按 GitHub 的规则解析 README：
  ///
  /// - `ExtensionSet.gitHubFlavored`：表格 / 删除线 / 自动链接 / 任务清单 / 脚注定义
  /// - 额外启用 emoji 短代码（`:tada:`）与脚注引用——GitHub 都支持
  /// - `encodeHtml: false`：直写 HTML 以 `UnparsedContent` 原样给出，
  ///   由渲染器按 GitHub 的白名单自行处理（class/style 属性 GitHub 会剥掉，
  ///   所以 README 在 GitHub 上从来不依赖它们，这里也无需支持）
  @visibleForTesting
  static List<md.Node> parseMarkdown(String data) => _mergeHtmlContainers(
    md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
      // FootnoteRefSyntax 未被 markdown 包导出，脚注引用暂按字面文本处理
      inlineSyntaxes: [md.EmojiSyntax()],
    ).parseLines(const LineSplitter().convert(data)),
  );

  /// 可跨块包裹内容的开标签（GitHub 上 markdown 在这些标签内照常渲染）
  static const _openableContainers = {'div', 'center'};

  /// 跨块的 HTML 容器合并。
  ///
  /// CommonMark 的 HTML 块在空行处结束，所以 `<div align=center>`、
  /// `markdown 内容`、`</div>` 会成为三个独立块；GitHub 上由浏览器完成
  /// 标签配对把内容包进容器，这里在块间维持同样的开/闭上下文
  static List<md.Node> _mergeHtmlContainers(List<md.Node> blocks) {
    final out = <md.Node>[];
    final open = <md.Element>[];

    List<md.Node> current() => open.isEmpty ? out : open.last.children!;

    void closeOne() {
      if (open.isEmpty) return;
      final element = open.removeLast();
      current().add(element);
    }

    for (final node in blocks) {
      // 块级 HTML 在 markdown 7.x 里是 Text（内容为标签源码）
      final source = node is md.Text
          ? node.text.trim()
          : node is md.UnparsedContent
          ? node.textContent.trim()
          : null;

      // 纯闭标签：收掉最近一层容器
      final closeMatch = source == null
          ? null
          : RegExp(
              r'^\s*</\s*([a-zA-Z][a-zA-Z0-9]*)\s*>\s*$',
            ).firstMatch(source);
      if (closeMatch != null) {
        closeOne();
        current().add(node);
        continue;
      }

      // 纯开标签（可包裹容器）：压栈，后续块成为它的子内容
      final openMatch = source == null
          ? null
          : RegExp(
              r'^\s*<([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^<>]*?)?)>\s*$',
            ).firstMatch(source);
      if (openMatch != null &&
          _openableContainers.contains(openMatch.group(1)!.toLowerCase())) {
        open.add(
          md.Element(openMatch.group(1)!, <md.Node>[])
            ..attributes.addAll(_parseAttributes(openMatch.group(2) ?? '')),
        );
        continue;
      }
      current().add(node);
    }
    while (open.isNotEmpty) {
      closeOne();
    }
    return out;
  }

  /// 把行内节点序列按 `<br>` 拆成多行（空行会被丢弃，由调用方补空隙）
  @visibleForTesting
  static List<List<md.Node>> splitInlineOnBr(List<md.Node> nodes) {
    final lines = <List<md.Node>>[[]];
    for (final node in nodes) {
      final isBr =
          (node is md.Element && node.tag == 'br') ||
          (node is md.Text &&
              RegExp(
                r'^<br\s*/?>$',
                caseSensitive: false,
              ).hasMatch(node.text.trim()));
      if (isBr) {
        lines.add([]);
        continue;
      }
      lines.last.add(node);
    }
    return [
      for (final line in lines)
        if (line.isNotEmpty) line,
    ];
  }

  /// 直写 HTML 的小树 → markdown 风格节点（复用既有的块级 / 行内渲染）
  @visibleForTesting
  static List<md.Node> convertHtmlNode(ReadmeHtmlNode node) {
    if (node.tag == null) {
      return node.text.isEmpty ? const [] : [md.Text(node.text)];
    }
    switch (node.tag) {
      case 'br':
        return [md.Element.empty('br')];
      case 'hr':
        return [md.Element.empty('hr')];
      case 'img':
      case 'input':
        return [
          md.Element(node.tag!, null)..attributes.addAll(node.attributes),
        ];
      default:
        final children = [
          for (final child in node.children) ...convertHtmlNode(child),
        ];
        return [
          md.Element(node.tag!, children)..attributes.addAll(node.attributes),
        ];
    }
  }

  /// GitHub tagfilter 明确禁用、会转义成字面文本展示的标签
  static const _disallowedHtmlTags = {
    'iframe',
    'textarea',
    'style',
    'title',
    'xmp',
    'noembed',
    'noframes',
    'plaintext',
    'script',
  };

  /// 会开新块的直写 HTML 标签
  static const _blockHtmlTags = {
    'div',
    'p',
    'table',
    'ul',
    'ol',
    'details',
    'pre',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'dl',
    'center',
  };

  /// 行内 HTML 标签
  static const _inlineHtmlTags = {
    'a',
    'img',
    'b',
    'strong',
    'i',
    'em',
    'code',
    'del',
    's',
    'strike',
    'ins',
    'u',
    'br',
    'span',
    'sub',
    'sup',
    'kbd',
    'samp',
    'tt',
    'var',
    'mark',
    'q',
    'small',
    'font',
    'time',
    'abbr',
    'ruby',
    'rt',
    'rp',
    'bdi',
    'bdo',
    'wbr',
    'input',
  };

  /// HTML 小解析器（暴露出来给测试用）
  @visibleForTesting
  static List<ReadmeHtmlNode>? parseHtml(String html) => _parseHtml(html);

  @override
  State<ReadmeView> createState() => _ReadmeViewState();
}

class _ReadmeViewState extends State<ReadmeView> {
  /// 链接的点击识别器要在 dispose 里释放
  final _recognizers = <TapGestureRecognizer>[];

  late List<md.Node> _blocks = _parse(widget.data);

  @override
  void didUpdateWidget(covariant ReadmeView oldWidget) {
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

  List<md.Node> _parse(String data) => ReadmeView.parseMarkdown(data);

  ThemeData get _theme => Theme.of(context);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    //顶层也是「行内 + 块级」混排（如整段的直写 HTML 与裸图片行），统一走混排拆分
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: _buildMixedBlocks(_blocks, colors),
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
        return _alignWrap(
          node.attributes,
          _paragraph(node.children ?? const <md.Node>[], colors),
        );

      case 'ul':
      case 'ol':
        return _buildList(node, colors, depth: 0);

      case 'pre':
        return _buildCodeBlock(node);

      case 'blockquote':
        return _buildBlockquote(node, colors);

      case 'hr':
        return Divider(color: colors.border, height: 20);

      case 'table':
        return _alignWrap(node.attributes, _buildTable(node, colors));

      case 'details':
        return _buildDetails(node, colors);

      default:
        // 未知块级（div 等）：透明处理，只渲染内容；`<center>` 与 align 照常生效。
        // 内容是「行内 + 块级」混排的（div 里常见 <br> / 图片 / 链接），
        // 交给混排拆分器处理
        final children = node.children ?? const <md.Node>[];
        if (children.isEmpty) return null;
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: _buildMixedBlocks(children, colors),
        );
        final alignment = node.tag == 'center'
            ? Alignment.center
            : _alignOf(node.attributes);
        return alignment == null
            ? body
            : Align(alignment: alignment, child: body);
    }
  }

  /// 把「行内 + 块级」混排的节点列表拆成块：
  /// - 行内的聚成段落（按 `<br>` 断行，连续 `<br>` 出空隙）
  /// - 块级的递归 `_buildBlock`
  List<Widget> _buildMixedBlocks(List<md.Node> nodes, AppColors colors) {
    final widgets = <Widget>[];
    final inline = <md.Node>[];
    var inlineHasContent = false;

    void flushInline() {
      if (!inlineHasContent) {
        inline.clear();
        return;
      }
      for (final line in ReadmeView.splitInlineOnBr(inline)) {
        widgets.add(_paragraph(line, colors));
      }
      inline.clear();
      inlineHasContent = false;
    }

    for (final node in nodes) {
      if (node is md.UnparsedContent) {
        // 直写 HTML：含块级标签就当块处理，否则并入行内
        final tree = _parseHtml(node.textContent);
        final isBlockHtml =
            tree != null &&
            tree.any(
              (it) =>
                  it.tag != null &&
                  ReadmeView._blockHtmlTags.contains(it.tag) &&
                  // 纯 `<br>` 不算块
                  it.tag != 'br',
            );
        if (isBlockHtml) {
          flushInline();
          final converted = [
            for (final it in tree) ...ReadmeView.convertHtmlNode(it),
          ];
          widgets.addAll(_buildMixedBlocks(converted, colors));
          continue;
        }
        inline.add(node);
        inlineHasContent = true;
        continue;
      }
      if (node is md.Text) {
        if (node.text.trim().isEmpty) continue;
        inline.add(node);
        inlineHasContent = true;
        continue;
      }
      if (node is md.Element && node.tag == 'br') {
        // 行内的 <br>：先结束当前段落，连续出现时产生空隙
        if (inlineHasContent) {
          for (final line in ReadmeView.splitInlineOnBr(inline)) {
            widgets.add(_paragraph(line, colors));
          }
          inline.clear();
          inlineHasContent = false;
        }
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      if (node is md.Element &&
          !ReadmeView._inlineHtmlTags.contains(node.tag)) {
        flushInline();
        if (_buildBlock(node, colors) case final widget?) {
          widgets.add(widget);
        }
        continue;
      }
      inline.add(node);
      inlineHasContent = true;
    }
    flushInline();
    return widgets;
  }

  /// GitHub 提示框：引用块以 `[!NOTE]` / `[!TIP]` / `[!IMPORTANT]` /
  /// `[!WARNING]` / `[!CAUTION]` 开头时渲染成带图标的色块
  Widget _buildBlockquote(md.Element node, AppColors colors) {
    final children = [...(node.children ?? const <md.Node>[])];

    // 检测 alert 标记（在第一个段落的首个文本里）
    (String, Color, IconData)? alert;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is! md.Element || child.tag != 'p') continue;
      final pChildren = [...(child.children ?? const <md.Node>[])];
      for (var j = 0; j < pChildren.length; j++) {
        final it = pChildren[j];
        if (it is! md.Text) continue;
        final match = RegExp(
          r'^\s*\[!(note|tip|important|warning|caution)\]\s*',
          caseSensitive: false,
        ).firstMatch(it.text);
        if (match == null) break;
        final kind = match.group(1)!.toLowerCase();
        alert = switch (kind) {
          'note' => ('NOTE', const Color(0xFF4493F8), Icons.info_outline),
          'tip' => ('TIP', const Color(0xFF3FB950), Icons.lightbulb_outline),
          'important' => (
            'IMPORTANT',
            const Color(0xFFAB7DF8),
            Icons.priority_high_outlined,
          ),
          'warning' => (
            'WARNING',
            const Color(0xFFD29922),
            Icons.warning_amber_outlined,
          ),
          _ => ('CAUTION', const Color(0xFFF85149), Icons.report_outlined),
        };
        // 去掉标记文本（含其后的换行）
        final rest = it.text
            .substring(match.end)
            .replaceFirst(RegExp(r'^\n+'), '');
        if (rest.isEmpty) {
          pChildren.removeAt(j);
        } else {
          pChildren[j] = md.Text(rest);
        }
        children[i] = md.Element('p', pChildren)
          ..attributes.addAll(child.attributes);
        break;
      }
      break;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: _buildMixedBlocks(children, colors),
    );

    if (alert == null) {
      return Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.border, width: 3)),
        ),
        child: body,
      );
    }

    final (title, color, icon) = alert;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(icon, size: 16, color: color),
              Text(
                title,
                style: _theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          body,
        ],
      ),
    );
  }

  /// `align="center|left|right"` → 对齐方式（GitHub 白名单里保留的属性，
  /// class/style 会被 GitHub 剥掉，所以 README 只会靠 align 做布局）
  Alignment? _alignOf(Map<String, String> attributes) =>
      switch (attributes['align']?.toLowerCase()) {
        'center' => Alignment.center,
        'left' => Alignment.centerLeft,
        'right' => Alignment.centerRight,
        _ => null,
      };

  Widget _alignWrap(Map<String, String> attributes, Widget child) {
    final alignment = _alignOf(attributes);
    return alignment == null
        ? child
        : Align(alignment: alignment, child: child);
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

      // li 的子节点分三类：子列表 / 块级（段落、代码块、表格…）/ 行内。
      // 块级必须单独成块，否则「标题 + 空行 + 图片」会被压到同一行
      final nested = <md.Element>[];
      final blocks = <md.Node>[];
      final inline = <md.Node>[];
      for (final it in rest) {
        if (it is md.Element && (it.tag == 'ul' || it.tag == 'ol')) {
          nested.add(it);
        } else if (it is md.Element &&
            !ReadmeView._inlineHtmlTags.contains(it.tag)) {
          blocks.add(it);
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
                    if (inline.isNotEmpty)
                      Text.rich(
                        TextSpan(
                          children: _inlines(inline, colors),
                          style: _theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      ),
                    for (final block in blocks) ?_buildBlock(block, colors),
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
                    children: _inlines(
                      cell.children ?? const <md.Node>[],
                      colors,
                    ),
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
            children: [for (final child in rest) ?_buildBlock(child, colors)],
          ),
        ],
      ),
    );
  }

  // ── 行内 ──

  List<InlineSpan> _inlines(
    List<md.Node> nodes,
    AppColors colors, {
    String? linkUrl,
  }) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      // markdown 7.x 把行内直写 HTML 放在 Text 里（源码形式），
      // 交给 HTML 渲染（<br> / <b> / <a><img> 都在这类节点里）
      if (node is md.Text && _looksLikeHtml(node.text)) {
        _appendHtml(node.text, colors, spans, linkUrl: linkUrl);
        continue;
      }
      _appendInline(node, colors, spans, linkUrl: linkUrl);
    }
    return spans;
  }

  static final _looksLikeHtmlPattern = RegExp(r'<\s*/?\s*[a-zA-Z]');

  /// 段内软换行按 markdown 语义折叠为空格（硬换行走 Element('br')，不受影响）
  static String _plainText(String text) => text.replaceAll('\n', ' ');

  bool _looksLikeHtml(String text) => _looksLikeHtmlPattern.hasMatch(text);

  void _appendInline(
    md.Node node,
    AppColors colors,
    List<InlineSpan> spans, {
    String? linkUrl,
  }) {
    if (node is md.Text) {
      if (node.text.isNotEmpty) {
        spans.add(TextSpan(text: _plainText(node.text)));
      }
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
      case 's':
      case 'strike':
        spans.add(
          TextSpan(
            children: _inlines(children, colors),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      case 'ins':
      case 'u':
        spans.add(
          TextSpan(
            children: _inlines(children, colors),
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      case 'kbd':
      case 'samp':
      case 'tt':
      case 'var':
        spans.add(
          TextSpan(
            children: _inlines(children, colors),
            style: _theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        );
      case 'mark':
        spans.add(
          TextSpan(
            children: _inlines(children, colors),
            style: TextStyle(
              backgroundColor: _theme.colorScheme.secondaryContainer,
            ),
          ),
        );
      case 'q':
        final quoted = _inlines(children, colors);
        spans.add(
          TextSpan(
            children: [
              const TextSpan(text: '“'),
              ...quoted,
              const TextSpan(text: '”'),
            ],
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
            : ReadmeView.resolveLink(widget.source, href);
        final text = _inlines(children, colors, linkUrl: url);
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
        spans.add(_imageSpan(node, colors, linkUrl: linkUrl));
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
  void _appendHtml(
    String html,
    AppColors colors,
    List<InlineSpan> spans, {
    String? linkUrl,
  }) {
    final tree = _parseHtml(html);
    if (tree == null) {
      final plain = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (plain.isNotEmpty) spans.add(TextSpan(text: plain));
      return;
    }
    for (final node in tree) {
      _renderHtmlNode(node, colors, spans, linkUrl: linkUrl);
    }
  }

  void _renderHtmlNode(
    ReadmeHtmlNode node,
    AppColors colors,
    List<InlineSpan> spans, {
    String? linkUrl,
  }) {
    if (node.tag == null) {
      if (node.text.isNotEmpty) {
        spans.add(TextSpan(text: _plainText(node.text)));
      }
      return;
    }

    // GitHub tagfilter：这些标签会被转义成字面文本展示
    if (ReadmeView._disallowedHtmlTags.contains(node.tag)) {
      spans.add(TextSpan(text: '<${node.tag}>${node.rawText}</${node.tag}>'));
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
      case 's':
      case 'strike':
      case 'del':
        spans.add(
          TextSpan(
            children: children(),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      case 'ins':
      case 'u':
        spans.add(
          TextSpan(
            children: children(),
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      case 'kbd':
      case 'samp':
      case 'tt':
      case 'var':
        spans.add(
          TextSpan(
            children: children(),
            style: _theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        );
      case 'mark':
        spans.add(
          TextSpan(
            children: children(),
            style: TextStyle(
              backgroundColor: _theme.colorScheme.secondaryContainer,
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
            : ReadmeView.resolveLink(widget.source, href);
        final childSpans = <InlineSpan>[];
        for (final child in node.children) {
          _renderHtmlNode(child, colors, childSpans, linkUrl: url);
        }
        spans.add(
          TextSpan(
            children: childSpans,
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
            linkUrl: linkUrl,
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

  InlineSpan _imageSpan(md.Element node, AppColors colors, {String? linkUrl}) {
    final src = node.attributes['src'];
    if (src == null || src.trim().isEmpty) {
      return const TextSpan(text: '');
    }
    final width = double.tryParse(node.attributes['width'] ?? '');
    final height = double.tryParse(node.attributes['height'] ?? '');
    return _imageSpanOf(src, width, height, colors, linkUrl: linkUrl);
  }

  InlineSpan _imageSpanOf(
    String src,
    double? width,
    double? height,
    AppColors colors, {
    String? linkUrl,
  }) {
    final uri = Uri.tryParse(src.trim());
    if (uri == null) return const TextSpan(text: '');

    Widget image = ReadmeNetworkImage(
      uri: uri,
      source: widget.source,
      width: width,
      height: height,
      onError: Icon(
        Icons.broken_image_outlined,
        size: 16,
        color: colors.itemHint,
      ),
    );

    // <a><img></a>：图片是真实 widget，父 TextSpan 的 recognizer 管不到它，
    // 必须自己包手势才能点击
    if (linkUrl != null) {
      image = GestureDetector(onTap: () => _openLink(linkUrl), child: image);
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: image,
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

  /// 还原成源码文本（GitHub tagfilter 的字面展示用）
  String get rawText => tag == null
      ? text
      : '<$tag${attributes.entries.map((it) => ' ${it.key}="${it.value}"').join()}>'
            '${children.map((child) => child.rawText).join()}</$tag>';
}

/// 自闭合（无内容）标签
const _voidTags = {'br', 'hr', 'img', 'input', 'meta', 'link', 'wbr', 'source'};

/// 把 HTML 片段解析成节点树；含注释 / 残缺标签等无法处理时返回 null
List<ReadmeHtmlNode>? _parseHtml(String html) {
  if (html.contains('<!--') || html.contains('<?')) return null;

  final pattern = RegExp(
    r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^<>]*?)?)\s*(/?)\s*>',
  );
  final root = <ReadmeHtmlNode>[];
  final stack =
      <
        ({
          String name,
          Map<String, String> attrs,
          List<ReadmeHtmlNode> children,
        })
      >[];

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
    current().add(
      ReadmeHtmlNode.element(frame.name, frame.attrs, frame.children),
    );
  }

  // 还有没被识别成标签的 `<`（残缺标签 / 裸小于号）时放弃，交给调用方剥标签
  if (html.replaceAll(pattern, '').contains('<')) return null;
  return root;
}

Map<String, String> _parseAttributes(String raw) {
  final map = <String, String>{};
  // 带值属性：双引号 / 单引号 / 裸值（GitHub 上常见 `align = center` 这种无引号写法）
  final pattern = RegExp(
    r'([a-zA-Z-]+)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s"<>\x27]+))',
  );
  var rest = raw;
  for (final match in pattern.allMatches(raw)) {
    final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    map[match.group(1)!.toLowerCase()] = _decodeEntities(value);
    rest = rest.replaceFirst(match.group(0)!, ' ');
  }
  // 无值属性（checked / open 等）：只在去掉带值属性后的剩余部分里找
  for (final match in RegExp(
    r'(?:^|\s)([a-zA-Z-]+)(?=\s|$)',
  ).allMatches(rest)) {
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
