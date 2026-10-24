$ErrorActionPreference = 'Continue'
Write-Output "== HTTP 状态 =="
$urls = @(
  'http://192.168.100.1/',
  'http://192.168.100.1/cgi-bin/luci/',
  'http://192.168.100.1/cgi-bin/luci/admin/status/overview',
  'http://192.168.100.1/cgi-bin/luci/admin/network/network',
  'http://192.168.100.1/cgi-bin/luci/admin/system/system',
  'http://192.168.100.1/cgi-bin/luci/admin/services/',
  'http://192.168.100.1/luci-static/resources/luci.js',
  'http://192.168.100.1/luci-static/resources/view/status/include/10_system.js'
)
foreach ($u in $urls) {
  try {
    $req = [System.Net.WebRequest]::Create($u)
    $req.Method = 'GET'
    $req.Timeout = 10000
    $req.AllowAutoRedirect = $false
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $loc = $resp.Headers['Location']
    $len = $resp.ContentLength
    $resp.Close()
    "{0} {1} len={2} loc={3}" -f $code, $u, $len, $loc
  } catch [System.Net.WebException] {
    if ($_.Exception.Response) {
      $r = $_.Exception.Response
      "{0} {1} (exception) loc={2}" -f [int]$r.StatusCode, $u, $r.Headers['Location']
    } else {
      "ERR $u : $($_.Exception.Message)"
    }
  } catch {
    "ERR $u : $($_.Exception.Message)"
  }
}

Write-Output "== C7 LAN 吞吐（PC 监听 5201，设备发送 512MB）=="
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, 5201)
try {
  $listener.Start()
} catch {
  Write-Output "listener-failed: $($_.Exception.Message)"
  exit 1
}
$key = 'C:\Users\somma\Desktop\e87n\e87n_key'
$remote = 'dd if=/dev/zero bs=64k count=8000 2>/dev/null | nc 192.168.100.124 5201'
$cmdline = 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=10 -i "' + $key + '" root@192.168.100.1 "' + $remote + '"'
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmdline -PassThru -WindowStyle Hidden
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$acceptTask = $listener.AcceptTcpClientAsync()
if (-not $acceptTask.Wait(15000)) {
  Write-Output "accept-timeout (PC 防火墙可能拦截入站 5201)"
  $p.Kill()
  $listener.Stop()
  exit 1
}
$client = $acceptTask.Result
$stream = $client.GetStream()
$buf = New-Object byte[] 65536
$total = 0
while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $total += $n }
$sw.Stop()
$stream.Close(); $client.Close(); $listener.Stop()
$p.WaitForExit(5000) | Out-Null
$secs = $sw.Elapsed.TotalSeconds
$mbps = ($total * 8 / 1000000) / $secs
"bytes={0} secs={1:N2} Mbps={2:N1}" -f $total, $secs, $mbps
