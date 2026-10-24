$ErrorActionPreference = 'Continue'
Write-Output "== LuCI 空密码登录 + 页面状态 =="
$base = 'http://192.168.100.1'
$cookies = New-Object System.Net.CookieContainer
$body = [System.Text.Encoding]::UTF8.GetBytes('username=root&password=')
try {
  $req = [System.Net.WebRequest]::Create("$base/cgi-bin/luci/")
  $req.Method = 'POST'
  $req.ContentType = 'application/x-www-form-urlencoded'
  $req.ContentLength = $body.Length
  $req.AllowAutoRedirect = $false
  $req.CookieContainer = $cookies
  $req.Timeout = 10000
  $st = $req.GetRequestStream(); $st.Write($body, 0, $body.Length); $st.Close()
  $resp = $req.GetResponse()
  Write-Output ("login: {0} loc={1}" -f [int]$resp.StatusCode, $resp.Headers['Location'])
  $resp.Close()
} catch [System.Net.WebException] {
  if ($_.Exception.Response) {
    $r = $_.Exception.Response
    Write-Output ("login: {0} loc={1}" -f [int]$r.StatusCode, $r.Headers['Location'])
  } else { Write-Output "login ERR: $($_.Exception.Message)" }
}
foreach ($u in @(
  "$base/cgi-bin/luci/",
  "$base/cgi-bin/luci/admin/status/overview",
  "$base/cgi-bin/luci/admin/network/network",
  "$base/cgi-bin/luci/admin/system/system",
  "$base/cgi-bin/luci/admin/services/",
  "$base/cgi-bin/luci/admin/system/admin/ssh",
  "$base/cgi-bin/luci/admin/system/reboot"
)) {
  try {
    $req = [System.Net.WebRequest]::Create($u)
    $req.AllowAutoRedirect = $false
    $req.CookieContainer = $cookies
    $req.Timeout = 10000
    $resp = $req.GetResponse()
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $txt = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
    $hasLogin = $txt -match 'luci.login|login-form|password'
    "{0} {1} len={2} loginform={3}" -f [int]$resp.StatusCode, $u, $txt.Length, $hasLogin
  } catch [System.Net.WebException] {
    if ($_.Exception.Response) { "{0} {1} (exception)" -f [int]$_.Exception.Response.StatusCode, $u }
    else { "ERR $u : $($_.Exception.Message)" }
  }
}
