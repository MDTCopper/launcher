import 'dart:io';

// 需要排除的目录
const excludeDirs = {
  'build',
  '.dart_tool',
  '.git',
  '.idea',
  '.gradle',
  'ios',
  'android',
  'node_modules',
  '.opencode',
};

// 需要统计的文件后缀
const targetExtensions = {
  '.dart',
  '.kt',
  '.kts',
  '.java',
  '.swift',
  '.cpp',
  '.c',
  '.h',
  '.hpp',
  '.py',
  '.js',
  '.ts',
  '.tsx',
  '.jsx',
  '.rs',
  '.go',
  '.xml',
  '.gradle',
};

// 过滤注释和空行的正则表达式
final commentAndEmptyRegex = RegExp(r'^\s*(//.*|/\*|\*/|\*.*|)$');

Future<void> main() async {
  final dir = Directory.current;
  final List<Map<String, dynamic>> fileCounts = [];
  int totalLines = 0;

  // 递归遍历文件
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      final path = entity.path;

      // 检查是否在排除的目录中
      if (excludeDirs.any(
        (dir) => path.contains(
          Platform.pathSeparator + dir + Platform.pathSeparator,
        ),
      )) {
        continue;
      }

      // 检查文件后缀
      final ext = '.${path.split('.').last}';
      if (!targetExtensions.contains(ext)) continue;

      // 读取文件并过滤空行和注释
      try {
        final lines = await entity.readAsLines();
        final validLines = lines
            .where((line) => !commentAndEmptyRegex.hasMatch(line))
            .length;

        if (validLines > 0) {
          fileCounts.add({'file': path, 'lines': validLines});
          totalLines += validLines;
        }
      } catch (e) {
        // 忽略无法读取的文件
      }
    }
  }

  // 按行数降序排序并取前 20 个
  fileCounts.sort((a, b) => b['lines'].compareTo(a['lines']));

  stdout.writeln('🔝 Top 20 Files by Lines of Code:');
  stdout.writeln('-' * 60);
  for (var i = 0; i < fileCounts.length && i < 20; i++) {
    stdout.writeln(
      '${fileCounts[i]['lines'].toString().padLeft(6)}  ${fileCounts[i]['file']}',
    );
  }

  stdout.writeln('-' * 60);
  stdout.writeln('📊 TOTAL VALID LINES: $totalLines');
}
