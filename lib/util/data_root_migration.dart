/// 数据根迁移的占位
///
/// 0.3.0 允许破坏性变更，旧安装的版本 / 存档 / 配置不自动搬移，这里暂时不动数据；
/// 正式版需要从 alpha 的数据根迁移时，再补 `migrate` 与 `runIfNeeded` 的判据。
/// 届时的三类不搬：`bridge/`（exec / dlopen 只允许应用内部目录，见 `AppPaths.bridgeRoot`）、
/// `logs/`、`tmp/`
class DataRootMigration {
  DataRootMigration._();

  /// 生产入口：当前不做迁移
  static Future<DataRootMigrationReport?> runIfNeeded() async => null;
}

/// 一次迁移的结果（给启动日志用）
class DataRootMigrationReport {
  final List<String> moved = [];
  final List<String> skippedExisting = [];
  final Map<String, String> failed = {};

  bool get didAnything => moved.isNotEmpty;

  /// 一句话汇报；什么都没发生时返回 null（调用方据此决定记不记日志）
  String? describe() {
    if (moved.isEmpty && skippedExisting.isEmpty && failed.isEmpty) return null;
    final parts = <String>[
      if (moved.isNotEmpty) '已搬入 ${moved.join('、')}',
      if (skippedExisting.isNotEmpty) '目标已有跳过 ${skippedExisting.join('、')}',
      if (failed.isNotEmpty)
        '失败 ${failed.entries.map((it) => '${it.key}（${it.value}）').join('、')}',
    ];
    return parts.join('；');
  }
}
