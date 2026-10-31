#include "window_ime.h"

#include <imm.h>

#include <flutter/standard_method_codec.h>

namespace {

// 摘掉之前窗口挂着的输入法上下文，恢复时原样挂回去
HIMC saved_input_context = nullptr;
bool input_detached = false;

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateWindowImeChannel(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "io.github.copper.launcher/window_ime",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result) {
        if (call.method_name() == "detach") {
          if (input_detached) {
            result->Success(flutter::EncodableValue(true));
            return;
          }
          const HIMC previous = ::ImmAssociateContext(window, nullptr);
          if (previous == nullptr) {
            // 窗口本来就没挂输入法上下文，没什么可摘的
            result->Success(flutter::EncodableValue(false));
            return;
          }
          saved_input_context = previous;
          input_detached = true;
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (call.method_name() == "restore") {
          if (input_detached) {
            ::ImmAssociateContext(window, saved_input_context);
            saved_input_context = nullptr;
            input_detached = false;
          }
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  return channel;
}
