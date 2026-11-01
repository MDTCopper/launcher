param(
  [int]$Runs = 3,
  [string]$VersionId = 'f7078a96-d701-4593-a7b9-17d5946773ea',
  [int]$TimeoutSeconds = 120,
  [int]$PollMs = 100,
  # 要测的构建：Debug 更接近开发态；Release 更接近用户桌面快捷方式冷启动
  [string]$Configuration = 'Debug'
)

# 冷启动测速：从进程启动到「游戏可交互」（游戏日志 Total time to load 之后启动器记的时间线）
# 只用于 Windows；结果依赖机器状态，跑 3~5 次取平均
#
# 注意：本脚本用 Windows PowerShell 5.1 跑（系统没有 pwsh 时也一样能跑）：
#   - 日志是 UTF-8，必须显式按 UTF-8 读，5.1 的 Get-Content 默认是 ANSI，中文标签会读成乱码；
#   - 脚本文件本身要带 UTF-8 BOM，否则 5.1 按 ANSI 解析源码，源码里的中文标签同样会乱码。
# 数据根：checkout 内构建产物的数据根是 <仓库>\data（见 AppPaths 的 checkout 分支），
# 日志与云服务态都在这个目录下

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root "build\windows\x64\runner\$Configuration\copper_launcher.exe"
if (-not (Test-Path $exe) -and $Configuration -eq 'Debug') {
  $exe = Join-Path $root 'build\windows\x64\runner\Release\copper_launcher.exe'
}
if (-not (Test-Path $exe)) { throw "找不到构建产物：$exe（先 flutter build windows --$($Configuration.ToLower())）" }

$dataDir = Join-Path $root 'data'
$logsDir = Join-Path $dataDir 'logs'
$serviceDir = Join-Path $dataDir 'cloud-service'

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

