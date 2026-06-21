import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// ================================================================
// 数据类型
// ================================================================

/// 窗口矩形（整数坐标）
class WinRect {
  final int left, top, right, bottom;

  const WinRect(this.left, this.top, this.right, this.bottom);

  int get width => right - left;

  int get height => bottom - top;

  @override
  String toString() => 'WinRect($left, $top, ${width}x$height)';
}

// ================================================================
// kernel32 FFI 绑定
// ================================================================

final _kernel32 = DynamicLibrary.open('kernel32.dll');

// 结构体定义

final class _SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;

  external Pointer<NativeType> lpSecurityDescriptor;

  @Int32()
  external int bInheritHandle;
}

final class _StartupInfoW extends Struct {
  @Uint32()
  external int cb;

  external Pointer<Utf16> lpReserved;
  external Pointer<Utf16> lpDesktop;
  external Pointer<Utf16> lpTitle;

  @Uint32()
  external int dwX;
  @Uint32()
  external int dwY;
  @Uint32()
  external int dwXSize;
  @Uint32()
  external int dwYSize;
  @Uint32()
  external int dwXCountChars;
  @Uint32()
  external int dwYCountChars;
  @Uint32()
  external int dwFillAttribute;
  @Uint32()
  external int dwFlags;

  @Uint16()
  external int wShowWindow;
  @Uint16()
  external int cbReserved2;

  external Pointer<Uint8> lpReserved2;

  @IntPtr()
  external int hStdInput;
  @IntPtr()
  external int hStdOutput;
  @IntPtr()
  external int hStdError;
}

final class _ProcessInfo extends Struct {
  @IntPtr()
  external int hProcess;
  @IntPtr()
  external int hThread;

  @Uint32()
  external int dwProcessId;
  @Uint32()
  external int dwThreadId;
}

// CreatePipe
typedef _CreatePipeC =
    Int32 Function(
      Pointer<IntPtr> hReadPipe,
      Pointer<IntPtr> hWritePipe,
      Pointer<_SecurityAttributes> lpPipeAttributes,
      Uint32 nSize,
    );
typedef _CreatePipeDart =
    int Function(
      Pointer<IntPtr>,
      Pointer<IntPtr>,
      Pointer<_SecurityAttributes>,
      int,
    );

final _createPipe = _kernel32.lookupFunction<_CreatePipeC, _CreatePipeDart>(
  'CreatePipe',
);

// CreateProcessW
typedef _CreateProcessWC =
    Int32 Function(
      Pointer<Utf16> lpApplicationName,
      Pointer<Utf16> lpCommandLine,
      Pointer<_SecurityAttributes> lpProcessAttributes,
      Pointer<_SecurityAttributes> lpThreadAttributes,
      Int32 bInheritHandles,
      Uint32 dwCreationFlags,
      Pointer<NativeType> lpEnvironment,
      Pointer<Utf16> lpCurrentDirectory,
      Pointer<_StartupInfoW> lpStartupInfo,
      Pointer<_ProcessInfo> lpProcessInformation,
    );
typedef _CreateProcessWDart =
    int Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<_SecurityAttributes>,
      Pointer<_SecurityAttributes>,
      int,
      int,
      Pointer<NativeType>,
      Pointer<Utf16>,
      Pointer<_StartupInfoW>,
      Pointer<_ProcessInfo>,
    );

final _createProcessW = _kernel32
    .lookupFunction<_CreateProcessWC, _CreateProcessWDart>('CreateProcessW');

// ReadFile
typedef _ReadFileC =
    Int32 Function(
      IntPtr hFile,
      Pointer<Uint8> lpBuffer,
      Uint32 nNumberOfBytesToRead,
      Pointer<Uint32> lpNumberOfBytesRead,
      Pointer<NativeType> lpOverlapped,
    );
typedef _ReadFileDart =
    int Function(
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint32>,
      Pointer<NativeType>,
    );

final _readFile = _kernel32.lookupFunction<_ReadFileC, _ReadFileDart>(
  'ReadFile',
);

// PeekNamedPipe
typedef _PeekNamedPipeC =
    Int32 Function(
      IntPtr hNamedPipe,
      Pointer<Uint8> lpBuffer,
      Uint32 nBufferSize,
      Pointer<Uint32> lpBytesRead,
      Pointer<Uint32> lpTotalBytesAvail,
      Pointer<Uint32> lpBytesLeftThisMessage,
    );
