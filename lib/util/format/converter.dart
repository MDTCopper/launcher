


String convertToMarkdownFrom(String html) {
    if (html.isEmpty) return html;

    String md = html;

    // 1. 处理换行符: <br> -> 换行
    // GitHub 风格的 Markdown 中，<br> 通常表示硬换行
    md = md.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    // 2. 处理标题: <h1>...<h6> -> # ...
    // 注意：这里使用简单的替换，实际渲染中 MarkdownBody 也能直接识别 <h1> 等标签，
    // 但为了纯文本一致性，我们将其转换。
    md = md.replaceAll(RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false), '# \$1\n');
    md = md.replaceAll(RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false), '## \$1\n');
    md = md.replaceAll(RegExp(r'<h3[^>]*>(.*?)</h3>', caseSensitive: false), '### \$1\n');
    md = md.replaceAll(RegExp(r'<h4[^>]*>(.*?)</h4>', caseSensitive: false), '#### \$1\n');

    // 3. 处理粗体: <b> 或 <strong> -> **...**
    // 使用非贪婪匹配 (.*?)
    md = md.replaceAll(RegExp(r'<(b|strong)[^>]*>(.*?)</\1>', caseSensitive: false), '**\$2**');

    // 4. 处理斜体: <i> 或 <em> -> *...*
    md = md.replaceAll(RegExp(r'<(i|em)[^>]*>(.*?)</\1>', caseSensitive: false), '*\$2*');

    // 5. 处理代码块: <code> -> `...`
    // 注意：如果存在 <pre><code>，这个正则可能会产生多余的反引号，但通常无害
    md = md.replaceAllMapped(RegExp(r'<code[^>]*>(.*?)</code>', caseSensitive: false), (Match m) {
      String content = m.group(1) ?? '';
      if (content.contains('`')) return '`\$content`';
      return '`\$content`';
    });

    // 6. 处理图片: <img src="..." alt="..."> -> ![alt](src)
    // 提取 src 和 alt 属性
    md = md.replaceAllMapped(RegExp(r'<img[^>]*src="([^"]*)"[^>]*(?:alt="([^"]*)")?[^>]*/?>', caseSensitive: false), (Match m) {
      String src = m.group(1) ?? '';
      String alt = m.group(2) ?? '';
      return '![$alt]($src)';
    });

    // 兼容 alt 在 src 前面的情况
    md = md.replaceAllMapped(RegExp(r'<img[^>]*alt="([^"]*)"[^>]*(?:src="([^"]*)")?[^>]*/?>', caseSensitive: false), (Match m) {
      String alt = m.group(1) ?? '';
      String src = m.group(2) ?? '';
      return '![$alt]($src)';
    });

    // 7. 处理链接: <a href="...">...</a> -> [...]
    md = md.replaceAllMapped(RegExp(r'<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>', caseSensitive: false), (Match m) {
      String href = m.group(1) ?? '';
      String text = m.group(2) ?? '';
      // 如果链接文本本身就是图片 Markdown，需要特殊处理，这里做简化处理
      return '[$text]($href)';
    });

    // 8. 处理段落: <p> -> 双换行
    // 将 </p> 替换为两个换行符，以区分段落
    md = md.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    md = md.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '');

    // 9. 清理剩余的 HTML 标签
    // 移除所有未被上述规则处理的标签 (如 <div>, <span> 等)
    md = md.replaceAll(RegExp(r'<[^>]+>'), '');

    // 10. 格式化清理
    // 移除连续的空行 (超过 2 个换行符的缩减为 2 个)
    md = md.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // 移除首尾空白
    md = md.trim();

    return md;
  }
