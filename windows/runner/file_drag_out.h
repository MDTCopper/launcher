#ifndef RUNNER_FILE_DRAG_OUT_H_
#define RUNNER_FILE_DRAG_OUT_H_

#include <windows.h>

#include <memory>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

// 建好「拖出」通道并挂上处理器
//
// Dart 侧是 `lib/util/file_drag_out.dart`：一次调用给一组本机路径与手势位置，
// 一直阻塞到用户松手，返回是否真的落到了别处；
// 返回的通道要由调用方持有到窗口销毁（通道没了，Dart 就调不动了）
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateFileDragOutChannel(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_FILE_DRAG_OUT_H_