typedef _PeekNamedPipeDart =
    int Function(
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );

final _peekNamedPipe = _kernel32
    .lookupFunction<_PeekNamedPipeC, _PeekNamedPipeDart>('PeekNamedPipe');

// CloseHandle
typedef _CloseHandleC = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int);

final _closeHandle = _kernel32.lookupFunction<_CloseHandleC, _CloseHandleDart>(
  'CloseHandle',
);

// TerminateProcess
typedef _TerminateProcessC = Int32 Function(IntPtr hProcess, Uint32 uExitCode);
typedef _TerminateProcessDart = int Function(int, int);

final _terminateProcess = _kernel32
    .lookupFunction<_TerminateProcessC, _TerminateProcessDart>(
      'TerminateProcess',
    );

// GetExitCodeProcess
typedef _GetExitCodeProcessC =
    Int32 Function(IntPtr hProcess, Pointer<Uint32> lpExitCode);
typedef _GetExitCodeProcessDart = int Function(int, Pointer<Uint32>);

final _getExitCodeProcess = _kernel32
    .lookupFunction<_GetExitCodeProcessC, _GetExitCodeProcessDart>(
      'GetExitCodeProcess',
    );

// SetHandleInformation
typedef _SetHandleInformationC =
    Int32 Function(IntPtr hObject, Uint32 dwMask, Uint32 dwFlags);
typedef _SetHandleInformationDart = int Function(int, int, int);

final _setHandleInformation = _kernel32
    .lookupFunction<_SetHandleInformationC, _SetHandleInformationDart>(
      'SetHandleInformation',
    );

const int kCreateNewProcessGroup = 0x00000200;
const int kDetachedProcess = 0x00000008;
const int kBreakawayFromJob = 0x01000000;
const int kStartfUseStdHandles = 0x00000100;
const int kStillActive = 259;

// ================================================================
// user32 FFI 绑定
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

typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdDart = int Function(int, Pointer<Uint32>);

