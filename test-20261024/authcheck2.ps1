$ErrorActionPreference = 'Continue'
$base = 'http://192.168.100.1'
$cookies = New-Object System.Net.CookieContainer
function Fetch($url, $method, $body, $cookies) {
  try {
    $req = [System.Net.WebRequest]::Create($url)
    $req.Method = $method
    $req.AllowAutoRedirect = $false
    $req.CookieContainer = $cookies
    $req.Timeout = 10000
    if ($body) {
      $b = [Text.Encoding]::UTF8.GetBytes($body)
      $req.ContentType = 'application/x-www-form-urlencoded'
      $req.ContentLength = $b.Length
      $s = $req.GetRequestStream(); $s.Write($b,0,$b.Length); $s.Close()
    }
    $r = $req.GetResponse()
    $sr = New-Object IO.StreamReader($r.GetResponseStream())
    $t = $sr.ReadToEnd(); $sr.Close()
    return @{ code = [int]$r.StatusCode; body = $t; location = $r.Headers['Location'] }
  } catch [System.Net.WebException] {
    if ($_.Exception.Response) {
      $r = $_.Exception.Response
      $sr = New-Object IO.StreamReader($r.GetResponseStream())
      $t = $sr.ReadToEnd(); $sr.Close()
      return @{ code = [int]$r.StatusCode; body = $t; location = $r.Headers['Location'] }
    }
    return @{ code = -1; body = $_.Exception.Message; location = '' }
  }
}
$g = Fetch "$base/cgi-bin/luci/" 'GET' $null $cookies
Write-Output ("GET login: {0} len={1} loc={2}" -f $g.code, $g.body.Length, $g.location)
$tok = ''
$m = [regex]::Match($g.body, 'name="token"\s+value="([^"]*)"')
if ($m.Success) { $tok = $m.Groups[1].Value }
Write-Output "token=$tok"
Write-Output "cookies:"
foreach ($c in $cookies.GetCookies($base)) { Write-Output ("  {0}={1}" -f $c.Name, $c.Value) }
$m2 = [regex]::Match($g.body, 'name="([^"]*)"')
Write-Output ("first-input={0}" -f $m2.Groups[1].Value)
$body = "luci_username=root&luci_password=&token=$tok"
$p = Fetch "$base/cgi-bin/luci/" 'POST' $body $cookies
Write-Output ("POST login: {0} loc={1} len={2}" -f $p.code, $p.location, $p.body.Length)
Write-Output "cookies after:"
foreach ($c in $cookies.GetCookies($base)) { Write-Output ("  {0}={1}" -f $c.Name, $c.Value) }
foreach ($u in @(
  "$base/cgi-bin/luci/",
  "$base/cgi-bin/luci/admin/status/overview",
  "$base/cgi-bin/luci/admin/network/network",
  "$base/cgi-bin/luci/admin/system/system",
  "$base/cgi-bin/luci/admin/services/",
  "$base/cgi-bin/luci/admin/system/admin/ssh",
  "$base/cgi-bin/luci/admin/system/reboot",
  "$base/cgi-bin/luci/admin/system/package-manager"
)) {
  $r = Fetch $u 'GET' $null $cookies
  $login = $r.body -match 'luci_username'
  "{0} {1} len={2} loginform={3} loc={4}" -f $r.code, $u, $r.body.Length, $login, $r.location
}