function Stop-GameProcesses {
  # copper_launcher.exe 自己也可能还挂着上一局的服务进程；java.exe 是游戏本体
  Get-CimInstance Win32_Process -Filter "Name='copper_launcher.exe' OR Name='java.exe'" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 400
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

function Get-TimelineLines($text) {
  if (-not $text) { return @() }
  $lines = @()
  foreach ($line in ($text -split "`n")) {
    if ($line -match '时间线：') { $lines += $line.Trim() }
  }
  return $lines
}

"构建产物：$exe"
"构建配置：$Configuration"
"数据根　：$dataDir"
"版本 id：$VersionId（跑 $Runs 次，超时 ${TimeoutSeconds}s）"
''

$results = @()
for ($i = 1; $i -le $Runs; $i++) {
  Stop-GameProcesses
  Remove-Item $serviceDir -Recurse -Force -ErrorAction SilentlyContinue
  $before = @()
  if (Test-Path $logsDir) {
    $before = Get-ChildItem $logsDir -Filter '*.log' -File | ForEach-Object { $_.FullName }
  }

  $watch = [Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process -FilePath $exe -ArgumentList @('--launch-version', $VersionId) -PassThru
  $procStart = $null
  try { $procStart = $process.StartTime } catch { }
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $log = $null
  $loaded = $false
  $failed = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds $PollMs
    $log = Get-NewLogFile $before
    if ($log) {
      $text = Read-Utf8Text $log.FullName
      if ($text -match '时间线：游戏可交互') { $loaded = $true; break }
      if ($text -match '启动失败|找不到版本|未找到可用 Java') { $failed = $true; break }
    }
    if ($process -and $process.HasExited -and -not $log) { break }
  }
  $watch.Stop()
  $log = Get-NewLogFile $before
  $text = if ($log) { Read-Utf8Text $log.FullName } else { '' }

  # 进程创建 → 日志文件创建：引擎启动（含 main 里 AppPaths.init 的一部分），
  # 用来补上「时间线」从 Dart main 才开始、看不到引擎启动的那一段
  $preMainMs = $null
  if ($procStart -and $log) {
    $preMainMs = [int]($log.CreationTime - $procStart).TotalMilliseconds
  }
  $logReadyMs = Get-TimelineValue $text '时间线：日志就绪'
  $engineMs = if ($preMainMs -ne $null -and $logReadyMs -ne $null) { $preMainMs - $logReadyMs } else { $null }
  $gameTotalMs = Get-GameTotalValue $text
  $gameLoadMs = Get-TimelineValue $text '时间线：游戏可交互'
  $jvmMs = if ($gameLoadMs -ne $null -and $gameTotalMs -ne $null) { $gameLoadMs - $gameTotalMs } else { $null }

  $row = [pscustomobject]@{
    Run        = $i
    TotalMs    = $watch.ElapsedMilliseconds
    Loaded     = $loaded
    Failed     = $failed
    PathsMs    = Get-TimelineValue $text '时间线：基础路径就绪'
    ConfigMs   = Get-TimelineValue $text '时间线：配置就绪'
    ServiceMs  = Get-TimelineValue $text '时间线：云服务就绪'
    GameProcMs = Get-TimelineValue $text '时间线：游戏进程已创建'
    GameLoadMs = $gameLoadMs
    GameTotal  = $gameTotalMs
    JvmMs      = $jvmMs
    PreMainMs  = $preMainMs
    EngineMs   = $engineMs
    Log        = if ($log) { $log.Name } else { '' }
  }
  $results += $row
  $row | Format-Table -AutoSize
  foreach ($line in (Get-TimelineLines $text)) { "    $line" }

  Stop-GameProcesses
}

''
'===== 每次 ====='
$results | Format-Table Run,TotalMs,Loaded,PathsMs,ConfigMs,ServiceMs,GameProcMs,GameLoadMs,GameTotal,JvmMs,PreMainMs,EngineMs,Log -AutoSize

''
'===== 平均（只算成功跑到「游戏可交互」的轮次）====='
$loadedRows = @($results | Where-Object { $_.Loaded })
if ($loadedRows.Count -gt 0) {
  function Avg-Of($prop) {
    $vals = @($loadedRows | ForEach-Object { $_.$prop } | Where-Object { $_ -ne $null })
    if ($vals.Count -eq 0) { return $null }
    return [int](($vals | Measure-Object -Average).Average)
  }
  function Median-Of($prop) {
    $vals = @($loadedRows | ForEach-Object { $_.$prop } | Where-Object { $_ -ne $null } | Sort-Object)
    if ($vals.Count -eq 0) { return $null }
    return [int]$vals[[int][math]::Floor(($vals.Count - 1) / 2)]
  }
  $avg = [pscustomobject]@{
    Runs          = $loadedRows.Count
    TotalMs       = Avg-Of 'TotalMs'
    MedianTotalMs = Median-Of 'TotalMs'
    PathsMs       = Avg-Of 'PathsMs'
    ConfigMs      = Avg-Of 'ConfigMs'
    ServiceMs     = Avg-Of 'ServiceMs'
    GameProcMs    = Avg-Of 'GameProcMs'
    GameLoadMs    = Avg-Of 'GameLoadMs'
    GameTotal     = Avg-Of 'GameTotal'
    JvmMs         = Avg-Of 'JvmMs'
    PreMainMs     = Avg-Of 'PreMainMs'
    EngineMs      = Avg-Of 'EngineMs'
    ConfigDelta   = if ((Avg-Of 'PathsMs') -ne $null -and (Avg-Of 'ConfigMs') -ne $null) { (Avg-Of 'ConfigMs') - (Avg-Of 'PathsMs') } else { $null }
    ServiceDelta  = if ((Avg-Of 'ConfigMs') -ne $null -and (Avg-Of 'ServiceMs') -ne $null) { (Avg-Of 'ServiceMs') - (Avg-Of 'ConfigMs') } else { $null }
    GameSpawnMs   = if ((Avg-Of 'ServiceMs') -ne $null -and (Avg-Of 'GameProcMs') -ne $null) { (Avg-Of 'GameProcMs') - (Avg-Of 'ServiceMs') } else { $null }
    GameLoadDelta = if ((Avg-Of 'GameProcMs') -ne $null -and (Avg-Of 'GameLoadMs') -ne $null) { (Avg-Of 'GameLoadMs') - (Avg-Of 'GameProcMs') } else { $null }
    OutsideMs     = if ((Avg-Of 'GameLoadMs') -ne $null -and (Avg-Of 'TotalMs') -ne $null) { (Avg-Of 'TotalMs') - (Avg-Of 'GameLoadMs') } else { $null }
  }
  $avg | Format-Table -AutoSize
  ''
  '分段（平均，ms）：'
  "  引擎启动（进程创建→Dart main，估；从日志文件创建时间倒推）：$($avg.EngineMs)"
  "  Dart main → 日志/基础路径就绪（AppPaths+Log.init）：$($avg.PathsMs)"
  "  AppPaths/Log → 配置就绪（DataRootMigration+TokenEncryptor+config 读盘/备份/保存）：$($avg.ConfigDelta)"
  "  配置 → 云服务就绪（服务初始化）：$($avg.ServiceDelta)"
  "  云服务 → 游戏进程创建（Java 校验/云同步/settings/内存估算/起 JVM）：$($avg.GameSpawnMs)"
  "  游戏进程创建 → 游戏可交互（JVM 启动 + 游戏/模组加载 + 日志转发）：$($avg.GameLoadDelta)"
  "  其中游戏日志自报 Total time to load（游戏自身加载）：$($avg.GameTotal)"
  "  其中 JVM 启动 + 日志转发（GameLoad - 游戏自报）：$($avg.JvmMs)"
  "  外部总耗时（进程创建 → 脚本察觉，含轮询 ${PollMs}ms 误差）：$($avg.TotalMs)，中位数 $($avg.MedianTotalMs)"
} else {
  '没有一次成功加载（检查游戏 / 云服务日志）'
  exit 1
}
