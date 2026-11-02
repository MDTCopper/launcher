import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/sync_proxy.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/token_encryptor.dart';

/// 云同步代理进程：服务在启动前同步超过 3 秒时拉起
///
/// 只初始化代理真正用的东西：路径、日志、配置（主题与版本名）；
/// 不做数据根迁移、网络设置、账号恢复，这些是 UI/服务进程的事。
/// 代理是短命进程，同步结束/取消/超时就退出，不进入任何长期任务链。
class SyncProxyProcess {
  SyncProxyProcess._();

  static Future<void> start({String? versionId}) async {
    AppRuntime.form = AppForm.syncProxy;
    AppRuntime.headless = true;
    await AppPaths.init();
    await Log.init();
    addLog(
      .info,
      '时间线：代理预检 +${AppRuntime.elapsedMs}ms（${AppRuntime.form.label}）',
      tag: 'Timeline',
    );
    addLog(.info, '启动器形态：${AppRuntime.form.label}', tag: 'Startup');
    addLog(.info, '数据根目录：${AppPaths.copperLauncher}', tag: 'Startup');
    // 配置里有加密的 GitHub token，解密器必须先就绪
    await TokenEncryptor.init();
    await initAppConfig();
    addLog(.info, '时间线：配置就绪 +${AppRuntime.elapsedMs}ms', tag: 'Timeline');
    await runSyncProxy(versionId: versionId);
  }
}
