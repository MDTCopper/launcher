<#
.SYNOPSIS
    Build a Mindustry blueprint-preview asset pack from a game jar.

.DESCRIPTION
    CPU-only pipeline: reads the packed sprite atlas and game content tables from
    a Mindustry desktop jar with the Java tools in ./src, then writes the pack
    consumed by lib/domain/preview.

    Steps:
      1. compile src/*.java (javac --release 17)
      2. AtlasDump index    -> atlas region table
      3. ContentDump        -> content.json (blocks/items/liquids)
      4. BlockDrawDump / CanvasDump / DrawerDump -> classes/canvas/drawer json
      5. AtlasDump extract  -> parts (block-name regions + shared extras)
      6. AtlasDump extract  -> icons/block|item|liquid|generic, write meta.json

    No Python, no System.Drawing, no GL, no game window.

.PARAMETER JarPath
    Path to the Mindustry desktop jar, e.g. data/mindustrys/mindustry-v160.7-314baa30.jar

.PARAMETER OutDirPath
    Target asset-pack directory. Managed files/dirs inside it are replaced.

.PARAMETER Version
    Version label stored in meta.json. Default: parsed from the jar file name, or 'unknown'.

.PARAMETER WorkDirPath
    Intermediate directory (classes, json, raw PNG). Default: a new temp directory.

.EXAMPLE
    pwsh -File tool/preview_assets/build_pack.ps1 `
        -JarPath data/mindustrys/mindustry-v160.7-314baa30.jar `
        -OutDirPath tmp/bp-research/m1/pack-nu -Version v160.7
#>

param(
    [string]$JarPath,
    [string]$OutDirPath,
    [string]$Version,
    [string]$WorkDirPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($JarPath)) { throw 'Missing required parameter -JarPath' }
if ([string]::IsNullOrWhiteSpace($OutDirPath)) { throw 'Missing required parameter -OutDirPath' }

# ---------------------------------------------------------------- helpers

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

$jarFull = Resolve-InputPath $JarPath
if (-not (Test-Path -LiteralPath $jarFull -PathType Leaf)) {
    throw "Jar not found: $jarFull"
}
$jarLeaf = Split-Path -Leaf $jarFull
$outDir = Resolve-InputPath $OutDirPath

if ([string]::IsNullOrWhiteSpace($Version)) {
    if ($jarLeaf -match 'v(\d+(?:\.\d+)*)') {
        $Version = 'v' + $Matches[1]
    } elseif ($jarLeaf -match 'Build\s+(\d+)') {
        $Version = 'Build ' + $Matches[1]
    } else {
        $Version = 'unknown'
    }
}

if ([string]::IsNullOrWhiteSpace($WorkDirPath)) {
    $WorkDirPath = Join-Path ([System.IO.Path]::GetTempPath()) ('mindustry-preview-assets-' + [guid]::NewGuid().ToString('N'))
}
$workDir = Resolve-InputPath $WorkDirPath

foreach ($tool in @('java', 'javac')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool not found in PATH (JDK 17+ required)"
    }
}

$classesDir = Join-Path $workDir 'classes'
New-Item -ItemType Directory -Force -Path $classesDir | Out-Null
$classPath = $jarFull + [System.IO.Path]::PathSeparator + $classesDir

function Invoke-PreviewJava([string]$MainClass, [string[]]$Arguments) {
    $stdout = & java '-cp' $classPath $MainClass @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $stdout) { Write-Host "  $line" }
    if ($exitCode -ne 0) { throw "$MainClass failed (exit code $exitCode)" }
}

# Extract a set of icon regions: raw PNGs named after the region, then copy each
# to <targetDir>/<content-name>.png. $Mapping is content name -> atlas region name.
function Export-IconSet([hashtable]$Mapping, [string]$RawDir, [string]$TargetDir, [string]$ListName) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    if ($Mapping.Count -eq 0) { return 0 }
    $listFile = Join-Path $workDir $ListName
    @($Mapping.Values | Sort-Object -Unique) | Set-Content -LiteralPath $listFile -Encoding ASCII
    Invoke-PreviewJava 'AtlasDump' @('extract', $jarFull, $RawDir, $listFile, '--exact')
    $count = 0
    foreach ($entry in $Mapping.GetEnumerator()) {
        $source = Join-Path $RawDir ($entry.Value + '.png')
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        Copy-Item -LiteralPath $source -Destination (Join-Path $TargetDir ($entry.Key + '.png')) -Force
        $count++
    }
    return $count
}

# ---------------------------------------------------------------- prepare

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
foreach ($sub in @('icons', 'parts')) {
    $target = Join-Path $outDir $sub
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
foreach ($name in @('content.json', 'classes.json', 'canvas.json', 'drawer-spec.json', 'meta.json')) {
    $target = Join-Path $outDir $name
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
}

Write-Host "[preview_assets] jar=$jarLeaf version=$Version"
Write-Host "[preview_assets] out=$outDir"
Write-Host "[preview_assets] work=$workDir"

# ---------------------------------------------------------------- 1. compile

Write-Host '[1/6] compile tools'
$sources = @(Get-ChildItem -LiteralPath $srcDir -Filter '*.java' -File | ForEach-Object { $_.FullName })
if ($sources.Count -eq 0) { throw "No Java sources in $srcDir" }
$javacOut = & javac '--release' '17' '-encoding' 'UTF-8' '-cp' $jarFull '-d' $classesDir @sources 2>&1
if ($LASTEXITCODE -ne 0) {
    foreach ($line in $javacOut) { Write-Host "  $line" }
    throw "javac failed (exit code $LASTEXITCODE)"
}

# ---------------------------------------------------------------- 2. atlas index

Write-Host '[2/6] atlas index'
$atlasIndexPath = Join-Path $workDir 'atlas-index.json'
Invoke-PreviewJava 'AtlasDump' @('index', $jarFull, $atlasIndexPath)

# ---------------------------------------------------------------- 3. content table

Write-Host '[3/6] content table'
$contentPath = Join-Path $workDir 'content.json'
Invoke-PreviewJava 'ContentDump' @($contentPath)

# ---------------------------------------------------------------- 4. rule data

Write-Host '[4/6] classes / canvas / drawer spec'
$classesPath = Join-Path $workDir 'classes.json'
$canvasPath = Join-Path $workDir 'canvas.json'
$drawerSpecPath = Join-Path $workDir 'drawer-spec.json'
Invoke-PreviewJava 'BlockDrawDump' @($classesPath)
Invoke-PreviewJava 'CanvasDump' @($canvasPath)
Invoke-PreviewJava 'DrawerDump' @($drawerSpecPath)

# ---------------------------------------------------------------- 5. parts

Write-Host '[5/6] parts'
$content = Get-Content -LiteralPath $contentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$atlas = Get-Content -LiteralPath $atlasIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $content.blocks) { throw "content.json has no blocks: $contentPath" }
if ($null -eq $atlas.regions) { throw "atlas-index.json has no regions: $atlasIndexPath" }

$regionNameSet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($region in $atlas.regions) { [void]$regionNameSet.Add([string]$region.name) }

$blockNames = @($content.blocks | ForEach-Object { [string]$_.name })
$partsNamesFile = Join-Path $workDir 'parts-names.txt'
$blockNames | Set-Content -LiteralPath $partsNamesFile -Encoding ASCII
$partsRawDir = Join-Path $workDir 'parts'
Invoke-PreviewJava 'AtlasDump' @('extract', $jarFull, $partsRawDir, $partsNamesFile)

# shared regions referenced by the draw rules but not owned by one block
$extraParts = @(
    'center', 'cross', 'laser', 'laser-end',
    'block-1', 'block-2', 'block-3', 'block-4',
    'reinforced-block-2', 'reinforced-block-3', 'reinforced-block-4', 'reinforced-block-5'
)
$extrasFile = Join-Path $workDir 'parts-extras.txt'
$extraParts | Set-Content -LiteralPath $extrasFile -Encoding ASCII
Invoke-PreviewJava 'AtlasDump' @('extract', $jarFull, $partsRawDir, $extrasFile, '--exact')

$outPartsDir = Join-Path $outDir 'parts'
New-Item -ItemType Directory -Force -Path $outPartsDir | Out-Null
Get-ChildItem -LiteralPath $partsRawDir -Filter '*.png' -File | Copy-Item -Destination $outPartsDir -Force
$partsCount = @(Get-ChildItem -LiteralPath $outPartsDir -Filter '*.png' -File).Count
Write-Host "  parts=$partsCount"

# ---------------------------------------------------------------- 6. icons

Write-Host '[6/6] icons'
$blockUi = @{}
$blockFull = @{}
$itemUi = @{}
$liquidUi = @{}
foreach ($region in $atlas.regions) {
    $name = [string]$region.name
    if ($name -match '^block-(.+)-ui$') { $blockUi[$Matches[1]] = $name }
    elseif ($name -match '^block-(.+)-full$') { $blockFull[$Matches[1]] = $name }
    elseif ($name -match '^item-(.+)-ui$') { $itemUi[$Matches[1]] = $name }
    elseif ($name -match '^liquid-(.+)-ui$') { $liquidUi[$Matches[1]] = $name }
}

# prefer -full (includes top layers), fall back to -ui
$blockIconMap = @{}
foreach ($key in $blockUi.Keys) { $blockIconMap[$key] = $blockUi[$key] }
foreach ($key in $blockFull.Keys) { $blockIconMap[$key] = $blockFull[$key] }

$blockIconCount = Export-IconSet $blockIconMap (Join-Path $workDir 'icons-block-raw') (Join-Path $outDir 'icons\block') 'icons-block.txt'
$itemIconCount = Export-IconSet $itemUi (Join-Path $workDir 'icons-item-raw') (Join-Path $outDir 'icons\item') 'icons-item.txt'
$liquidIconCount = Export-IconSet $liquidUi (Join-Path $workDir 'icons-liquid-raw') (Join-Path $outDir 'icons\liquid') 'icons-liquid.txt'

# generic marks used by config_marks.dart / plan_draw_rule.dart
$genericRawDir = Join-Path $workDir 'icons-generic-raw'
$genericFile = Join-Path $workDir 'icons-generic.txt'
@('center', 'cross') | Set-Content -LiteralPath $genericFile -Encoding ASCII
Invoke-PreviewJava 'AtlasDump' @('extract', $jarFull, $genericRawDir, $genericFile, '--exact')
$outGenericDir = Join-Path $outDir 'icons\generic'
New-Item -ItemType Directory -Force -Path $outGenericDir | Out-Null
Get-ChildItem -LiteralPath $genericRawDir -Filter '*.png' -File | Copy-Item -Destination $outGenericDir -Force
$genericIconCount = @(Get-ChildItem -LiteralPath $outGenericDir -Filter '*.png' -File).Count

Write-Host "  icons: block=$blockIconCount item=$itemIconCount liquid=$liquidIconCount generic=$genericIconCount"

# ---------------------------------------------------------------- assemble

Copy-Item -LiteralPath $contentPath -Destination (Join-Path $outDir 'content.json') -Force
Copy-Item -LiteralPath $classesPath -Destination (Join-Path $outDir 'classes.json') -Force
Copy-Item -LiteralPath $canvasPath -Destination (Join-Path $outDir 'canvas.json') -Force
Copy-Item -LiteralPath $drawerSpecPath -Destination (Join-Path $outDir 'drawer-spec.json') -Force

$meta = [ordered]@{
    version     = $Version
    jar         = $jarLeaf
    generatedBy = 'tool/preview_assets/build_pack.ps1'
    # content block count (same as content.json blocks, not icon file count)
    blocks      = $content.blocks.Count
    blockIcons  = $blockIconCount
    itemIcons   = $itemIconCount
    liquidIcons = $liquidIconCount
    parts       = $partsCount
    icons       = $blockIconCount + $itemIconCount + $liquidIconCount
}
$metaJson = $meta | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $outDir 'meta.json'), $metaJson, $utf8NoBom)

Write-Host ''
Write-Host "[preview_assets] pack written: $outDir"
Write-Host "  version=$Version blocks=$($content.blocks.Count) blockIcons=$blockIconCount itemIcons=$itemIconCount liquidIcons=$liquidIconCount parts=$partsCount"
Write-Host "  workdir=$workDir"
