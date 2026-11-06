import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'template_media.dart';
import 'template_skin.dart';

/// 轻量 Markdown 渲染（不引第三方包）：标题 / 段落 / 列表 / 代码块 / 引用 / 分隔线 / 行内样式
///
/// 覆盖度审计 P2-25：模组详情的 README 展示。刻意只做「读得舒服」这一层——
/// 表格、HTML、脚注这类留给真正的网页视图，这里不追
class TemplateMarkdown extends StatelessWidget {
  const TemplateMarkdown({
    super.key,
    required this.skin,
    required this.data,
    this.onLinkTap,
  });

  final TemplateSkin skin;
  final String data;

  /// 链接点击；不给就只显示成强调色文字
  final void Function(String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.md,
      children: [for (final block in blocks) _buildBlock(context, block)],
    );
  }

  // ── 解析 ──

  List<_MdBlock> _parse(String source) {
    final blocks = <_MdBlock>[];
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final paragraph = <String>[];
    final list = <String>[];
    var listOrdered = false;

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_MdParagraph(paragraph.join(' ')));
      paragraph.clear();
    }

    void flushList() {
      if (list.isEmpty) return;
      blocks.add(_MdList(List.of(list), ordered: listOrdered));
      list.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // 代码块
      if (trimmed.startsWith('```')) {
        flushParagraph();
        flushList();
        final language = trimmed.substring(3).trim();
        final code = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          code.add(lines[i]);
          i++;
        }
        blocks.add(_MdCode(code.join('\n'), language: language));
        continue;
      }

      if (trimmed.isEmpty) {
        flushParagraph();
        flushList();
        continue;
      }

      // 分隔线
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        flushParagraph();
        flushList();
        blocks.add(const _MdDivider());
        continue;
      }

      // 标题
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        flushList();
        blocks.add(
          _MdHeading(heading.group(2)!.trim(), heading.group(1)!.length),
        );
        continue;
      }

      // 引用
      if (trimmed.startsWith('>')) {
        flushParagraph();
        flushList();
        blocks.add(_MdQuote(trimmed.replaceFirst(RegExp(r'^>\s?'), '')));
        continue;
      }

      // 图片（README 里的 shields 徽章也走这条）→ 小徽章占位
      final image = RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(trimmed);
      if (image != null) {
        flushParagraph();
        flushList();
        blocks.add(
          _MdImage(alt: image.group(1) ?? '', url: image.group(2) ?? ''),
        );
        continue;
      }

      // 列表
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        if (list.isNotEmpty && listOrdered) flushList();
        listOrdered = false;
        list.add(bullet.group(1)!);
        continue;
      }
      final ordered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
      if (ordered != null) {
        flushParagraph();
        if (list.isNotEmpty && !listOrdered) flushList();
        listOrdered = true;
        list.add(ordered.group(1)!);
        continue;
      }

      flushList();
      paragraph.add(trimmed);
    }
    flushParagraph();
    flushList();
    return blocks;
  }

  Widget _buildBlock(BuildContext context, _MdBlock block) {
    return switch (block) {
      _MdHeading() => _heading(block),
      _MdParagraph() => _paragraph(block.text),
      _MdList() => _listBlock(block),
      _MdCode() => _codeBlock(block),
      _MdQuote() => _quoteBlock(block),
      _MdDivider() => Container(height: 1, color: skin.border),
      _MdImage() => _imageBlock(block),
    };
  }

  Widget _heading(_MdHeading heading) {
    final style = switch (heading.level) {
      1 => TemplateType.page.copyWith(
        color: skin.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      2 => TemplateType.section.copyWith(
        color: skin.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      _ => TemplateType.item.copyWith(
        color: skin.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    };
    return Padding(
      padding: EdgeInsets.only(top: heading.level <= 2 ? TemplateSpace.xs : 0),
      child: _inline(heading.text, style),
    );
  }

  Widget _paragraph(String text) {
    return _inline(
      text,
      TemplateType.caption.copyWith(color: skin.textSecondary, height: 20 / 12),
    );
  }

  Widget _listBlock(_MdList list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.xs,
      children: [
        for (var i = 0; i < list.items.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.sm,
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  list.ordered ? '${i + 1}.' : '•',
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: _inline(
                  list.items[i],
                  TemplateType.caption.copyWith(
                    color: skin.textSecondary,
                    height: 20 / 12,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _codeBlock(_MdCode code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TemplateSpace.md),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        border: Border.all(color: skin.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.xs,
        children: [
          if (code.language.isNotEmpty)
            Text(
              code.language,
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
            ),
          SelectableText(
            code.text,
            style: TemplateType.caption.copyWith(
              color: skin.textSecondary,
              height: 18 / 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quoteBlock(_MdQuote quote) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.sm,
      ),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
        border: Border(left: BorderSide(color: skin.accent, width: 3)),
      ),
      child: _inline(
        quote.text,
        TemplateType.caption.copyWith(color: skin.textSecondary),
      ),
    );
  }

  Widget _imageBlock(_MdImage image) {
    // README 里的 shields 徽章：渲染成一个小胶囊而不是去拉网络图
    final isBadge = image.url.contains('shields.io');
    if (isBadge) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: TemplateSpace.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: skin.sunken,
            borderRadius: BorderRadius.circular(TemplateRadius.pill),
            border: Border.all(color: skin.border),
          ),
          child: Text(
            image.alt.isEmpty ? 'badge' : image.alt,
            style: TemplateType.micro.copyWith(color: skin.textSecondary),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TemplateImageBox(
        skin: skin,
        size: 96,
        image: image.url,
        icon: Icons.image_outlined,
      ),
    );
  }

  /// 行内解析：`**粗**`、`` `代码` ``、`[文字](链接)`
  Widget _inline(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)');
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: TextStyle(
              backgroundColor: skin.sunken,
              color: skin.textPrimary,
            ),
          ),
        );
      } else {
        final label = match.group(3)!;
        final url = match.group(4)!;
        spans.add(
          TextSpan(
            text: label,
            style: style.copyWith(color: skin.accentText),
            recognizer: onLinkTap == null
                ? null
                : (TapGestureRecognizer()..onTap = () => onLinkTap!(url)),
          ),
        );
      }
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

// ── 块模型 ──

sealed class _MdBlock {
  const _MdBlock();
}

class _MdHeading extends _MdBlock {
  const _MdHeading(this.text, this.level);

  final String text;
  final int level;
}

class _MdParagraph extends _MdBlock {
  const _MdParagraph(this.text);

  final String text;
}

class _MdList extends _MdBlock {
  const _MdList(this.items, {required this.ordered});

  final List<String> items;
  final bool ordered;
}

class _MdCode extends _MdBlock {
  const _MdCode(this.text, {required this.language});

  final String text;
  final String language;
}

class _MdQuote extends _MdBlock {
  const _MdQuote(this.text);

  final String text;
}

class _MdDivider extends _MdBlock {
  const _MdDivider();
}

class _MdImage extends _MdBlock {
  const _MdImage({required this.alt, required this.url});

  final String alt;
  final String url;
}
