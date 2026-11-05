# 由 icon_src/ 的源图重出安卓自适应图标前景层
#
# 规则见 icon_src/README.md：
#   1. 传送带铺底 + 物品原图 1:1 盖上；
#   2. 整张图缩到 108dp 画布的 72dp（系统只显示中间 72dp）并居中；
#   3. 每个密度各出一张前景 PNG。
#
# 用法： powershell -ExecutionPolicy Bypass -File tool\gen_launcher_icons.ps1

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'icon_src'
$res = Join-Path $root 'android\app\src\main\res'

# 主题 -> (物品源图, 传送带源图, 前景文件名)
$themes = [ordered]@{
    copper     = @('copper.png',     'conveyor.png',            'ic_launcher_foreground.png')
    titanium   = @('titanium.png',   'titanium-conveyor.png',   'ic_launcher_foreground_titanium.png')
    thorium    = @('thorium.png',    'armored-conveyor.png',    'ic_launcher_foreground_thorium.png')
    plastanium = @('plastanium.png', 'plastanium-conveyor.png', 'ic_launcher_foreground_plastanium.png')
}

$densities = [ordered]@{ mdpi = 108; hdpi = 162; xhdpi = 216; xxhdpi = 324; xxxhdpi = 432 }

foreach ($theme in $themes.Keys) {
    $itemPath, $conveyorPath, $fileName = $themes[$theme]

    # 1. 1:1 合成
    $composed = [System.Drawing.Bitmap]::FromFile((Join-Path $src $conveyorPath))
    $item = [System.Drawing.Image]::FromFile((Join-Path $src $itemPath))
    $g = [System.Drawing.Graphics]::FromImage($composed)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($item, [System.Drawing.Rectangle]::new(0, 0, 1024, 1024))
    $g.Dispose()
    $item.Dispose()

    # 2. 每个密度缩到画布的 72/108 并居中
    foreach ($density in $densities.Keys) {
        $size = $densities[$density]
        $side = [int][Math]::Round($size * 72.0 / 108.0)
        $offset = [int][Math]::Floor(($size - $side) / 2)

        $bitmap = [System.Drawing.Bitmap]::new($size, $size)
        $fg = [System.Drawing.Graphics]::FromImage($bitmap)
        $fg.SmoothingMode = 'AntiAlias'
        $fg.InterpolationMode = 'HighQualityBicubic'
        $fg.PixelOffsetMode = 'HighQuality'
        $fg.Clear([System.Drawing.Color]::Transparent)
        $fg.DrawImage($composed, [System.Drawing.Rectangle]::new($offset, $offset, $side, $side))
        $fg.Dispose()

        $outPath = Join-Path (Join-Path $res "mipmap-$density") $fileName
        $bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
    }

    $composed.Dispose()
    Write-Output "前景已重出: $theme -> $fileName"
}