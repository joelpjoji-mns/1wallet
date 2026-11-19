Add-Type -AssemblyName System.Drawing

$imgDir = (Resolve-Path "android/fastlane/metadata/android/en-US/images").Path

for ($i = 1; $i -le 5; $i++) {
    $rawPath = Join-Path $imgDir "raw_screenshot_$i.png"
    $outPath = Join-Path $imgDir "screenshot_phone_$i.png"
    
    if (Test-Path $rawPath) {
        $fileBytes = [System.IO.File]::ReadAllBytes($rawPath)
        $ms = New-Object System.IO.MemoryStream(,$fileBytes)
        $src = [System.Drawing.Image]::FromStream($ms)
        
        $targetWidth = 1080
        $targetHeight = 1920
        $bmp = New-Object System.Drawing.Bitmap $targetWidth, $targetHeight
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(14, 14, 16))
        $g.FillRectangle($brush, 0, 0, $targetWidth, $targetHeight)
        
        # Fit height 1920
        $scale = [double]$targetHeight / [double]$src.Height
        $newW = [int]([double]$src.Width * $scale)
        $newH = $targetHeight
        $posX = [int](($targetWidth - $newW) / 2)
        $posY = 0
        
        $g.DrawImage($src, $posX, $posY, $newW, $newH)
        
        $src.Dispose()
        $ms.Dispose()
        $g.Dispose()
        
        $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host "Generated $outPath : $targetWidth x $targetHeight"
    }
}
