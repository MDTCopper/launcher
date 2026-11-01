param(
  [int]$Runs = 3,
  [string]$VersionId = 'f7078a96-d701-4593-a7b9-17d5946773ea',
  [int]$TimeoutSeconds = 120,
  # 窗口轮询间隔：越小越准，20ms 下 EnumWindows 开销可忽略；日志按 LogPollMs 读
  [int]$PollMs = 20,
  [int]$LogPollMs = 100,
  # 要测的构建：Debug 更接近开发态；Release 更接近用户桌面快捷方式冷启动
  [string]$Configuration = 'Debug',
  # 可选：冻结的 runner 目录（例如复制到 tmp 下的产物），空则用 build\windows\x64\runner\<Configuration>
  [string]$RunnerRoot = ''
)

# 冷启动测速（用户口径）：从「启动器进程创建」到「游戏窗口弹出」，而不是游戏加载完。
#   - 游戏窗口：Win32 EnumWindows + GetWindowThreadProcessId + IsWindowVisible，只认 java.exe 进程的
#     可见顶层窗口（优先 pid == 日志里的游戏 pid；标题 Mindustry / 类名 SDL* 作为兜底）。
#   - 同时保留原有「游戏可交互」时间线（游戏日志 Total time to load），并给出窗口前分段。
# 只用于 Windows；结果依赖机器状态，跑 3~5 次取平均
#
# 注意：本脚本用 Windows PowerShell 5.1 跑（系统没有 pwsh 时也一样能跑）：
#   - 日志是 UTF-8，必须显式按 UTF-8 读，5.1 的 Get-Content 默认是 ANSI，中文标签会读成乱码；
#   - 脚本文件本身要带 UTF-8 BOM，否则 5.1 按 ANSI 解析源码，源码里的中文标签同样会乱码。
# 数据根：checkout 内构建产物的数据根是 <仓库>\data（见 AppPaths 的 checkout 分支），
# 日志与云服务态都在这个目录下

$root = Split-Path -Parent $PSScriptRoot
if (-not $RunnerRoot) {
  $RunnerRoot = Join-Path $root "build\windows\x64\runner\$Configuration"
}
$exe = Join-Path $RunnerRoot 'copper_launcher.exe'
if (-not (Test-Path $exe)) { throw "找不到构建产物：$exe（先 flutter build windows --$($Configuration.ToLower())）" }

$dataDir = Join-Path $root 'data'
$logsDir = Join-Path $dataDir 'logs'
$serviceDir = Join-Path $dataDir 'cloud-service'
$tmpDir = Join-Path $root 'tmp'
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Force $tmpDir | Out-Null }

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-Utf8Text([string]$path) {
  if (-not $path -or -not (Test-Path $path)) { return '' }
  for ($attempt = 1; $attempt -le 6; $attempt++) {
    $fs = $null
    $reader = $null
    try {
      $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
      $reader = New-Object System.IO.StreamReader($fs, $utf8)
      return $reader.ReadToEnd()
    } catch {
      Start-Sleep -Milliseconds 60
    } finally {
      if ($reader) { $reader.Close() }
      if ($fs) { $fs.Close() }
    }
  }
  return ''
}

# ---------------------------------------------------------------------------
# Win32：可见顶层窗口快照 + 进程映像路径
# ---------------------------------------------------------------------------
if (-not ('CopperWin32Probe' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CopperWin32Probe
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref uint lpdwSize);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    // 每个可见顶层窗口一行：pid|hwnd|宽|高|类名|标题（标题里的 | 换成 /）
    public static string[] SnapshotVisibleWindows()
    {
        List<string> rows = new List<string>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            if (!IsWindowVisible(hWnd)) return true;
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            RECT rect;
            if (!GetWindowRect(hWnd, out rect)) return true;
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            // 托盘 / 工具窗 / 隐藏的零尺寸窗口一律不算
            if (width < 40 || height < 40) return true;
            StringBuilder cls = new StringBuilder(256);
            GetClassName(hWnd, cls, cls.Capacity);
            StringBuilder title = new StringBuilder(512);
            GetWindowText(hWnd, title, title.Capacity);
            rows.Add(pid + "|" + hWnd.ToInt64() + "|" + width + "|" + height + "|" + cls + "|" + title.ToString().Replace("|", "/"));
            return true;
        }, IntPtr.Zero);
        return rows.ToArray();
    }

    public static string ProcessImagePath(uint pid)
    {
        IntPtr h = OpenProcess(0x1000, false, pid); // PROCESS_QUERY_LIMITED_INFORMATION
        if (h == IntPtr.Zero) return "";
        try
        {
            StringBuilder sb = new StringBuilder(1024);
            uint size = (uint)sb.Capacity;
            if (!QueryFullProcessImageName(h, 0, sb, ref size)) return "";
            return sb.ToString(0, (int)size);
        }
        finally { CloseHandle(h); }
    }
}
'@
}

