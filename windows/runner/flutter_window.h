#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // 无界面进程（--sync-proxy / --cloud-service / 带值的 --launch-version）不在
  // 第一帧显示窗口，需要时由 Dart 侧显式 show（见 lib/domain/sync_proxy.dart 的 runSyncProxy）
  void SetSuppressInitialShow(bool suppress) { suppress_initial_show_ = suppress; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // 快捷启动：跳过首帧显示回调，窗口保持隐藏
  bool suppress_initial_show_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 「把文件拖出去」的通道（Dart 侧 lib/util/file_drag_out.dart）
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_drag_out_channel_;

  // 「临时摘掉输入法」的通道（Dart 侧 lib/util/window_ime.dart）
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_ime_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
