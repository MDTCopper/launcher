/// 云存档 UI 的固定文案（口径见 `.project_status/steam_cloud.md`）
class CloudNotes {
  CloudNotes._();

  /// Steam 云同步的是同一批文件，两边一起改会互相判冲突、卡住上传
  static const steamCloudHint =
      'Steam 版建议先在 Steam 里关掉这个游戏的云同步（库 → 该游戏 → 属性 → 通用）：'
      'Steam 云同步的是同一批文件，两边一起改会互相判冲突、卡住上不上去。';

  /// 外部启动的会话 Steam 只上传不下载 ⇒ 覆盖本地前一定要自己留底
  static const overwriteBackupHint =
      '用云端存档覆盖本地之前会先自动备份一份，出问题还能退回去；'
      '覆盖请只在游戏退出后进行。';

  /// 游戏运行中两边同时写数据目录最容易出事
  static const gameRunningHint = '游戏运行中不能同步：先退出游戏，避免两边同时写存档。';

  /// 服务端的保留策略（2026-10-03 对线上核过：`retention` 两条）
  static const retentionHint =
      '云端每个槽位最多留 20 个未固定的快照、且只保留 90 天；'
      '想长期留的版本要在云端历史里「固定」住。';
}
