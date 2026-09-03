class WindowsFileNameValidator {
  // Windows 禁止的文件名特殊字符
  static const Set<String> _invalidChars = {
    r'\',
    '/',
    ':',
    '*',
    '?',
    '"',
    '<',
    '>',
    '|',
  };

  // Windows 系统保留文件名（不区分大小写，含后缀如 .txt 也禁止）
  static const Set<String> _reservedNames = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// 校验文件名是否符合 Windows 规则
  /// 返回 null 表示合法，返回字符串表示错误原因
  static String? validate(String fileName) {
    // 1. 检查为空
    if (fileName.isEmpty) {
      return "文件名不能为空";
    }
    // 2. 检查长度（Windows 文件名+路径总长≤260，但单独文件名建议≤255）
    if (fileName.length > 255) {
      return "文件名长度不能超过 255 个字符";
    }
    // 3. 检查禁止字符
    for (final char in fileName.split('')) {
      if (_invalidChars.contains(char)) {
        return "不能含特殊字符：${_invalidChars.join(' ')}";
      }
    }
    // 4. 检查系统保留名（提取主文件名，忽略后缀，不区分大小写）
    final baseName = fileName.split('.').first.toUpperCase();
    if (_reservedNames.contains(baseName)) {
      return "不能是系统保留名：${_reservedNames.join(' ')}";
    }
    // 5. 检查首尾空格或句号
    if (fileName.startsWith(' ') ||
        fileName.endsWith(' ') ||
        fileName.startsWith('.') ||
        fileName.endsWith('.')) {
      return "文件名首尾不能是空格或句号";
    }
    // 所有规则通过
    return null;
  }

  /// 把文件名中的非法字符替换成 `_`，避免如 `xxx/xxx` 被当作路径拆分。
  ///
  /// 只替换非法字符，不处理扩展名（`.` 不在非法字符集内）；
  /// 替换后若只剩非法字符/空白/点号，则回退到占位名 `mod`，避免生成空文件。
  static String sanitizeFileName(String fileName) {
    final result = StringBuffer();
    for (final char in fileName.split('')) {
      result.write(_invalidChars.contains(char) ? '_' : char);
    }
    final name = result.toString();
    if (name.trim().isEmpty || RegExp(r'^[._\s]+$').hasMatch(name)) {
      return 'mod';
    }
    return name;
  }

  static String? tagValidate(String? tag) {
    if (tag == null||tag.isEmpty) return "名称不能为空";

    if (tag.length > 64) return "名称过长";

    final Set<String> invalidChars = {};
    for (final invalidChar in _invalidChars) {
      if (tag.contains(invalidChar)) {
        invalidChars.add(invalidChar);
      }
    }
    if (invalidChars.isNotEmpty) {
      return "不能有特殊字符 ${invalidChars.join(' ')}";
    }

    if (_reservedNames.contains(tag.toUpperCase())) return "非法字段";

    if (tag.endsWith(' ') || tag.startsWith(' ')) return "首尾不能为空格";

    if (tag.startsWith('.') || tag.endsWith('.')) return "首尾不能为句点";

    return null;
  }
}
