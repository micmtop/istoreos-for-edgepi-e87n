Add-Type -AssemblyName System.Drawing
$w = 428; $h = 142
$raw = [IO.File]::ReadAllBytes('C:\Users\somma\Desktop\e87n\e87n-istoreos-build\test-20261024\k6.raw')
$bmp = New-Object System.Drawing.Bitmap($w, $h)
for ($y = 0; $y -lt $h; $y++) {
  for ($x = 0; $x -lt $w; $x++) {
    $i = ($y * $w + $x) * 2
    $v = [int]$raw[$i] -bor ([int]$raw[$i + 1] -shl 8)
    $r = [int]((($v -shr 11) -band 31) * 255 / 31)
    $g = [int]((($v -shr 5) -band 63) * 255 / 63)
    $b = [int](($v -band 31) * 255 / 31)
    $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($r, $g, $b))
  }
}
$bmp.Save('C:\Users\somma\Desktop\e87n\e87n-istoreos-build\test-20261024\k6-page1.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved"
