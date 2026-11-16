import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 本次进程是否无界面：口径以 lib/main.dart 的 CLI 分流为准，与 Windows / Linux runner 一致
  ///
  /// 无界面形态只有三种：--sync-proxy（云同步代理，首帧后由 Dart 显示小窗）、
  /// --cloud-service（云存档服务，--adopt-all / --recover 只跟着它出现）、
  /// --launch-version <id>（快捷启动触发进程）；--launch-version 要带值才算，
  /// 取值失败时 Dart 会走界面，所以不能按裸标志压制；--resume-launch 与无参数都要建界面
  static var isHeadlessLaunch: Bool {
    let launchVersionPrefix = "--launch-version="
    let arguments = CommandLine.arguments
    for (index, argument) in arguments.enumerated() {
      if argument == "--sync-proxy" || argument == "--cloud-service" {
        return true
      }
      if argument == "--launch-version" {
        if index + 1 < arguments.count && !arguments[index + 1].hasPrefix("--") {
          return true
        }
        continue
      }
      if argument.hasPrefix(launchVersionPrefix) && argument.count > launchVersionPrefix.count {
        return true
      }
    }
    return false
  }

  /// 启动阶段的窗口排序要压掉；只压启动这一轮，之后 Dart 侧 show 照常
  private static var suppressingLaunchOrdering = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 无界面进程启动时不留主窗口；需要窗口的形态由 Dart 侧 windowManager.show() 显示
    //
    // nib 的「Visible At Launch」在启动流程里才走窗口排序，所以这里先压一次，
    // 再靠下一轮主队列解除，保证启动阶段任何一次排序都显示不出来；
    // macOS 目前不在 CI 发布范围（见 .github/workflows/release.yml），
    // 这段只做了代码复核，未在真机验证，首次打 macos 包时要人眼确认无界面进程不弹窗
    if MainFlutterWindow.isHeadlessLaunch {
      MainFlutterWindow.suppressingLaunchOrdering = true
      self.setIsVisible(false)
      DispatchQueue.main.async {
        MainFlutterWindow.suppressingLaunchOrdering = false
      }
    }

    super.awakeFromNib()
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    if MainFlutterWindow.suppressingLaunchOrdering {
      self.setIsVisible(false)
    }
  }
}