# pid -> @{ Exe; StartUtc; IsJava }；进程短命，查过就缓存，避免每 20ms 调系统 API
$script:procInfoCache = @{}
function Get-ProcessInfoCached([int]$processId) {
  if ($script:procInfoCache.ContainsKey($processId)) { return $script:procInfoCache[$processId] }
  $info = [pscustomobject]@{ Exe = ''; StartUtc = $null; IsJava = $false }
  try {
    $p = [System.Diagnostics.Process]::GetProcessById($processId)
    try { $info.StartUtc = $p.StartTime.ToUniversalTime() } catch { }
    $path = ''
    try { $path = [CopperWin32Probe]::ProcessImagePath([uint32]$processId) } catch { }
    if (-not $path) {
      try { $path = $p.MainModule.FileName } catch { }
    }
    $info.Exe = $path
    $info.IsJava = ($path -match '(?i)\\java(w)?\.exe$')
  } catch {
    # 进程已经退出：按非 java 处理
  }
  $script:procInfoCache[$processId] = $info
  return $info
}

# 只杀游戏本体 java，保留 Gradle / Kotlin 等开发用 daemon（它们命令行里没有 mindustry）
function Get-GameJavaProcesses {
  @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine -match '(?i)mindustry|copper_loader|desktop-[0-9.]+\.jar') })
}

function Stop-GameProcesses {
  # copper_launcher.exe 可能是残留 UI / 云服务 / 上一轮启动器；不杀会走「转发给在线进程」而不是冷启动
  Get-CimInstance Win32_Process -Filter "Name='copper_launcher.exe'" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-GameJavaProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  $deadline = (Get-Date).AddSeconds(3)
  while ((Get-Date) -lt $deadline) {
    $launchers = @(Get-CimInstance Win32_Process -Filter "Name='copper_launcher.exe'" -ErrorAction SilentlyContinue)
    $games = @(Get-GameJavaProcesses)
    if ($launchers.Count -eq 0 -and $games.Count -eq 0) { break }
    Start-Sleep -Milliseconds 100
  }
  Start-Sleep -Milliseconds 300
}

