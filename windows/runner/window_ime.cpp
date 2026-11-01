#include "window_ime.h"

#include <imm.h>

#include <flutter/standard_method_codec.h>

namespace {

enum class ImeTarget : int {
  kNone = 0,
  kFocus = 1,
  kView = 2,
  kRoot = 3,
};

struct SavedContext {
  HWND window;
  HIMC context;
};

// 摘掉之前挂着的输入法上下文，恢复时原样挂回去
SavedContext saved_contexts[3];
int saved_count = 0;

// 第一个摘到上下文的窗口类型（给日志用）
ImeTarget ime_target = ImeTarget::kNone;

// 上下文不一定挂在顶层窗口上：Flutter 的视图是顶层窗口里的子窗口，
// 输入法实际跟的是有焦点的子窗口。焦点 / 视图 / 顶层都试一遍，
// 谁挂着就摘谁（引擎有可能在这几个窗口上都挂过）
void DetachCandidates(HWND view_window) {
  struct Candidate {
    HWND window;
    ImeTarget target;
  };
  const Candidate candidates[3] = {
      {::GetFocus(), ImeTarget::kFocus},
      {view_window, ImeTarget::kView},
      {::GetAncestor(view_window, GA_ROOT), ImeTarget::kRoot},
  };
  for (const Candidate& candidate : candidates) {
    if (candidate.window == nullptr || saved_count >= 3) {
      continue;
    }
    const HIMC previous = ::ImmAssociateContext(candidate.window, nullptr);
    if (previous == nullptr) {
      continue;
    }
    saved_contexts[saved_count++] = {candidate.window, previous};
    if (ime_target == ImeTarget::kNone) {
      ime_target = candidate.target;
    }
  }
}

void RestoreCandidates() {
  for (int index = saved_count - 1; index >= 0; --index) {
    ::ImmAssociateContext(saved_contexts[index].window,
                          saved_contexts[index].context);
  }
  saved_count = 0;
  ime_target = ImeTarget::kNone;
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
          if (saved_count == 0) {
            DetachCandidates(view_window);
          }
          // 报摘到了哪一类窗口：0 = 没摘到（没有上下文 / 非 Windows）
          result->Success(
              flutter::EncodableValue(static_cast<int>(ime_target)));
          return;
        }

        if (call.method_name() == "restore") {
          RestoreCandidates();
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  return channel;
}
