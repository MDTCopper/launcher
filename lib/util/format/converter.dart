String convertToMarkdownFrom(String html) {
  if (html.isEmpty) return html;

  String md = html;

  md = md.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  md = md.replaceAll(
    RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false),
    '# \$1\n',
  );
  md = md.replaceAll(
    RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false),
    '## \$1\n',
  );
  md = md.replaceAll(
    RegExp(r'<h3[^>]*>(.*?)</h3>', caseSensitive: false),
    '### \$1\n',
  );
  md = md.replaceAll(
    RegExp(r'<h4[^>]*>(.*?)</h4>', caseSensitive: false),
    '#### \$1\n',
  );

  md = md.replaceAll(
    RegExp(r'<(b|strong)[^>]*>(.*?)</\1>', caseSensitive: false),
    '**\$2**',
  );

  md = md.replaceAll(
    RegExp(r'<(i|em)[^>]*>(.*?)</\1>', caseSensitive: false),
    '*\$2*',
  );

  md = md.replaceAllMapped(
    RegExp(r'<code[^>]*>(.*?)</code>', caseSensitive: false),
    (Match m) {
      String content = m.group(1) ?? '';
      if (content.contains('`')) return '`\$content`';
      return '`\$content`';
    },
  );

  md = md.replaceAllMapped(
    RegExp(
      r'<img[^>]*src="([^"]*)"[^>]*(?:alt="([^"]*)")?[^>]*/?>',
      caseSensitive: false,
    ),
    (Match m) {
      String src = m.group(1) ?? '';
      String alt = m.group(2) ?? '';
      return '![$alt]($src)';
    },
  );

  md = md.replaceAllMapped(
    RegExp(
      r'<img[^>]*alt="([^"]*)"[^>]*(?:src="([^"]*)")?[^>]*/?>',
      caseSensitive: false,
    ),
    (Match m) {
      String alt = m.group(1) ?? '';
      String src = m.group(2) ?? '';
      return '![$alt]($src)';
    },
  );

  md = md.replaceAllMapped(
    RegExp(r'<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>', caseSensitive: false),
    (Match m) {
      String href = m.group(1) ?? '';
      String text = m.group(2) ?? '';

      return '[$text]($href)';
    },
  );

  md = md.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
  md = md.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '');

  md = md.replaceAll(RegExp(r'<[^>]+>'), '');

  md = md.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  md = md.trim();

  return md;
}
