#ifndef RUNNER_WINDOW_IME_H_
#define RUNNER_WINDOW_IME_H_

#include <windows.h>

#include <memory>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

// 建「临时摘掉窗口输入法」的通道并挂上处理器
//
// Dart 侧是 `lib/util/window_ime.dart`：捕获键位时调 detach、关掉弹窗调 restore。
//
// 为什么放在 runner 里：IMM32 的输入法上下文只能由窗口自己的线程操作
// （跨线程关联是未定义行为）；而且 Flutter 的 Windows 端即使没有文本框
// 也挂着窗口的输入法上下文，中文输入法会把按键拦成 VK_PROCESSKEY，
// Flutter 又会跳过这些下键事件 ⇒ Dart 侧一个键都收不到
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateWindowImeChannel(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_WINDOW_IME_H_
