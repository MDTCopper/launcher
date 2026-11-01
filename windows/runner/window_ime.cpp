#include "window_ime.h"

#include <imm.h>

#include <flutter/standard_method_codec.h>

namespace {

// 摘掉之前挂着的输入法上下文，恢复时原样挂回去
HIMC saved_input_context = nullptr;

// 上下文是挂在「有焦点的那个窗口」上的，不一定是顶层窗口：
// Flutter 的视图是顶层窗口里的子窗口，输入法实际跟的是它
HWND ime_window = nullptr;

// 上下文是挂在「有焦点的那个窗口」上的，不一定是顶层窗口：
// Flutter 的视图是顶层窗口里的子窗口，输入法实际跟的是它。
// 依次试 焦点窗口 → 视图窗口 → 顶层窗口，谁有上下文就摘谁
HWND ResolveImeWindow(HWND view_window, HIMC* out_context) {
  HWND candidates[3] = {::GetFocus(), view_window,
                        ::GetAncestor(view_window, GA_ROOT)};
  for (HWND window : candidates) {
    if (window == nullptr) {
      continue;
    }
    const HIMC previous = ::ImmAssociateContext(window, nullptr);
    if (previous != nullptr) {
      *out_context = previous;
      return window;
    }
  }
  return nullptr;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateWindowImeChannel(flutter::BinaryMessenger* messenger, HWND view_window) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "io.github.copper.launcher/window_ime",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [view_window](const flutter::MethodCall<flutter::EncodableValue>& call,
                    std::unique_ptr<
                        flutter::MethodResult<flutter::EncodableValue>>
                        result) {
        if (call.method_name() == "detach") {
          if (ime_window != nullptr) {
            result->Success(flutter::EncodableValue(true));
            return;
          }
          HIMC previous = nullptr;
          HWND window = ResolveImeWindow(view_window, &previous);
          if (window == nullptr) {
            // 这几个窗口都没挂输入法上下文，没什么可摘的
            result->Success(flutter::EncodableValue(false));
            return;
          }
          saved_input_context = previous;
          ime_window = window;
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (call.method_name() == "restore") {
          if (ime_window != nullptr) {
            ::ImmAssociateContext(ime_window, saved_input_context);
            saved_input_context = nullptr;
            ime_window = nullptr;
          }
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  return channel;
}
