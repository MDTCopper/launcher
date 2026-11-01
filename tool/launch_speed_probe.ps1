param(
  [int]$Runs = 3,
  [string]$VersionId = 'f7078a96-d701-4593-a7b9-17d5946773ea',
  [int]$TimeoutSeconds = 120
)

# 冷启动测速：从进程启动到「游戏可交互」（游戏日志 Total time to load）
# 只用于 Windows 调试 / 发布包，结果依赖机器状态，跑 3~5 次取平均

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root 'build\windows\x64\runner\Debug\copper_launcher.exe'
if (-not (Test-Path $exe)) {
  $exe = Join-Path $root 'build\windows\x64\runner\Release\copper_launcher.exe'
}
if (-not (Test-Path $exe)) { throw "找不到构建产物：$exe" }

# 数据根：checkout 内构建产物的数据根是 <仓库>\data（见 AppPaths 的 checkout 分支），
# 日志与云服务态都在这个目录下，不在仓库根
$dataDir = Join-Path $root 'data'
$logsDir = Join-Path $dataDir 'logs'
$sessionsDir = Join-Path $dataDir 'cloud-service\sessions'
$serviceDir = Join-Path $dataDir 'cloud-service'

function Stop-GameProcesses {
  Get-CimInstance Win32_Process -Filter "Name='copper_launcher.exe' OR Name='java.exe'" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
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
  $match = [regex]::Match($text, [regex]::Escape($label) + '\s*\+(\d+)ms')
  if ($match.Success) { return [int]$match.Groups[1].Value }
  return $null
}

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
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $log = $null
  $loaded = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
    $log = Get-NewLogFile $before
    if ($log) {
      $text = Get-Content $log.FullName -Raw -ErrorAction SilentlyContinue
      if ($text -match '游戏可交互') { $loaded = $true; break }
      if ($text -match '启动失败|找不到版本') { break }
    }
  }
  $watch.Stop()

  $text = if ($log) { Get-Content $log.FullName -Raw -ErrorAction SilentlyContinue } else { '' }
  $row = [pscustomobject]@{
    Run        = $i
    TotalMs    = $watch.ElapsedMilliseconds
    Loaded     = $loaded
    PathsMs    = Get-TimelineValue $text '时间线：基础路径就绪'
    ConfigMs   = Get-TimelineValue $text '时间线：配置就绪'
    ServiceMs  = Get-TimelineValue $text '时间线：云服务就绪'
    GameProcMs = Get-TimelineValue $text '时间线：游戏进程已创建'
    GameLoadMs = Get-TimelineValue $text '时间线：游戏可交互'
    Log        = if ($log) { $log.Name } else { '' }
  }
  $results += $row
  $row | Format-Table -AutoSize

  Stop-GameProcesses
}

"`n===== 平均 ====="
$loadedRows = $results | Where-Object { $_.Loaded }
if ($loadedRows) {
  $avg = [pscustomobject]@{
    Runs       = $loadedRows.Count
    TotalMs    = [int](($loadedRows | Measure-Object TotalMs -Average).Average)
    ConfigMs   = [int](($loadedRows | Where-Object ConfigMs -ne $null | Measure-Object ConfigMs -Average).Average)
    ServiceMs  = [int](($loadedRows | Where-Object ServiceMs -ne $null | Measure-Object ServiceMs -Average).Average)
    GameProcMs = [int](($loadedRows | Where-Object GameProcMs -ne $null | Measure-Object GameProcMs -Average).Average)
    GameLoadMs = [int](($loadedRows | Where-Object GameLoadMs -ne $null | Measure-Object GameLoadMs -Average).Average)
  }
  $avg | Format-Table -AutoSize
} else {
  '没有一次成功加载（检查游戏 / 云服务日志）'
}
