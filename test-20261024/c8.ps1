$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Diagnostics;
public class Rx5Min {
    public static string Run(int port) {
        var l = new TcpListener(IPAddress.Any, port);
        l.Start();
        var sw = Stopwatch.StartNew();
        long total = 0;
        var t = Task.Run(async () => {
            using (var c = await l.AcceptTcpClientAsync()) {
                var s = c.GetStream();
                var buf = new byte[262144];
                int n;
                while ((n = await s.ReadAsync(buf, 0, buf.Length)) > 0) total += n;
            }
        });
        if (!t.Wait(380000)) { l.Stop(); return "TIMEOUT bytes=" + total; }
        sw.Stop();
        l.Stop();
        return string.Format("bytes={0} secs={1:F2} Mbps={2:F1}", total, sw.Elapsed.TotalSeconds, total * 8.0 / 1000000.0 / sw.Elapsed.TotalSeconds);
    }
}
"@
$key = 'C:\Users\somma\Desktop\e87n\e87n_key'
$ssh = 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=10 -i "' + $key + '" root@192.168.100.1'
$sampler = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ($ssh + ' "i=0; while [ $i -lt 45 ]; do echo $(date +%s) $(cat /sys/class/hwmon/hwmon0/temp1_input) $(cat /sys/class/hwmon/hwmon2/pwm1); sleep 10; i=$((i+1)); done > /tmp/c8.log"') -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$sender = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ($ssh + ' "dd if=/dev/zero bs=1M count=17000 2>/dev/null | nc 192.168.100.124 5301"') -PassThru -WindowStyle Hidden
$res = [Rx5Min]::Run(5301)
Write-Output $res
$sender.WaitForExit(30000) | Out-Null
$sampler.WaitForExit(5000) | Out-Null
Write-Output "== device post =="
cmd /c ($ssh + ' "ip -s link show eth0 | tail -6; dmesg | grep -c \"Link is Down\"; dmesg | tail -5; echo ---; tail -20 /tmp/c8.log; echo ---; cat /sys/class/hwmon/hwmon0/temp1_input"')
