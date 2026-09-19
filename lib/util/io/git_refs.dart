import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// git 的 ref 广告：只取 tag，**不消耗 GitHub API 的匿名额度**
///
/// 地址形如 `https://github.com/<owner>/<repo>.git/info/refs?service=git-upload-pack`，
/// 响应用 pkt-line 编码（每行 4 位十六进制长度 + 内容），这里只挑 `refs/tags/*`
///
/// 只对它 tag 规整的仓库有用（Mindustry / loader 这类按版本打 tag 的）；
/// mod 的 tag 五花八门，解析不可靠，不要往这上面靠
class GitRefs {
  /// 取 [repo]（`owner/name`）的全部 tag
  static Future<List<String>> fetchTags(String repo) async {
    //固定按纯文本取：ref 广告是 pkt-line 不是 JSON，别让 dio 按 content-type 去解
    final response = await cio.get<String>(
      'https://github.com/$repo.git/info/refs?service=git-upload-pack',
      headers: const {'User-Agent': 'CopperLauncher'},
      responseType: ResponseType.plain,
    );
    if (response.statusCode != 200) {
      throw Exception('获取 $repo 的 tag 失败：HTTP ${response.statusCode}');
    }
    return parseTags(response.data ?? '');
  }

  /// 从 ref 广告里解析 tag 名（纯函数，便于用例覆盖）
  ///
  /// 一行形如 `003f<sha> refs/tags/v146`；带 `^{}` 的是同 tag 的解引用条目，去掉后去重
  @visibleForTesting
  static List<String> parseTags(String body) {
    const marker = 'refs/tags/';
    final tags = <String>[];
    final seen = <String>{};

    for (final rawLine in body.split('\n')) {
      var line = rawLine;
      //剥掉 pkt-line 的长度前缀（4 位十六进制）
      final prefix = line.length >= 4 ? line.substring(0, 4) : '';
      if (prefix.isNotEmpty && int.tryParse(prefix, radix: 16) != null) {
        line = line.substring(4);
      }

      final index = line.indexOf(marker);
      if (index < 0) continue;
      var tag = line.substring(index + marker.length);
      //首个 ref 行后面跟着 NUL 与能力列表，一并切掉
      final terminator = tag.indexOf('\u0000');
      if (terminator >= 0) tag = tag.substring(0, terminator);
      tag = tag.trim();
      if (tag.endsWith('^{}')) tag = tag.substring(0, tag.length - 3);
      tag = tag.trim();
      if (tag.isEmpty || !seen.add(tag)) continue;
      tags.add(tag);
    }
    return tags;
  }
}
