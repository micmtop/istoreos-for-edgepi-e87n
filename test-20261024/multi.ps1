$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Diagnostics;
public class ParallelRx {
    public static string Run(int[] ports) {
        var listeners = new TcpListener[ports.Length];
        for (int i = 0; i < ports.Length; i++) {
            listeners[i] = new TcpListener(IPAddress.Any, ports[i]);
            listeners[i].Start();
        }
        var sw = Stopwatch.StartNew();
        var tasks = new Task<long>[ports.Length];
        for (int i = 0; i < ports.Length; i++) {
            int idx = i;
            tasks[i] = Task.Run(async () => {
                using (var c = await listeners[idx].AcceptTcpClientAsync()) {
                    var s = c.GetStream();
                    var buf = new byte[262144];
                    long t = 0; int n;
                    while ((n = await s.ReadAsync(buf, 0, buf.Length)) > 0) t += n;
                    return t;
                }
            });
        }
        Task.WaitAll(tasks, 120000);
        sw.Stop();
        long total = 0;
        foreach (var t in tasks) if (t.Status == TaskStatus.RanToCompletion) total += t.Result;
        foreach (var l in listeners) l.Stop();
        double mbps = total * 8.0 / 1000000.0 / sw.Elapsed.TotalSeconds;
        return string.Format("bytes={0} secs={1:F2} aggregateMbps={2:F1}", total, sw.Elapsed.TotalSeconds, mbps);
    }
}
"@
$key = 'C:\Users\somma\Desktop\e87n\e87n_key'
$ip = '192.168.100.124'
$ports = @(5201, 5202, 5203, 5204)
$each = 256
$procs = @()
for ($i = 0; $i -lt $ports.Count; $i++) {
  $remote = "dd if=/dev/zero bs=1M count=$each 2>/dev/null | nc $ip $($ports[$i])"
  $cmdline = 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=10 -i "' + $key + '" root@192.168.100.1 "' + $remote + '"'
  $procs += Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmdline -PassThru -WindowStyle Hidden
}
$res = [ParallelRx]::Run([int[]]$ports)
Write-Output $res
foreach ($p in $procs) { $p.WaitForExit(5000) | Out-Null }