final _getWindowThreadProcessId = _user32
    .lookupFunction<_GetWindowThreadProcessIdC, _GetWindowThreadProcessIdDart>(
      'GetWindowThreadProcessId',
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

typedef _GetWindowRectC = Int32 Function(IntPtr, Pointer<RECT>);
typedef _GetWindowRectDart = int Function(int, Pointer<RECT>);

final _getWindowRect = _user32
    .lookupFunction<_GetWindowRectC, _GetWindowRectDart>('GetWindowRect');

typedef _IsWindowC = Int32 Function(IntPtr);
typedef _IsWindowDart = int Function(int);

final _isWindow = _user32.lookupFunction<_IsWindowC, _IsWindowDart>('IsWindow');

typedef _FlashWindowC = Int32 Function(IntPtr, Int32);
typedef _FlashWindowDart = int Function(int, int);

final _flashWindow = _user32.lookupFunction<_FlashWindowC, _FlashWindowDart>(
  'FlashWindow',
);

typedef _GetWindowLongPtrC = IntPtr Function(IntPtr, Int32);
typedef _GetWindowLongPtrDart = int Function(int, int);

final _getWindowLongPtr = _user32
    .lookupFunction<_GetWindowLongPtrC, _GetWindowLongPtrDart>(
      'GetWindowLongPtrW',
    );

HWND _hwnd(int addr) => HWND(Pointer.fromAddress(addr));

const int kWsMaximize = 0x01000000;
const int kWsVisible = 0x10000000;
const int kGwlStyle = -16;
const int kMsgClose = 0x0010;

// ================================================================
// EnumWindows 数据结构与回调
// ================================================================

final class _EnumSearchData extends Struct {
  @Int32()
  external int targetPid;
  @IntPtr()
  external int foundHwnd;
  @IntPtr()
  external int targetFullPathPtr;
  @IntPtr()
  external int targetFolderNamePtr;
  @IntPtr()
  external int targetTitlePtr;
  @Int32()
  external int requireVisible;
  @Int32()
  external int bufLen;
}

int _enumByPidCallback(int hWnd, int lParam) {
  final data = Pointer<_EnumSearchData>.fromAddress(lParam).ref;
  final p = calloc<Uint32>();
  _getWindowThreadProcessId(hWnd, p);
  final pid = p.value;
  calloc.free(p);
  if (pid == data.targetPid) {
    if (data.requireVisible != 0) {
      if (!IsWindowVisible(_hwnd(hWnd))) return 1;
      final style = _getWindowLongPtr(hWnd, kGwlStyle);
      if ((style & kWsVisible) == 0) return 1;
    }
    data.foundHwnd = hWnd;
    return 0;
  }
  return 1;
}

int _enumByTitleCallback(int hWnd, int lParam) {
  final data = Pointer<_EnumSearchData>.fromAddress(lParam).ref;
  if (data.requireVisible != 0 && !IsWindowVisible(_hwnd(hWnd))) return 1;
  final buf = calloc<Uint16>(data.bufLen);
  _getWindowText(hWnd, buf, data.bufLen);
  final title = buf.cast<Utf16>().toDartString();
  calloc.free(buf);
  if (title.isEmpty) return 1;
  final target = Pointer<Utf16>.fromAddress(data.targetTitlePtr).toDartString();
  if (title.toLowerCase().contains(target.toLowerCase())) {
    data.foundHwnd = hWnd;
    return 0;
  }
  return 1;
}

int _enumExplorerCallback(int hWnd, int lParam) {
  final data = Pointer<_EnumSearchData>.fromAddress(lParam).ref;
  final buf = calloc<Uint16>(data.bufLen);
  _getClassName(hWnd, buf, data.bufLen);
  final cls = buf.cast<Utf16>().toDartString();
  calloc.free(buf);

  // 放宽类名匹配：也接受包含 "Cabinet" 或 "Explore" 的子串
  if (!cls.contains('Cabinet') && !cls.contains('Explore')) return 1;

  final tb = calloc<Uint16>(data.bufLen);
  _getWindowText(hWnd, tb, data.bufLen);
  final title = tb.cast<Utf16>().toDartString();
  calloc.free(tb);
  if (title.isEmpty) return 1;

  final tf =
      Pointer<Utf16>.fromAddress(data.targetFolderNamePtr).toDartString();
  final tp = Pointer<Utf16>.fromAddress(data.targetFullPathPtr).toDartString();
  final t = title.toLowerCase();

  // 宽松匹配：精确相等 OR 标题包含文件夹名 OR 标题包含完整路径
  if (t == tf.toLowerCase() ||
      t == tp.toLowerCase() ||
      t.contains(tf.toLowerCase()) ||
      t.contains(tp.toLowerCase())) {
    data.foundHwnd = hWnd;
    return 0;
  }
  return 1;
}

/// 全局可见窗口回调：返回第一个可见的非工具顶层窗口。
int _enumAllVisibleCallback(int hWnd, int lParam) {
  final data = Pointer<_EnumSearchData>.fromAddress(lParam).ref;

  // 跳过属于排除 PID 的窗口（如 Flutter 自身）
  if (data.targetPid != 0) {
    final p = calloc<Uint32>();
    _getWindowThreadProcessId(hWnd, p);
    final match = p.value == data.targetPid;
    calloc.free(p);
    if (match) return 1;
  }

  if (!IsWindowVisible(_hwnd(hWnd))) return 1;

  final tb = calloc<Uint16>(data.bufLen);
  _getWindowText(hWnd, tb, data.bufLen);
  final title = tb.cast<Utf16>().toDartString();
  calloc.free(tb);
  if (title.isEmpty) return 1;

  // 跳过工具窗口
  const int gwlExStyle = -20;
  final exStyle = _getWindowLongPtr(hWnd, gwlExStyle);
  if ((exStyle & 0x80) != 0) return 1;

  // 要求标准顶层窗口
  const int wsOverlapped = 0x00CF0000;
  final style = _getWindowLongPtr(hWnd, kGwlStyle);
  if ((style & wsOverlapped) != wsOverlapped) return 1;

  data.foundHwnd = hWnd;
  return 0;
}

// ================================================================
// WindowProcessController
// ================================================================

/// 封装 Win32 窗口 + 进程控制器。
///
/// 零 Flutter 依赖，可独立用于任何 Dart 项目（仅需 `dart:ffi` + `win32`）。
///
/// ## 两种模式
///
/// **普通模式** (`independent: false`, 默认)：
/// - 子进程绑定到启动器控制台，启动器退出时子进程一同退出
/// - 完整 stdout/stderr 监控
///
/// **独立模式** (`independent: true`)：
/// - 通过 `CreateProcessW` + `CREATE_NEW_PROCESS_GROUP` 创建
/// - 子进程在独立进程组中，**Flutter 退出不影响子进程**
/// - 仍可捕获 stdout/stderr（通过匿名管道）
class WindowProcessController {
  // ---- 普通模式 ----
  Process? _process;

  // ---- 独立模式 ----
  int _hProcess = 0;
  int _hThread = 0;
  int _indepPid = 0;
  int _pipeOutRead = 0;
  int _pipeOutWrite = 0;
  int _pipeErrRead = 0;
  int _pipeErrWrite = 0;
  Timer? _pipeTimer;
  final StringBuffer _outBuf = StringBuffer();
  final StringBuffer _errBuf = StringBuffer();
  final Completer<int> _exitCompleter = Completer<int>();

  // ---- 窗口 ----
  int _hWndAddr = 0;

  // ---- 状态 ----
  bool _disposed = false;

  // ---- 流 ----
  final StreamController<String> _stdoutCtrl =
      StreamController<String>.broadcast();
  final StreamController<String> _stderrCtrl =
      StreamController<String>.broadcast();

  Stream<String> get stdoutStream => _stdoutCtrl.stream;

  Stream<String> get stderrStream => _stderrCtrl.stream;

  Stream<String> get combinedStream {
    final c = StreamController<String>.broadcast();
    _stdoutCtrl.stream.listen(c.add, onError: c.addError);
    _stderrCtrl.stream.listen(c.add, onError: c.addError);
    return c.stream;
  }

  // ================================================================
  // 启动
  // ================================================================

  /// 启动进程。
  ///
  /// [independent] 为 true 时，通过 `CreateProcessW` +
  /// `CREATE_NEW_PROCESS_GROUP` 启动，子进程脱离启动器控制台，
  /// Flutter 退出后子进程继续运行。
  Future<bool> start({
    required String exePath,
    List<String> args = const [],
    String? workingDir,
    bool independent = false,
  }) async {
    if (_process != null || _indepPid != 0) return false;

    if (independent) {
      return _startIndependent(exePath, args, workingDir);
    }

    try {
      _process = await Process.start(
        exePath,
        args,
        workingDirectory: workingDir,
        mode: ProcessStartMode.normal,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[WindowProcessController] 启动失败: $e');
      _process = null;
      return false;
    }
    _captureStdio();
    _process!.exitCode.then((_) {
      _hWndAddr = 0;
      _process = null;
    });
    await _waitForWindow(_process!.pid);
    return true;
  }

  // ---- 独立模式 ----

  Future<bool> _startIndependent(
    String exePath,
    List<String> args,
    String? workingDir,
  ) async {
    // 1) 创建管道
    if (!_createPipePair(true) || !_createPipePair(false)) {
      _closePipeHandles();
      return false;
    }

    // 2) 拼接命令行
    final cmdLine = _buildCommandLine(exePath, args);
    final cmdLinePtr = cmdLine.toNativeUtf16();
    final workDirPtr = workingDir?.toNativeUtf16();

    // 3) 填充 STARTUPINFO
    final si = calloc<_StartupInfoW>();
    si.ref.cb = sizeOf<_StartupInfoW>();
    si.ref.dwFlags = kStartfUseStdHandles;
    si.ref.hStdInput = 0;
    si.ref.hStdOutput = _pipeOutWrite;
    si.ref.hStdError = _pipeErrWrite;
    si.ref.wShowWindow = 1; // SW_SHOWNORMAL

    // 4) PROCESS_INFORMATION
    final pi = calloc<_ProcessInfo>();

    // 5) CreateProcessW
    final ok = _createProcessW(
      Pointer.fromAddress(0),
      // lpApplicationName = null
      cmdLinePtr,
      Pointer.fromAddress(0),
      // lpProcessAttributes = null
      Pointer.fromAddress(0),
      // lpThreadAttributes = null
      1,
      // bInheritHandles = TRUE
      kCreateNewProcessGroup | kDetachedProcess | kBreakawayFromJob,
      Pointer.fromAddress(0),
      // lpEnvironment = null
      workDirPtr ?? Pointer.fromAddress(0),
      si,
      pi,
    );

    // 6) 关掉写端（子进程已继承）
    _closeHandle(_pipeOutWrite);
    _closeHandle(_pipeErrWrite);
    _pipeOutWrite = 0;
    _pipeErrWrite = 0;

    free(cmdLinePtr);
    if (workDirPtr != null) free(workDirPtr);
    calloc.free(si);

    if (ok == 0) {
      calloc.free(pi);
      _closePipeHandles();
      return false;
    }

    _hProcess = pi.ref.hProcess;
    _hThread = pi.ref.hThread;
    _indepPid = pi.ref.dwProcessId;
    calloc.free(pi);

    // 7) 开始管道读取
    _pipeTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _readPipes(),
    );

    // 8) 等待窗口
    await _waitForWindow(_indepPid);
    return true;
  }

  bool _createPipePair(bool isStdout) {
    final readEnd = calloc<IntPtr>();
    final writeEnd = calloc<IntPtr>();
    final sa = calloc<_SecurityAttributes>();
    sa.ref.nLength = sizeOf<_SecurityAttributes>();
    sa.ref.bInheritHandle = 1;
    sa.ref.lpSecurityDescriptor = Pointer.fromAddress(0);

    final r = _createPipe(readEnd, writeEnd, sa, 0);
    calloc.free(sa);

    if (r == 0) {
      calloc.free(readEnd);
      calloc.free(writeEnd);
      return false;
    }

    // 读端不需要继承
    _setHandleInformation(readEnd.value, 0, 0);

    if (isStdout) {
      _pipeOutRead = readEnd.value;
      _pipeOutWrite = writeEnd.value;
    } else {
      _pipeErrRead = readEnd.value;
      _pipeErrWrite = writeEnd.value;
    }
    calloc.free(readEnd);
    calloc.free(writeEnd);
    return true;
  }

  String _buildCommandLine(String exe, List<String> args) {
    final parts = <String>[_quoteArg(exe), ...args.map(_quoteArg)];
    return parts.join(' ');
  }

  String _quoteArg(String arg) {
    if (arg.contains(' ') || arg.contains('"')) {
      return '"${arg.replaceAll('"', '\\"')}"';
    }
    return arg;
  }

  // ---- 管道读取 ----

  void _readPipes() {
    _readPipe(_pipeOutRead, _outBuf, _stdoutCtrl);
    _readPipe(_pipeErrRead, _errBuf, _stderrCtrl);
    _checkExit();
  }

  void _readPipe(
    int handle,
    StringBuffer lineBuf,
    StreamController<String> ctrl,
  ) {
    if (handle == 0 || ctrl.isClosed) return;

    final avail = calloc<Uint32>();
    final peekOk = _peekNamedPipe(
      handle,
      Pointer.fromAddress(0),
      0,
      Pointer.fromAddress(0),
      avail,
      Pointer.fromAddress(0),
    );
    final bytesAvail = peekOk != 0 ? avail.value : 0;
    calloc.free(avail);

    while (bytesAvail > 0) {
      final buf = calloc<Uint8>(4096);
      final bytesRead = calloc<Uint32>();
      final toRead = bytesAvail < 4096 ? bytesAvail : 4096;
      final ok = _readFile(
        handle,
        buf,
        toRead,
        bytesRead,
        Pointer.fromAddress(0),
      );
      if (ok == 0 || bytesRead.value == 0) {
        calloc.free(buf);
        calloc.free(bytesRead);
        break;
      }
      final chunk = buf.asTypedList(bytesRead.value);
      for (int i = 0; i < chunk.length; i++) {
        final b = chunk[i];
        if (b == 0x0A) {
          ctrl.add(lineBuf.toString());
          lineBuf.clear();
        } else if (b != 0x0D) {
          lineBuf.writeCharCode(b);
        }
      }
      calloc.free(buf);
      calloc.free(bytesRead);

      // 还有更多数据吗？
      final a2 = calloc<Uint32>();
      _peekNamedPipe(
        handle,
        Pointer.fromAddress(0),
        0,
        Pointer.fromAddress(0),
        a2,
        Pointer.fromAddress(0),
      );
      final more = a2.value;
      calloc.free(a2);
      if (more == 0) break;
    }
  }

  void _checkExit() {
    if (_hProcess == 0) return;
    final code = calloc<Uint32>();
    _getExitCodeProcess(_hProcess, code);
    if (code.value != kStillActive) {
      if (!_exitCompleter.isCompleted) _exitCompleter.complete(code.value);
      if (_outBuf.isNotEmpty) {
        _stdoutCtrl.add(_outBuf.toString());
        _outBuf.clear();
      }
      if (_errBuf.isNotEmpty) {
        _stderrCtrl.add(_errBuf.toString());
        _errBuf.clear();
      }
      _cleanupIndep();
    }
    calloc.free(code);
  }

  void _cleanupIndep() {
    _pipeTimer?.cancel();
    _pipeTimer = null;
    _closeHandle(_pipeOutRead);
    _closeHandle(_pipeErrRead);
    _pipeOutRead = 0;
    _pipeErrRead = 0;
    _closeHandle(_hThread);
    _closeHandle(_hProcess);
    _hThread = 0;
    _hProcess = 0;
    _indepPid = 0;
    _hWndAddr = 0;
  }

  void _closePipeHandles() {
    _closeHandle(_pipeOutRead);
    _closeHandle(_pipeOutWrite);
    _closeHandle(_pipeErrRead);
    _closeHandle(_pipeErrWrite);
    _pipeOutRead = 0;
    _pipeOutWrite = 0;
    _pipeErrRead = 0;
    _pipeErrWrite = 0;
  }

  // ---- 普通模式 ----

  void _captureStdio() {
    if (_process == null) return;
    try {
      _process!.stdout.transform(utf8.decoder).listen((s) {
        if (!_stdoutCtrl.isClosed) _stdoutCtrl.add(s);
      }, onError: (_) {});
    } catch (_) {}
    try {
      _process!.stderr.transform(utf8.decoder).listen((s) {
        if (!_stderrCtrl.isClosed) _stderrCtrl.add(s);
      }, onError: (_) {});
    } catch (_) {}
  }

  // ================================================================
  // attach
  // ================================================================

  bool attachToPid(int pid) {
    _hWndAddr = _findWindowByPid(pid);
    if (_hWndAddr == 0) _hWndAddr = _findWindowByPidLenient(pid);
    return _hWndAddr != 0;
  }

  bool attachToTitle(String titlePart) {
    _hWndAddr = _findWindowByTitle(titlePart);
    return _hWndAddr != 0;
  }

  // ================================================================
  // 控制
  // ================================================================

  void kill() {
    if (_process != null) {
      _process!.kill(ProcessSignal.sigkill);
    } else if (_hProcess != 0) {
      _terminateProcess(_hProcess, 1);
    }
  }

  void stop({bool force = false}) {
    if (_process != null) {
      if (force) {
        _process!.kill(ProcessSignal.sigkill);
      } else {
        _closeWindow();
        Future.delayed(const Duration(seconds: 2), () {
          _process?.kill(ProcessSignal.sigkill);
        });
      }
    } else if (_hProcess != 0) {
      if (force) {
        _terminateProcess(_hProcess, 1);
      } else {
        _closeWindow();
        Future.delayed(const Duration(seconds: 2), () {
          if (_hProcess != 0) _terminateProcess(_hProcess, 1);
        });
      }
    }
  }

  bool get isRunning => _process != null || _indepPid != 0;

  int get processId => _process?.pid ?? _indepPid;

  Future<int> get exitCode {
    if (_process != null) return _process!.exitCode;
    if (_hProcess != 0) return _exitCompleter.future;
    return Future.value(-1);
  }

  // ================================================================
  // 窗口操作
  // ================================================================

  bool focus() {
    _ensureHwnd();
    if (_hWndAddr == 0) return false;
    final h = _hwnd(_hWndAddr);
    if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
    return SetForegroundWindow(h);
  }

  bool maximize() =>
      _hWndAddr != 0 && ShowWindow(_hwnd(_hWndAddr), SW_MAXIMIZE);

  bool minimize() =>
      _hWndAddr != 0 && ShowWindow(_hwnd(_hWndAddr), SW_MINIMIZE);

  bool restore() => _hWndAddr != 0 && ShowWindow(_hwnd(_hWndAddr), SW_RESTORE);

  bool showWindow() => _hWndAddr != 0 && ShowWindow(_hwnd(_hWndAddr), SW_SHOW);

  bool hide() => _hWndAddr != 0 && ShowWindow(_hwnd(_hWndAddr), SW_HIDE);

  bool setRect(int x, int y, int w, int h) {
    if (_hWndAddr == 0) return false;
    return SetWindowPos(
      _hwnd(_hWndAddr),
      _hwnd(0),
      x,
      y,
      w,
      h,
      SWP_NOZORDER | SWP_NOACTIVATE,
    ).value;
  }

  WinRect? getRect() {
    if (_hWndAddr == 0) return null;
    final r = calloc<RECT>();
    try {
      if (_getWindowRect(_hWndAddr, r) == 0) return null;
      return WinRect(r.ref.left, r.ref.top, r.ref.right, r.ref.bottom);
    } finally {
      calloc.free(r);
    }
  }

  String? getTitle() {
    if (_hWndAddr == 0) return null;
    const len = 512;
    final buf = calloc<Uint16>(len);
    try {
      if (_getWindowText(_hWndAddr, buf, len) == 0) return null;
      return buf.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }

  bool flashWindow() => _hWndAddr != 0 && _flashWindow(_hWndAddr, 1) != 0;

  bool closeWindow() {
    if (_hWndAddr == 0) return false;
    _closeWindow();
    return true;
  }

  void _closeWindow() =>
      PostMessage(_hwnd(_hWndAddr), kMsgClose, WPARAM(0), LPARAM(0));

  bool get isVisible => _hWndAddr != 0 && IsWindowVisible(_hwnd(_hWndAddr));

  bool get isMinimized => _hWndAddr != 0 && IsIconic(_hwnd(_hWndAddr));

  bool get isMaximized {
    if (_hWndAddr == 0) return false;
    return (_getWindowLongPtr(_hWndAddr, kGwlStyle) & kWsMaximize) != 0;
  }

  int get hwndAddress {
    _ensureHwnd();
    return _hWndAddr;
  }

  bool get isHwndValid => _hWndAddr != 0 && _isWindow(_hWndAddr) != 0;

  // ================================================================
  // 资源管理器
  // ================================================================

  static void openExplorer(String path) {
    final n = _normalizePath(path);
    final existing = _findExplorerWindow(n);
    if (existing != 0) {
      final h = _hwnd(existing);
      if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
      SetForegroundWindow(h);
      return;
    }

    final lpOp = 'open'.toNativeUtf16();
    final lpFile = 'explorer.exe'.toNativeUtf16();
    final lpParams = n.isNotEmpty ? n.toNativeUtf16() : null;
    try {
      ShellExecute(
        _hwnd(0),
        PCWSTR(lpOp),
        PCWSTR(lpFile),
        lpParams != null ? PCWSTR(lpParams) : PCWSTR(Pointer.fromAddress(0)),
        PCWSTR(Pointer.fromAddress(0)),
        SW_SHOWNORMAL,
      );
    } finally {
      free(lpOp);
      free(lpFile);
      if (lpParams != null) free(lpParams);
    }
  }

  static void locateFile(String path) {
    final n = _normalizePath(path);
    final params = '/select, $n';
    final lpOp = 'open'.toNativeUtf16();
    final lpFile = 'explorer.exe'.toNativeUtf16();
    final lpParams = params.toNativeUtf16();
    try {
      ShellExecute(
        _hwnd(0),
        PCWSTR(lpOp),
        PCWSTR(lpFile),
        PCWSTR(lpParams),
        PCWSTR(Pointer.fromAddress(0)),
        SW_SHOWNORMAL,
      );
    } finally {
      free(lpOp);
      free(lpFile);
      free(lpParams);
    }
  }

  // ================================================================
  // 生命周期
  // ================================================================

  /// 清理资源。独立模式下**不终止**子进程，仅释放 Dart 端资源。
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // 普通模式：杀掉进程
    if (_process != null) {
      _process!.kill(ProcessSignal.sigkill);
      _process = null;
    }

    // 独立模式：不杀进程，清理管道和句柄
    _pipeTimer?.cancel();
    _pipeTimer = null;
    _closePipeHandles();
    _closeHandle(_hThread);
    _closeHandle(_hProcess);
    _hThread = 0;
    _hProcess = 0;
    _indepPid = 0;
    _hWndAddr = 0;

    if (!_stdoutCtrl.isClosed) _stdoutCtrl.close();
    if (!_stderrCtrl.isClosed) _stderrCtrl.close();
  }

  // ================================================================
  // 内部
  // ================================================================

  Future<void> _waitForWindow(int childPid) async {
    for (int i = 0; i < 50 && _hWndAddr == 0; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_disposed) return;
      _hWndAddr = _findWindowByPid(childPid);
    }
    // 兜底：排除当前进程（Flutter），扫描目标窗口
    if (_hWndAddr == 0) _hWndAddr = _broadWindowSearch(pid);
  }

  void _ensureHwnd() {
    if (_hWndAddr != 0 && _isWindow(_hWndAddr) == 0) _hWndAddr = 0;
    if (_hWndAddr != 0) return;
    final childPid = _process?.pid ?? _indepPid;
    if (childPid != 0) {
      _hWndAddr = _findWindowByPid(childPid);
      if (_hWndAddr == 0) _hWndAddr = _findWindowByPidLenient(childPid);
    }
    // 兜底：排除当前进程（Flutter），扫描目标窗口
    if (_hWndAddr == 0) _hWndAddr = _broadWindowSearch(pid);
  }

  /// 全局窗口搜索：跳过 [skipPid]，返回第一个可见顶层窗口。
  static int _broadWindowSearch([int skipPid = 0]) {
    final data = calloc<_EnumSearchData>();
    try {
      data.ref.targetPid = skipPid; // 排除此 PID
      data.ref.foundHwnd = 0;
      data.ref.bufLen = 512;
      final cb = Pointer.fromFunction<_EnumWindowsProcC>(
        _enumAllVisibleCallback,
        0,
      );
      _enumWindows(cb, data.address);
      return data.ref.foundHwnd;
    } finally {
      calloc.free(data);
    }
  }

  static int _findWindowByPid(int pid) => _findWindow(pid, true);

  static int _findWindowByPidLenient(int pid) => _findWindow(pid, false);

  static int _findWindow(int pid, bool requireVisible) {
    final d = calloc<_EnumSearchData>();
    try {
      d.ref.targetPid = pid;
      d.ref.foundHwnd = 0;
      d.ref.requireVisible = requireVisible ? 1 : 0;
      d.ref.bufLen = 256;
      final cb = Pointer.fromFunction<_EnumWindowsProcC>(_enumByPidCallback, 0);
      _enumWindows(cb, d.address);
      return d.ref.foundHwnd;
    } finally {
      calloc.free(d);
    }
  }

  static int _findWindowByTitle(String title) {
    final tp = title.toNativeUtf16();
    final d = calloc<_EnumSearchData>();
    try {
      d.ref.foundHwnd = 0;
      d.ref.targetTitlePtr = tp.address;
      d.ref.requireVisible = 1;
      d.ref.bufLen = 512;
      final cb = Pointer.fromFunction<_EnumWindowsProcC>(
        _enumByTitleCallback,
        0,
      );
      _enumWindows(cb, d.address);
      return d.ref.foundHwnd;
    } finally {
      calloc.free(d);
      free(tp);
    }
  }

  static int _findExplorerWindow(String path) {
    final fn = _extractFolderName(path);
    final fnu = fn.toNativeUtf16();
    final fpu = path.toNativeUtf16();
    final d = calloc<_EnumSearchData>();
    try {
      d.ref.foundHwnd = 0;
      d.ref.targetFullPathPtr = fpu.address;
      d.ref.targetFolderNamePtr = fnu.address;
      d.ref.requireVisible = 0;
      d.ref.bufLen = 512;
      final cb = Pointer.fromFunction<_EnumWindowsProcC>(
        _enumExplorerCallback,
        0,
      );
      _enumWindows(cb, d.address);
      return d.ref.foundHwnd;
    } finally {
      calloc.free(d);
      free(fnu);
      free(fpu);
    }
  }

  static String _extractFolderName(String path) {
    var p = path;
    while ((p.endsWith('\\') || p.endsWith('/')) && p.length > 3) {
      p = p.substring(0, p.length - 1);
    }
    if (p.length == 2 && p[1] == ':') return p;
    final a = p.lastIndexOf('\\'), b = p.lastIndexOf('/');
    final s = a > b ? a : b;
    return s < 0 ? p : p.substring(s + 1);
  }

  static String _normalizePath(String path) {
    var p = path.replaceAll('/', '\\');
    while (p.endsWith('\\') && p.length > 3) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}
