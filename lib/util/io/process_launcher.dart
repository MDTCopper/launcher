import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ================================================================
// ProcessLauncher — 跨平台进程启动器
// ================================================================
//
// Windows 独立模式: CreateProcessW + 匿名管道 + DETACHED_PROCESS
// （已知限制：Flutter Job Object 下子进程仍可能被杀，dart run 独立测试正常）
// 其他平台: Process.start
// ================================================================

class LaunchResult {
  final int pid;

  LaunchResult(this.pid);
}

class ProcessLauncher {
  Process? _process;
  int _pid = 0;
  bool _disposed = false;

  int _hProcess = 0;
  int _hThread = 0;
  int _pipeOutRead = 0;
  int _pipeErrRead = 0;
  Timer? _pipeTimer;
  final StringBuffer _outBuf = StringBuffer();
  final StringBuffer _errBuf = StringBuffer();
  final Completer<int> _exitCompleter = Completer<int>();

  final StreamController<String> _stdoutCtrl =
      StreamController<String>.broadcast();
  final StreamController<String> _stderrCtrl =
      StreamController<String>.broadcast();

  Stream<String> get stdoutStream => _stdoutCtrl.stream;

  Stream<String> get stderrStream => _stderrCtrl.stream;

  bool get isRunning => _process != null || _hProcess != 0;

  int get processId => _process?.pid ?? _pid;

  Future<int> get exitCode {
    if (_process != null) return _process!.exitCode;
    if (_hProcess != 0) return _exitCompleter.future;
    return Future.value(-1);
  }

  Future<LaunchResult?> start({
    required String exePath,
    List<String> args = const [],
    String? workingDir,
    bool independent = false,
  }) async {
    if (_process != null || _hProcess != 0) return null;
    if (Platform.isWindows && independent) {
      return _startWinIndep(exePath, args, workingDir);
    }
    return _startNormal(exePath, args, workingDir);
  }

  Future<LaunchResult?> _startNormal(
    String exe,
    List<String> args,
    String? cwd,
  ) async {
    try {
      _process = await Process.start(
        exe,
        args,
        workingDirectory: cwd,
        mode: ProcessStartMode.normal,
      );
    } catch (_) {
      _process = null;
      return null;
    }
    _pid = _process!.pid;
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
    _process!.exitCode.then((_) => _process = null);
    return LaunchResult(_pid);
  }

  Future<LaunchResult?> _startWinIndep(
    String exe,
    List<String> args,
    String? cwd,
  ) async {
    final r = _winLaunch(exe, args, cwd);
    if (r == null) return null;
    _hProcess = r[0];
    _hThread = r[1];
    _pid = r[2];
    _pipeOutRead = r[3];
    _pipeErrRead = r[4];
    _pipeTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _winReadPipes(
        _pipeOutRead,
        _pipeErrRead,
        _outBuf,
        _errBuf,
        _hProcess,
        (s) {
          if (!_stdoutCtrl.isClosed) _stdoutCtrl.add(s);
        },
        (s) {
          if (!_stderrCtrl.isClosed) _stderrCtrl.add(s);
        },
        () {
          if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
          _cleanWin();
        },
      ),
    );
    return LaunchResult(_pid);
  }

  void _cleanWin() {
    _pipeTimer?.cancel();
    _pipeTimer = null;
    _winClose(_pipeOutRead);
    _pipeOutRead = 0;
    _winClose(_pipeErrRead);
    _pipeErrRead = 0;
    _winClose(_hThread);
    _hThread = 0;
    _winClose(_hProcess);
    _hProcess = 0;
    _pid = 0;
  }

  void kill() {
    if (_process != null) {
      _process!.kill(ProcessSignal.sigkill);
    } else if (_hProcess != 0) {
      _winTerminate(_hProcess);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_process != null) {
      _process!.kill(ProcessSignal.sigkill);
      _process = null;
    }
    _cleanWin();
    if (!_stdoutCtrl.isClosed) _stdoutCtrl.close();
    if (!_stderrCtrl.isClosed) _stderrCtrl.close();
  }
}

