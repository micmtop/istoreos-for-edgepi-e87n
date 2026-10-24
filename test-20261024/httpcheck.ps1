$ErrorActionPreference = 'Continue'
$urls = @(
  'http://192.168.100.1/',
  'http://192.168.100.1/cgi-bin/luci/',
  'http://192.168.100.1/cgi-bin/luci/admin/status/overview',
  'http://192.168.100.1/cgi-bin/luci/admin/network/network',
  'http://192.168.100.1/cgi-bin/luci/admin/system/system',
  'http://192.168.100.1/cgi-bin/luci/admin/services/',
  'http://192.168.100.1/cgi-bin/luci/admin/system/reboot',
  'http://192.168.100.1/luci-static/resources/luci.js'
)
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false
$c = New-Object System.Net.Http.HttpClient($handler)
$c.Timeout = [TimeSpan]::FromSeconds(10)
foreach ($u in $urls) {
  try {
    $r = $c.GetAsync($u).Result
    $loc = ''
    if ($r.Headers.Location) { $loc = " -> $($r.Headers.Location)" }
    "{0} {1}{2}" -f [int]$r.StatusCode, $u, $loc
  } catch {
    "ERR $u : $($_.Exception.Message)"
  }
}
