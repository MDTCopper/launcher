#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// 本次进程是否无界面：口径以 lib/main.dart 的 CLI 分流为准，三平台共用这一份判定
//
// 无界面形态只有三种：--sync-proxy（云同步代理，首帧后由 Dart 显示小窗）、
// --cloud-service（云存档服务，--adopt-all / --recover 只跟着它出现）、
// --launch-version <id>（快捷启动触发进程）；--launch-version 要带值才算，
// 取值失败时 Dart 会走界面，所以不能按裸标志压制；--resume-launch 与无参数都要建界面
bool IsHeadlessLaunch(const std::vector<std::string>& arguments) {
  const std::string launch_version_prefix = "--launch-version=";
  for (size_t index = 0; index < arguments.size(); ++index) {
    const std::string& argument = arguments[index];
    if (argument == "--sync-proxy" || argument == "--cloud-service") {
      return true;
    }
    if (argument == "--launch-version") {
      const bool has_version = index + 1 < arguments.size() &&
                               arguments[index + 1].rfind("--", 0) != 0;
      if (has_version) {
        return true;
      }
      continue;
    }
    if (argument.rfind(launch_version_prefix, 0) == 0 &&
        argument.size() > launch_version_prefix.size()) {
      return true;
    }
  }
  return false;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // 无界面进程：首帧不显示窗口，需要时由 Dart 侧显式 show（见 flutter_window.h）
  const bool suppress_initial_show = IsHeadlessLaunch(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetSuppressInitialShow(suppress_initial_show);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Copper Launcher", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
