import 'package:copper_launcher/data/models.dart';

/// README 渲染要的「来源」：解析相对链接与相对图片时用到的仓库与分支
///
/// 渲染器本身与模组无关 —— 模组 README 与启动器更新说明共用同一套渲染器，
/// 各自给出自己的仓库；不用为了渲染去造一条假的模组条目
class ReadmeSource {
  const ReadmeSource({required this.repo, this.branch = 'main'});

  /// `owner/repo`：相对路径按它拼成 GitHub 地址
  final String repo;

  /// 相对路径按哪个分支解析
  final String branch;

  /// 模组的来源：分支取条目上缓存的分支探测结果，没有就按 main
  factory ReadmeSource.ofMod(ModOfficialListEntry mod) =>
      ReadmeSource(repo: mod.repo, branch: mod.mainBranchCache ?? 'main');
}
