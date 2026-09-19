import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 资源管理器助手：打开文件夹 / 定位文件
///
/// 两个动作都得走 Win32：
/// - 打开前先看有没有**已经开着这个文件夹**的资源管理器窗口，有就把它恢复到前台（不重复开窗）
/// - 定位文件用 `explorer.exe /select, <路径>`
///
/// 这个文件以前还有一整套「独立进程启动 + 游戏窗口控制」（约 1600 行 FFI）：
/// 当年以为 Windows 下父进程退出会带走子进程才写的，2026-09-19 实测确认
/// release 下普通 `Process.start` 就能让游戏独立运行（debug 下被杀是调试器的
/// Job Object，那套 `CREATE_BREAKAWAY_FROM_JOB` 也修不了），已删除，见 `pitfalls.md`
class ExplorerHelper {
  ExplorerHelper._();

  /// 打开 [path] 对应的文件夹：已经开着就把它提到前台，否则新开一个
  static void openExplorer(String path) {
    final normalized = _normalizePath(path);
    final existing = _findExplorerWindow(normalized);
    if (existing != 0) {
      final handle = _hwnd(existing);
      if (IsIconic(handle)) ShowWindow(handle, SW_RESTORE);
      SetForegroundWindow(handle);
      return;
    }

    final operation = 'open'.toNativeUtf16();
    final file = 'explorer.exe'.toNativeUtf16();
    final parameters = normalized.isNotEmpty ? normalized.toNativeUtf16() : null;
    try {
      ShellExecute(
        _hwnd(0),
        PCWSTR(operation),
        PCWSTR(file),
        parameters != null
            ? PCWSTR(parameters)
            : PCWSTR(Pointer.fromAddress(0)),
        PCWSTR(Pointer.fromAddress(0)),
        SW_SHOWNORMAL,
      );
    } finally {
      free(operation);
      free(file);
      if (parameters != null) free(parameters);
    }
  }

  /// 在资源管理器里定位并选中 [path]
  static void locateFile(String path) {
    final normalized = _normalizePath(path);
    final parameters = '/select, $normalized'.toNativeUtf16();
    final operation = 'open'.toNativeUtf16();
    final file = 'explorer.exe'.toNativeUtf16();
    try {
      ShellExecute(
        _hwnd(0),
        PCWSTR(operation),
        PCWSTR(file),
        PCWSTR(parameters),
        PCWSTR(Pointer.fromAddress(0)),
        SW_SHOWNORMAL,
      );
    } finally {
      free(operation);
      free(file);
      free(parameters);
    }
  }

  /// 找已经打开着 [path] 这个文件夹的资源管理器窗口，没有返回 0
  static int _findExplorerWindow(String path) {
    final folderName = _extractFolderName(path).toNativeUtf16();
    final fullPath = path.toNativeUtf16();
    final data = calloc<_EnumSearchData>();
    try {
      data.ref.foundHwnd = 0;
      data.ref.targetFullPathPtr = fullPath.address;
      data.ref.targetFolderNamePtr = folderName.address;
      data.ref.bufLen = 512;
      final callback = Pointer.fromFunction<_EnumWindowsProcC>(
        _enumExplorerCallback,
        0,
      );
      _enumWindows(callback, data.address);
      return data.ref.foundHwnd;
    } finally {
      calloc.free(data);
      free(folderName);
      free(fullPath);
    }
  }

  /// 路径末尾的文件夹名（`C:\a\b\` → `b`；盘符根 `C:\` → `C:`）
  static String _extractFolderName(String path) {
    var trimmed = path;
    while ((trimmed.endsWith('\\') || trimmed.endsWith('/')) &&
        trimmed.length > 3) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.length == 2 && trimmed[1] == ':') return trimmed;
    final lastBackslash = trimmed.lastIndexOf('\\');
    final lastSlash = trimmed.lastIndexOf('/');
    final lastSeparator = lastBackslash > lastSlash
        ? lastBackslash
        : lastSlash;
    return lastSeparator < 0
        ? trimmed
        : trimmed.substring(lastSeparator + 1);
  }

  /// 统一成反斜杠、去掉末尾多余的分隔符（explorer 认这种形式）
  static String _normalizePath(String path) {
    var normalized = path.replaceAll('/', '\\');
    while (normalized.endsWith('\\') && normalized.length > 3) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

// ================================================================
// user32 / shell32：窗口枚举与 ShellExecute
// ================================================================

final _user32 = DynamicLibrary.open('user32.dll');

typedef _EnumWindowsProcC = Int32 Function(IntPtr hWnd, IntPtr lParam);
typedef _EnumWindowsC =
    Int32 Function(Pointer<NativeFunction<_EnumWindowsProcC>>, IntPtr);
typedef _EnumWindowsDart =
    int Function(Pointer<NativeFunction<_EnumWindowsProcC>>, int);

final _enumWindows = _user32.lookupFunction<_EnumWindowsC, _EnumWindowsDart>(
  'EnumWindows',
);

typedef _GetWindowTextC = Int32 Function(IntPtr, Pointer<Uint16>, Int32);
typedef _GetWindowTextDart = int Function(int, Pointer<Uint16>, int);

final _getWindowText = _user32
    .lookupFunction<_GetWindowTextC, _GetWindowTextDart>('GetWindowTextW');

typedef _GetClassNameC = Int32 Function(IntPtr, Pointer<Uint16>, Int32);
typedef _GetClassNameDart = int Function(int, Pointer<Uint16>, int);

final _getClassName = _user32.lookupFunction<_GetClassNameC, _GetClassNameDart>(
  'GetClassNameW',
);

HWND _hwnd(int addr) => HWND(Pointer.fromAddress(addr));

/// 窗口枚举时传下去的数据
final class _EnumSearchData extends Struct {
  @IntPtr()
  external int foundHwnd;
  @IntPtr()
  external int targetFullPathPtr;
  @IntPtr()
  external int targetFolderNamePtr;
  @Int32()
  external int bufLen;
}

/// 找资源管理器窗口：类名含 `Cabinet` / `Explore`，标题匹配文件夹名或完整路径
int _enumExplorerCallback(int hWnd, int lParam) {
  final data = Pointer<_EnumSearchData>.fromAddress(lParam).ref;

  final classBuffer = calloc<Uint16>(data.bufLen);
  _getClassName(hWnd, classBuffer, data.bufLen);
  final className = classBuffer.cast<Utf16>().toDartString();
  calloc.free(classBuffer);
  if (!className.contains('Cabinet') && !className.contains('Explore')) {
    return 1;
  }

  final titleBuffer = calloc<Uint16>(data.bufLen);
  _getWindowText(hWnd, titleBuffer, data.bufLen);
  final title = titleBuffer.cast<Utf16>().toDartString();
  calloc.free(titleBuffer);
  if (title.isEmpty) return 1;

  final targetFolder = Pointer<Utf16>.fromAddress(
    data.targetFolderNamePtr,
  ).toDartString();
  final targetPath = Pointer<Utf16>.fromAddress(
    data.targetFullPathPtr,
  ).toDartString();
  final lowerTitle = title.toLowerCase();

  //宽松匹配：标题等于文件夹名 / 完整路径，或包含它们
  if (lowerTitle == targetFolder.toLowerCase() ||
      lowerTitle == targetPath.toLowerCase() ||
      lowerTitle.contains(targetFolder.toLowerCase()) ||
      lowerTitle.contains(targetPath.toLowerCase())) {
    data.foundHwnd = hWnd;
    return 0;
  }
  return 1;
}
