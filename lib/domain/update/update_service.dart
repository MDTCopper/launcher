import '../../core/app_config.dart';
import '../../data/models.dart';
import '../../util/format/string_cleaner.dart';
import '../../util/io/log.dart';
import 'game_version_update.dart';
import 'loader_update.dart';
import 'mod_update.dart';
import 'update_models.dart';

/// 统一更新入口：一次检查模组 / 游戏版本 / 加载器
///
/// 各类检查互相独立，某一类失败（断网 / 限流 / 解析失败）只落进 [UpdateReport.errors]，
/// 不影响其他类的结果
class UpdateService {
  /// 全量检查
  ///
  /// - [gameVersion]：检查哪个游戏版本数据目录里的模组（通常是当前选中版本）；
  ///   不传就跳过模组这一路
  /// - [installedVersions]：游戏版本检查要对比的本机版本记录；不传取当前配置
  /// - [refresh]：忽略数据索引缓存，强制重拉
  /// - [onModProgress]：模组检查进度（已检查 / 总数）
  static Future<UpdateReport> checkAll({
    Mindustry? gameVersion,
    Iterable<Mindustry>? installedVersions,
    bool refresh = false,
    void Function(int done, int total)? onModProgress,
  }) async {
    final versions = installedVersions ?? allInstalledVersions();
    final errors = <UpdateContentKind, String>{};

    // 三路同时开跑，各自把异常收成一条错误
    final modFuture = _guard<ModUpdateCheck>(() async {
      if (gameVersion == null) return const ModUpdateCheck();
      return ModUpdateService.checkInstalled(
        gameVersion: gameVersion,
        refresh: refresh,
        onProgress: onModProgress,
      );
    });
    final gameVersionFuture = _guard<GameVersionCheck>(
      () =>
          GameVersionUpdateService.check(installed: versions, refresh: refresh),
    );
    final loaderFuture = _guard<LoaderUpdateCheck>(LoaderUpdateService.check);

    final modRun = await modFuture;
    final gameVersionRun = await gameVersionFuture;
    final loaderRun = await loaderFuture;

    _collectError(
      errors,
      UpdateContentKind.mod,
      modRun.error ?? modRun.value?.error,
    );
    _collectError(
      errors,
      UpdateContentKind.gameVersion,
      gameVersionRun.error ?? gameVersionRun.value?.error,
    );
    _collectError(
      errors,
      UpdateContentKind.loader,
      loaderRun.error ?? loaderRun.value?.error,
    );

    final loaderUpdate = loaderRun.value?.update;
    return UpdateReport(
      mods: modRun.value?.mods ?? const [],
      gameVersions: gameVersionRun.value?.updates ?? const [],
      loaders: [?loaderUpdate],
      checkedModCount: modRun.value?.checkedCount ?? 0,
      skippedModCount: modRun.value?.skippedCount ?? 0,
      errors: errors,
    );
  }

  /// 当前配置里的全部游戏版本记录（跨分类目录）
  static Iterable<Mindustry> allInstalledVersions() =>
      config.versionOptions.versionFolds.expand((fold) => fold.versions);

  static void _collectError(
    Map<UpdateContentKind, String> errors,
    UpdateContentKind kind,
    String? message,
  ) {
    if (message == null) return;
    errors[kind] = message;
    addLog(
      .warning,
      '${kind.name} 更新检查失败：${removeNewlines(message)}',
      tag: 'Update',
    );
  }

  /// 跑一次可能抛异常的检查，异常转成一句可展示的错误
  static Future<({T? value, String? error})> _guard<T>(
    Future<T> Function() run,
  ) async {
    try {
      return (value: await run(), error: null);
    } catch (error) {
      return (value: null, error: '$error');
    }
  }
}
