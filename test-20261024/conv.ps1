param([string]$In, [string]$Out)
Add-Type -AssemblyName System.Drawing
$w = 428; $h = 142
$raw = [IO.File]::ReadAllBytes($In)
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
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "$In -> $Out"