function Get-NewLogFile($before) {
  if (-not (Test-Path $logsDir)) { return $null }
  Get-ChildItem $logsDir -Filter '*.log' -File |
    Where-Object { $before -notcontains $_.FullName } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-TimelineValue($text, $label) {
  if (-not $text) { return $null }
  $match = [regex]::Match($text, [regex]::Escape($label) + '\s*\+(\d+)ms')
  if ($match.Success) { return [int]$match.Groups[1].Value }
  return $null
}

function Get-GameTotalValue($text) {
  if (-not $text) { return $null }
  $match = [regex]::Match($text, 'Total time to load:\s*(\d+)ms')
  if ($match.Success) { return [int]$match.Groups[1].Value }
  return $null
}

function Get-GamePid($text) {
  if (-not $text) { return 0 }
  $match = [regex]::Match($text, '进程 ID：(\d+)')
  if ($match.Success) { return [int]$match.Groups[1].Value }
  return 0
}

function Get-TimelineLines($text) {
  if (-not $text) { return @() }
  $lines = @()
  foreach ($line in ($text -split "`n")) {
    if ($line -match '时间线：') { $lines += $line.Trim() }
  }
  return $lines
}

$exeHash = (Get-FileHash $exe -Algorithm SHA256).Hash.Substring(0, 12)
"构建产物：$exe（sha256:${exeHash}…）"
"构建配置：$Configuration"
"数据根　：$dataDir"
"版本 id：$VersionId（跑 $Runs 次，超时 ${TimeoutSeconds}s，窗口轮询 ${PollMs}ms）"
''

$results = @()
for ($i = 1; $i -le $Runs; $i++) {
  $row = $null
  $attempt = 0
  while ($attempt -lt 3 -and -not $row) {
    $attempt++
    Stop-GameProcesses
    Remove-Item $serviceDir -Recurse -Force -ErrorAction SilentlyContinue
    $before = @()
    if (Test-Path $logsDir) {
      $before = Get-ChildItem $logsDir -Filter '*.log' -File | ForEach-Object { $_.FullName }
    }

    # 用「重定向 + NoNewWindow」让 Start-Process 走 CreateProcess 而不是 ShellExecute：
    # 实测把产物冻结复制到 tmp 后，默认 ShellExecute 路径会卡住（Start-Process 一直不返回）；
    # 顺便把启动器 stdout/stderr 收进文件，避免游戏日志转发混进本脚本输出
    $stdoutFile = Join-Path $tmpDir "probe-$i-$attempt.out.txt"
    $stderrFile = Join-Path $tmpDir "probe-$i-$attempt.err.txt"
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    $startWall = [DateTime]::UtcNow
    $process = Start-Process -FilePath $exe -ArgumentList @('--launch-version', $VersionId) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $procStartUtc = $startWall
    try { $procStartUtc = $process.StartTime.ToUniversalTime() } catch { }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $log = $null
    $text = ''
    $gamePid = 0
    $gameProcStartUtc = $null
    $interactiveUtc = $null
    $failed = $false
    $delegated = $false
    $lastLogRead = (Get-Date).AddMinutes(-1)
    $window = $null
    $firstJavaWindow = $null
    $seenHwnds = @{}
    $windowMissingSince = $null

    while ((Get-Date) -lt $deadline) {
      $now = Get-Date
      # 读日志：拿游戏 pid、游戏可交互时间线、失败/转发信号
      if ((-not $log) -or (($now - $lastLogRead).TotalMilliseconds -ge $LogPollMs)) {
        $lastLogRead = $now
        $foundLog = Get-NewLogFile $before
        if ($foundLog) {
          $log = $foundLog
          $text = Read-Utf8Text $log.FullName
          if ($gamePid -le 0) {
            $gamePid = Get-GamePid $text
            if ($gamePid -gt 0) {
              try { $gameProcStartUtc = ([System.Diagnostics.Process]::GetProcessById($gamePid)).StartTime.ToUniversalTime() } catch { }
            }
          }
          # 转发给在线的 UI / 云服务：本进程不是真正的冷启动，这一轮作废重跑
          if ($text -match '快捷启动：UI 在线|快捷启动：云服务在线') { $delegated = $true; break }
          if ($text -match '启动失败|找不到版本|未找到可用 Java') { $failed = $true; break }
          if ($text -match '时间线：游戏可交互') {
            if (-not $interactiveUtc) { $interactiveUtc = [DateTime]::UtcNow }
          }
        }
      }

      # 窗口：只认 java.exe 的可见顶层窗口，排除启动器自己的窗口与黑窗（ConsoleWindowClass）
      if (-not $window) {
        $snap = [CopperWin32Probe]::SnapshotVisibleWindows()
        foreach ($line in $snap) {
          $parts = $line -split '\|', 6
          if ($parts.Count -lt 6) { continue }
          $wpid = [int]$parts[0]
          $hwnd = [long]$parts[1]
          if ($seenHwnds.ContainsKey($hwnd)) { continue }
          $seenHwnds[$hwnd] = $true
          $wcls = $parts[4]
          $wtitle = $parts[5]
          if ($wcls -eq 'ConsoleWindowClass') { continue }
          if ($process -and $wpid -eq $process.Id) { continue }
          $info = Get-ProcessInfoCached $wpid
          if (-not $info.IsJava) { continue }
          # 启动前就存在的 java 窗口（例如别的工具）不算
          if ($info.StartUtc -and $info.StartUtc -lt $procStartUtc.AddMilliseconds(-1500)) { continue }
          $snapUtc = [DateTime]::UtcNow
          $ms = [int]($snapUtc - $procStartUtc).TotalMilliseconds
          if (-not $firstJavaWindow) {
            $firstJavaWindow = [pscustomobject]@{
              Ms = $ms; Pid = $wpid; Title = $wtitle; Class = $wcls
              Width = [int]$parts[2]; Height = [int]$parts[3]
            }
          }
          $match = ''
          if ($gamePid -gt 0 -and $wpid -eq $gamePid) { $match = 'game-pid' }
          elseif ($wtitle -match '(?i)mindustry') { $match = 'title' }
          elseif ($wcls -match '(?i)^SDL') { $match = 'class' }
          if ($match) {
            $window = [pscustomobject]@{
              Ms = $ms; Pid = $wpid; Hwnd = $hwnd; Title = $wtitle; Class = $wcls
              Width = [int]$parts[2]; Height = [int]$parts[3]; Match = $match
            }
          }
        }
      }

      if ($interactiveUtc -and $window) { break }
      if ($interactiveUtc -and -not $window) {
        # 已经可交互却还没看到窗口：再等 5s 抓一次（正常情况下窗口必然更早），之后按「窗口检测失败」收尾
        if (-not $windowMissingSince) {
          $windowMissingSince = [DateTime]::UtcNow
        } elseif ((([DateTime]::UtcNow) - $windowMissingSince).TotalSeconds -ge 5) {
          break
        }
      }
      Start-Sleep -Milliseconds $PollMs
    }

    $log = Get-NewLogFile $before
    $text = if ($log) { Read-Utf8Text $log.FullName } else { '' }

    if ($delegated) {
      "第 $i 次尝试 $attempt：快捷启动被转发给在线进程（非冷启动），重跑"
      Stop-GameProcesses
      continue
    }
    if ($failed) {
      "第 $i 次尝试 $attempt：启动失败（检查游戏 / 云服务日志）"
      Stop-GameProcesses
      continue
    }

    $gameProcExtMs = $null
    if ($gameProcStartUtc) {
      $gameProcExtMs = [int]($gameProcStartUtc - $procStartUtc).TotalMilliseconds
    }
    $interactiveMs = $null
    if ($interactiveUtc) {
      $interactiveMs = [int]($interactiveUtc - $procStartUtc).TotalMilliseconds
    }

    # 进程创建 → 日志文件创建：引擎启动（含 main 里 AppPaths.init 的一部分），
    # 用来补上「时间线」从 Dart main 才开始、看不到引擎启动的那一段
    $preMainMs = $null
    if ($log) {
      $preMainMs = [int]($log.CreationTime - $process.StartTime).TotalMilliseconds
    }
    $logReadyMs = Get-TimelineValue $text '时间线：日志就绪'
    $precheckMs = Get-TimelineValue $text '时间线：快捷启动预检'
    $pathsMs = Get-TimelineValue $text '时间线：基础路径就绪'
    $configMs = Get-TimelineValue $text '时间线：配置就绪'
    $serviceMs = Get-TimelineValue $text '时间线：云服务就绪'
    $gameProcMs = Get-TimelineValue $text '时间线：游戏进程已创建'
    $gameLoadMs = Get-TimelineValue $text '时间线：游戏可交互'
    $gameTotalMs = Get-GameTotalValue $text

    # 引擎时间反推：实测「进程启动→java 进程创建」− 时间线「main→游戏进程创建」
    $engineMs = $null
    if ($gameProcExtMs -ne $null -and $gameProcMs -ne $null) {
      $engineMs = $gameProcExtMs - $gameProcMs
    }
    # 快捷启动路径不写「日志就绪」（Log.init 在预检之前），Dart 时间线起点用「快捷启动预检」兜底
    $dartStartMs = if ($logReadyMs -ne $null) { $logReadyMs } else { $precheckMs }
    $enginePreMainMs = if ($preMainMs -ne $null -and $dartStartMs -ne $null) { $preMainMs - $dartStartMs } else { $null }
    $windowTimelineMs = if ($window -and $engineMs -ne $null) { $window.Ms - $engineMs } else { $null }

    $row = [pscustomobject]@{
      Run                  = $i
      Config               = $Configuration
      Attempt              = $attempt
      TotalToWindowMs      = if ($window) { $window.Ms } else { $null }
      TotalToInteractiveMs = $interactiveMs
      WindowPid            = if ($window) { $window.Pid } else { $null }
      WindowTitle          = if ($window) { $window.Title } else { '' }
      WindowClass          = if ($window) { $window.Class } else { '' }
      WindowWidth          = if ($window) { $window.Width } else { $null }
      WindowHeight         = if ($window) { $window.Height } else { $null }
      WindowMatch          = if ($window) { $window.Match } else { '' }
      GameProcExtMs        = $gameProcExtMs
      WindowAfterProcMs    = if ($window -and $gameProcExtMs -ne $null) { $window.Ms - $gameProcExtMs } else { $null }
      PreMainMs            = $preMainMs
      EngineMs             = $engineMs
      EnginePreMainMs      = $enginePreMainMs
      PrecheckMs           = $precheckMs
      LogReadyMs           = $logReadyMs
      DartStartMs          = $dartStartMs
      WindowTimelineMs     = $windowTimelineMs
      PathsMs              = $pathsMs
      ConfigMs             = $configMs
      ServiceMs            = $serviceMs
      GameProcMs           = $gameProcMs
      GameLoadMs           = $gameLoadMs
      GameTotalMs          = $gameTotalMs
      JvmMs                = if ($gameLoadMs -ne $null -and $gameTotalMs -ne $null) { $gameLoadMs - $gameTotalMs } else { $null }
      InteractiveAfterProcMs = if ($interactiveMs -ne $null -and $gameProcExtMs -ne $null) { $interactiveMs - $gameProcExtMs } else { $null }
      InteractiveAfterWindowMs = if ($interactiveMs -ne $null -and $window) { $interactiveMs - $window.Ms } else { $null }
      Delegated            = $delegated
      Failed               = $failed
      FirstJavaWindowTitle = if ($firstJavaWindow) { $firstJavaWindow.Title } else { '' }
      FirstJavaWindowClass = if ($firstJavaWindow) { $firstJavaWindow.Class } else { '' }
      FirstJavaWindowMs    = if ($firstJavaWindow) { $firstJavaWindow.Ms } else { $null }
      Log                  = if ($log) { $log.Name } else { '' }
    }
    $results += $row

    "----- 第 $i 次（$Configuration，尝试 $attempt）-----"
    $row | Format-List
    if ($window) {
      "    窗口：pid=$($row.WindowPid) 标题='$($row.WindowTitle)' 类=$($row.WindowClass) 尺寸=$($row.WindowWidth)x$($row.WindowHeight) 命中=$($row.WindowMatch)"
    } else {
      "    窗口：未检测到（$TimeoutSeconds s 超时）"
    }
    foreach ($line in (Get-TimelineLines $text)) { "    $line" }
    if ($gameTotalMs -ne $null) { "    游戏自报 Total time to load：${gameTotalMs}ms" }

    Stop-GameProcesses
  }
  if (-not $row) { "第 $i 次：3 次尝试都没跑起来，跳过" }
}

''
'===== 每次 ====='
$results | Format-Table Run,TotalToWindowMs,TotalToInteractiveMs,GameProcExtMs,WindowAfterProcMs,GameProcMs,EngineMs,PrecheckMs,LogReadyMs,PathsMs,ConfigMs,ServiceMs,GameLoadMs,GameTotalMs,WindowMatch,Log -AutoSize

$valid = @($results | Where-Object { $_.TotalToWindowMs -ne $null -and -not $_.Delegated -and -not $_.Failed })
''
'===== 平均（只算窗口检测成功的轮次）====='
if ($valid.Count -gt 0) {
  function Avg-Of($prop) {
    $vals = @($valid | ForEach-Object { $_.$prop } | Where-Object { $_ -ne $null })
    if ($vals.Count -eq 0) { return $null }
    return [int](($vals | Measure-Object -Average).Average)
  }
  function Median-Of($prop) {
    $vals = @($valid | ForEach-Object { $_.$prop } | Where-Object { $_ -ne $null } | Sort-Object)
    if ($vals.Count -eq 0) { return $null }
    return [int]$vals[[int][math]::Floor(($vals.Count - 1) / 2)]
  }
  $avg = [pscustomobject]@{
    Runs             = $valid.Count
    WindowMs         = Avg-Of 'TotalToWindowMs'
    WindowMedianMs   = Median-Of 'TotalToWindowMs'
    InteractiveMs    = Avg-Of 'TotalToInteractiveMs'
    InteractiveMdnMs = Median-Of 'TotalToInteractiveMs'
    EngineMs         = Avg-Of 'EngineMs'
    EnginePreMainMs  = Avg-Of 'EnginePreMainMs'
    PrecheckMs       = Avg-Of 'PrecheckMs'
    LogReadyMs       = Avg-Of 'LogReadyMs'
    DartStartMs      = Avg-Of 'DartStartMs'
    WindowTimelineMs = Avg-Of 'WindowTimelineMs'
    PathsMs          = Avg-Of 'PathsMs'
    ConfigMs         = Avg-Of 'ConfigMs'
    ServiceMs        = Avg-Of 'ServiceMs'
    GameProcMs       = Avg-Of 'GameProcMs'
    GameProcExtMs    = Avg-Of 'GameProcExtMs'
    WindowAfterProc  = Avg-Of 'WindowAfterProcMs'
    GameLoadMs       = Avg-Of 'GameLoadMs'
    GameTotalMs      = Avg-Of 'GameTotalMs'
    JvmMs            = Avg-Of 'JvmMs'
    AfterProcMs      = Avg-Of 'InteractiveAfterProcMs'
    AfterWindowMs    = Avg-Of 'InteractiveAfterWindowMs'
  }
  $avg | Format-Table -AutoSize
  ''
  '分段（平均，ms）：'
  "  [外部] 进程启动 → 日志文件创建（Flutter 引擎 + Log.init 前半，估）：$($avg.EnginePreMainMs)"
  "  [外部] 进程启动 → 时间线零点（引擎反推 = 实测 java 进程创建 − 时间线游戏进程创建）：$($avg.EngineMs)"
  "  [日志] 预检（快捷启动路径，Log.init 后）：$($avg.PrecheckMs)"
  "  [日志] 日志就绪：$($avg.LogReadyMs)（快捷启动路径不写这一行，用预检兜底 → Dart 起点 $($avg.DartStartMs)）"
  "  [日志] Dart 起点 → 基础路径就绪（AppPaths 后半）：$(if ($avg.PathsMs -ne $null -and $avg.DartStartMs -ne $null) { $avg.PathsMs - $avg.DartStartMs } else { $null })"
  "  [日志] 基础路径 → 配置就绪（DataRootMigration+TokenEncryptor+config 读盘/备份/保存）：$(if ($avg.ConfigMs -ne $null -and $avg.PathsMs -ne $null) { $avg.ConfigMs - $avg.PathsMs } else { $null })"
  "  [日志] 配置 → 云服务就绪（服务初始化 + 会话目录）：$(if ($avg.ServiceMs -ne $null -and $avg.ConfigMs -ne $null) { $avg.ServiceMs - $avg.ConfigMs } else { $null })"
  "  [日志] 云服务 → 游戏进程创建（Java 校验缓存命中/云同步/settings/内存估算/起 JVM）：$(if ($avg.GameProcMs -ne $null -and $avg.ServiceMs -ne $null) { $avg.GameProcMs - $avg.ServiceMs } else { $null })"
  "  [外部] 游戏进程创建 → 游戏窗口出现（JVM 启动 + SDL/GL 建窗）：$($avg.WindowAfterProc)"
  "  [外部] 游戏窗口出现 → 游戏可交互（游戏自报加载 + 转发）：$($avg.AfterWindowMs)"
  "  [时间线] 游戏窗口出现在 Dart 时间线的位置（外部窗口 − 引擎反推）：$($avg.WindowTimelineMs)"
  ''
  "  ★ 用户口径：进程启动 → 游戏窗口出现 = $($avg.WindowMs) ms（中位 $($avg.WindowMedianMs) ms，n=$($valid.Count)）"
  "     其中启动器侧准备（进程启动 → java 进程创建）= $($avg.GameProcExtMs) ms"
  "           = 引擎/进程创建 $($avg.EngineMs) + Dart 时间线 $($avg.GameProcMs)"
  "     其中游戏侧（java 进程创建 → 窗口出现）= $($avg.WindowAfterProc) ms"
  "  （旧口径）进程启动 → 游戏可交互 = $($avg.InteractiveMs) ms（中位 $($avg.InteractiveMdnMs) ms）"
  ''
  $check = if ($avg.EngineMs -ne $null -and $avg.EnginePreMainMs -ne $null) { $avg.EngineMs - $avg.EnginePreMainMs } else { $null }
  "  引擎两种估计之差（反推 − 日志文件创建口径）：$check ms（≈ Dart 起点前的 Log.init 时长，属正常误差；" +
    "日志时间戳为秒级量化）"
} else {
  '没有一次成功检测到游戏窗口（检查游戏 / 云服务日志；或用 java 进程创建 + 固定偏移作为替代口径）'
  exit 1
}