// ================================================================
// kernel32 FFI
// ================================================================

final _k32 = DynamicLibrary.open('kernel32.dll');

final class _W32SEC extends Struct {
  @Uint32()
  external int nLength;
  external Pointer<NativeType> lpSec;
  @Int32()
  external int bInherit;
}

final class _W32SI extends Struct {
  @Uint32()
  external int cb;
  external Pointer<Utf16> lpRes, lpDesk, lpTitle;
  @Uint32()
  external int dX, dY, dXS, dYS, dXC, dYC, dFill, dFlags;
  @Uint16()
  external int wShow, cbR2;
  external Pointer<Uint8> lpR2;
  @IntPtr()
  external int hIn, hOut, hErr;
}

final class _W32PI extends Struct {
  @IntPtr()
  external int hP, hT;
  @Uint32()
  external int pid, tid;
}

final _createPipe = _k32.lookupFunction<
  Int32 Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<_W32SEC>, Uint32),
  int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<_W32SEC>, int)
>('CreatePipe');

final _createProcessW = _k32.lookupFunction<
  Int32 Function(
    Pointer<Utf16>,
    Pointer<Utf16>,
    Pointer<_W32SEC>,
    Pointer<_W32SEC>,
    Int32,
    Uint32,
    Pointer<NativeType>,
    Pointer<Utf16>,
    Pointer<_W32SI>,
    Pointer<_W32PI>,
  ),
  int Function(
    Pointer<Utf16>,
    Pointer<Utf16>,
    Pointer<_W32SEC>,
    Pointer<_W32SEC>,
    int,
    int,
    Pointer<NativeType>,
    Pointer<Utf16>,
    Pointer<_W32SI>,
    Pointer<_W32PI>,
  )
>('CreateProcessW');

final _readFile = _k32.lookupFunction<
  Int32 Function(
    IntPtr,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint32>,
    Pointer<NativeType>,
  ),
  int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<NativeType>)
>('ReadFile');

final _peekPipe = _k32.lookupFunction<
  Int32 Function(
    IntPtr,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  ),
  int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
>('PeekNamedPipe');

final _closeH = _k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
  'CloseHandle',
);

final _terminateP = _k32
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'TerminateProcess',
    );

final _getExitCode = _k32.lookupFunction<
  Int32 Function(IntPtr, Pointer<Uint32>),
  int Function(int, Pointer<Uint32>)
>('GetExitCodeProcess');

final _setHI = _k32.lookupFunction<
  Int32 Function(IntPtr, Uint32, Uint32),
  int Function(int, int, int)
>('SetHandleInformation');

const int _kStill = 259;
const int _kDetach = 0x00000008;
const int _kNewGroup = 0x00000200;
const int _kBreakaway = 0x01000000;
const int _kUseHandles = 0x00000100;

List<int>? _winLaunch(String exe, List<String> args, String? cwd) {
  final outR = calloc<IntPtr>(), outW = calloc<IntPtr>();
  final errR = calloc<IntPtr>(), errW = calloc<IntPtr>();
  if (_makePipe(outR, outW) == 0 || _makePipe(errR, errW) == 0) {
    _free4(outR, outW, errR, errW);
    return null;
  }
  final pOutR = outR.value, pOutW = outW.value;
  final pErrR = errR.value, pErrW = errW.value;
  _free4(outR, outW, errR, errW);

  final cmd = _buildCmd(exe, args);
  final cmdPtr = cmd.toNativeUtf16();
  final cwdPtr = cwd?.toNativeUtf16();

  final si = calloc<_W32SI>();
  si.ref.cb = sizeOf<_W32SI>();
  si.ref.dFlags = _kUseHandles;
  si.ref.hOut = pOutW;
  si.ref.hErr = pErrW;
  si.ref.wShow = 1;

  final pi = calloc<_W32PI>();
  final ok = _createProcessW(
    Pointer.fromAddress(0),
    cmdPtr,
    Pointer.fromAddress(0),
    Pointer.fromAddress(0),
    1,
    _kNewGroup | _kDetach | _kBreakaway,
    Pointer.fromAddress(0),
    cwdPtr ?? Pointer.fromAddress(0),
    si,
    pi,
  );

  _closeH(pOutW);
  _closeH(pErrW);
  calloc.free(cmdPtr);
  if (cwdPtr != null) calloc.free(cwdPtr);
  calloc.free(si);

  if (ok == 0) {
    _closeH(pOutR);
    _closeH(pErrR);
    calloc.free(pi);
    return null;
  }
  final r = [pi.ref.hP, pi.ref.hT, pi.ref.pid, pOutR, pErrR];
  calloc.free(pi);
  return r;
}

