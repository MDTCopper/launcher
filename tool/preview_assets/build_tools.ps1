<#
.SYNOPSIS
    Compile the preview asset tools into a self-contained jar.

.DESCRIPTION
    Builds tool/preview_assets/src/*.java against the Mindustry game jar and writes
    assets/preview_tools/preview_tools.jar. The jar holds PackBuilder,
    MapPreviewExport and the shared dump/atlas helpers; at runtime it is put on the
    classpath AFTER the game jar (Boot.locateJar takes the first .jar from classpath).

    Requires JDK 17+ (java / javac / jar in PATH). No other dependency.

.PARAMETER GameJarPath
    Game jar used for compilation. Default: data/mindustrys/mindustry-v160.7-314baa30.jar

.PARAMETER OutJarPath
    Output jar path. Default: assets/preview_tools/preview_tools.jar

.PARAMETER WorkDirPath
    Optional intermediate directory (classes). Default: a temp directory.

.EXAMPLE
    .\tool\preview_assets\build_tools.ps1
#>

param(
    [string]$GameJarPath,
    [string]$OutJarPath,
    [string]$WorkDirPath
)

$ErrorActionPreference = 'Stop'

function Resolve-InputPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

$scriptDir = $PSScriptRoot
$srcDir = Join-Path $scriptDir 'src'
if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) {
    throw "Source directory not found: $srcDir"
}
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

if ([string]::IsNullOrWhiteSpace($GameJarPath)) {
    $GameJarPath = Join-Path $repoRoot 'data\mindustrys\mindustry-v160.7-314baa30.jar'
}
if ([string]::IsNullOrWhiteSpace($OutJarPath)) {
    $OutJarPath = Join-Path $repoRoot 'assets\preview_tools\preview_tools.jar'
}
$gameJarFull = Resolve-InputPath $GameJarPath
if (-not (Test-Path -LiteralPath $gameJarFull -PathType Leaf)) {
    throw "Game jar not found: $gameJarFull (pass -GameJarPath)"
}
$outJarFull = Resolve-InputPath $OutJarPath

if ([string]::IsNullOrWhiteSpace($WorkDirPath)) {
    $WorkDirPath = Join-Path ([System.IO.Path]::GetTempPath()) ('preview-tools-' + [guid]::NewGuid().ToString('N'))
}
$workDir = Resolve-InputPath $WorkDirPath
$classesDir = Join-Path $workDir 'classes'
New-Item -ItemType Directory -Force -Path $classesDir | Out-Null

foreach ($tool in @('java', 'javac', 'jar')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool not found in PATH (JDK 17+ required)"
    }
}

Write-Host "[build_tools] game jar=$gameJarFull"
Write-Host "[build_tools] sources=$srcDir"

$sources = @(Get-ChildItem -LiteralPath $srcDir -Filter '*.java' -File | ForEach-Object { $_.FullName })
if ($sources.Count -eq 0) { throw "No Java sources in $srcDir" }

$compileOut = & javac '--release' '17' '-encoding' 'UTF-8' '-cp' $gameJarFull '-d' $classesDir @sources 2>&1
if ($LASTEXITCODE -ne 0) {
    foreach ($line in $compileOut) { Write-Host "  $line" }
    throw "javac failed (exit code $LASTEXITCODE)"
}

$outParent = Split-Path -Parent $outJarFull
if (-not (Test-Path -LiteralPath $outParent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $outParent | Out-Null
}
if (Test-Path -LiteralPath $outJarFull) { Remove-Item -LiteralPath $outJarFull -Force }

$jarOut = & jar '--create' '--file' $outJarFull '-C' $classesDir '.' 2>&1
if ($LASTEXITCODE -ne 0) {
    foreach ($line in $jarOut) { Write-Host "  $line" }
    throw "jar failed (exit code $LASTEXITCODE)"
}

$jarSize = (Get-Item -LiteralPath $outJarFull).Length
Write-Host "[build_tools] written $outJarFull ($jarSize bytes) from $($sources.Count) sources"
