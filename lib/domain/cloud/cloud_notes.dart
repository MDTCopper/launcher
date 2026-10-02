/// 云存档 UI 上要用的几句固定文案
///
/// 口径是调研 + 用户拍板定下来的（见 `.project_status/steam_cloud.md`），写在一处，
/// 免得将来做 UI 时每次现编、说法不一致
class CloudNotes {
  CloudNotes._();

  /// Steam 云与我们的云同步**同一批文件**（Auto-Cloud 的规则覆盖 `saves/`、
  /// `saves/saves`、`maps`、`mods`、`schematics`、`assetCache`）；我们一改文件 SHA，
  /// Steam 就判冲突，而**一个冲突会挡住它整批上传** ⇒ 引导用户先关掉它
  static const steamCloudHint =
      'Steam 版建议先在 Steam 里关掉这个游戏的云同步（库 → 该游戏 → 属性 → 通用）：'
      'Steam 云同步的是同一批文件，两边一起改会互相判冲突、卡住上不上去。';

  /// 外部启动（绕开 Steam 客户端）的会话 Steam **只上传、不下载** ⇒ 覆盖前必须自己留底
  static const overwriteBackupHint =
      '用云端存档覆盖本地之前会先自动备份一份，出问题还能退回去；'
      '覆盖请只在游戏退出后进行。';

  /// 游戏运行中两边同时写数据目录最容易出事
  static const gameRunningHint = '游戏运行中不能同步：先退出游戏，避免两边同时写存档。';
}