void _winReadPipes(
  int outR,
  int errR,
  StringBuffer outBuf,
  StringBuffer errBuf,
  int hProcess,
  void Function(String) onOut,
  void Function(String) onErr,
  void Function() onExit,
) {
  _readPipe(outR, outBuf, onOut);
  _readPipe(errR, errBuf, onErr);
  final code = calloc<Uint32>();
  _getExitCode(hProcess, code);
  if (code.value != _kStill) {
    if (outBuf.isNotEmpty) {
      onOut(outBuf.toString());
      outBuf.clear();
    }
    if (errBuf.isNotEmpty) {
      onErr(errBuf.toString());
      errBuf.clear();
    }
    onExit();
  }
  calloc.free(code);
}

void _winClose(int h) => _closeH(h);

void _winTerminate(int h) => _terminateP(h, 1);

int _makePipe(Pointer<IntPtr> r, Pointer<IntPtr> w) {
  final sa = calloc<_W32SEC>();
  sa.ref.nLength = sizeOf<_W32SEC>();
  sa.ref.bInherit = 1;
  final ok = _createPipe(r, w, sa, 0);
  calloc.free(sa);
  if (ok != 0) _setHI(r.value, 0, 0);
  return ok;
}

String _buildCmd(String exe, List<String> args) =>
    <String>[_q(exe), ...args.map(_q)].join(' ');

String _q(String s) =>
    (s.contains(' ') || s.contains('"')) ? '"${s.replaceAll('"', '\\"')}"' : s;

void _readPipe(int h, StringBuffer buf, void Function(String) onLine) {
  if (h == 0) return;
  final avail = calloc<Uint32>();
  _peekPipe(
    h,
    Pointer.fromAddress(0),
    0,
    Pointer.fromAddress(0),
    avail,
    Pointer.fromAddress(0),
  );
  var left = avail.value;
  calloc.free(avail);
  while (left > 0) {
    final chunk = calloc<Uint8>(4096);
    final n = calloc<Uint32>();
    _readFile(h, chunk, left < 4096 ? left : 4096, n, Pointer.fromAddress(0));
    final got = n.value;
    calloc.free(n);
    if (got == 0) {
      calloc.free(chunk);
      break;
    }
    final data = chunk.asTypedList(got);
    for (int i = 0; i < data.length; i++) {
      final b = data[i];
      if (b == 0x0A) {
        onLine(buf.toString());
        buf.clear();
      } else if (b != 0x0D) {
        buf.writeCharCode(b);
      }
    }
    calloc.free(chunk);
    final a2 = calloc<Uint32>();
    _peekPipe(
      h,
      Pointer.fromAddress(0),
      0,
      Pointer.fromAddress(0),
      a2,
      Pointer.fromAddress(0),
    );
    left = a2.value;
    calloc.free(a2);
  }
}

void _free4(dynamic a, dynamic b, dynamic c, dynamic d) {
  calloc.free(a);
  calloc.free(b);
  calloc.free(c);
  calloc.free(d);
}
