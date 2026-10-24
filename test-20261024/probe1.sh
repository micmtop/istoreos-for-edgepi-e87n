echo "===== A1 版本/机型"
cat /etc/openwrt_release; tr -d '\0' < /proc/device-tree/model; echo
echo "===== A2 启动耗时"
dmesg | grep -m1 "procd: - init -"
cut -d. -f1 /proc/uptime
echo "===== A3 启动报错"
dmesg | grep -iE "error|failed|call trace|warn|panic" | head -40
echo "===== A4 overlay"
df -h /overlay
touch /etc/.rwtest && echo rwtest-ok && rm /etc/.rwtest
echo "===== A5 时钟"
date; cat /etc/config/system | grep -A2 ntp
echo "===== A6 reboots.log"
cat /etc/e87n/reboots.log 2>&1 | tail -20
echo "===== A7 watchdog"
for f in state identity timeout; do echo -n "$f="; cat /sys/class/watchdog/watchdog0/$f 2>&1; done
echo "===== B2 分区标签"
for d in /sys/class/block/mmcblk0p*; do echo "$(basename $d) $(grep PARTNAME $d/uevent)"; done
echo "===== B6 overlay 容量"
df -h /overlay
echo "===== C1 桥成员"
brctl show 2>/dev/null || ip link show master br-lan
echo "===== C2 地址"
ip -br addr show br-lan
echo "===== C6 ARP"
ip neigh
echo "===== D1/D2/D3 PHY"
dmesg | grep -E "mdio-bus:03|mdio-bus:0f" | head -10
dmesg | grep -E "mtk_soc_eth.*eth[01]" | head -10
echo "===== D4 协商"
for i in eth0 eth1; do echo -n "$i speed="; cat /sys/class/net/$i/speed 2>&1; echo -n "$i duplex="; cat /sys/class/net/$i/duplex 2>&1; echo -n "$i carrier="; cat /sys/class/net/$i/carrier 2>&1; done
echo "===== D5 错误计数"
ip -s link show eth0
echo "===== D7 温度"
for h in /sys/class/hwmon/hwmon*; do echo "$h $(cat $h/name 2>/dev/null) temp=$(cat $h/temp1_input 2>/dev/null)"; done
echo "===== F1 模块/开关"
lsmod | grep -E "nf_flow_table|nft_flow|mtk_ppe|mtk_eth"
uci show firewall | grep offload
echo "===== F2 flowtable"
nft list ruleset | sed -n '/flowtable ft {/,/}/p'
nft list ruleset | grep -n "flow add @ft" | head -5
echo "===== F3 PPE"
ls /sys/kernel/debug/ppe0/ 2>&1
head -c 400 /sys/kernel/debug/ppe0/entries 2>&1 | hexdump -C | head -20
echo "===== H1 IPv6"
ip -6 addr show br-lan
echo "===== K1 帧缓冲"
for f in virtual_size bits_per_pixel name; do echo -n "$f="; cat /sys/class/graphics/fb0/$f 2>&1; done
echo "===== K2 驱动日志"
dmesg | grep fb_nv3007
echo "===== K7 字体"
ls -l /usr/share/e87n/font.ttf 2>&1
echo "===== K8 主题"
e87n-theme list 2>&1
echo "===== M1 LED"
ls /sys/class/leds/
echo "===== N1 商店"
apk list -I 2>/dev/null | grep -E "luci-app-store|luci-app-quickstart|ota" ; ls -l /usr/lib/lua/luci/controller/store.lua 2>&1
echo "===== N2 向导"
ps | grep [q]uickstart
echo "===== N4 常用包"
apk list -I 2>/dev/null | grep -E "ddns|sqm|nlbwmon|ttyd|upnp|filebrowser"
echo "===== N6 自启"
ls /etc/rc.d/ | grep -E "S.*(fan|screen|e87n|istore|quickstart)"
echo "===== N7 进程唯一"
ps | grep -c "[e]87n-display"
echo "===== O1/O3/O5 metrics"
cat /var/run/e87n/metrics.json; echo
ubus call e87n status
echo "===== R1 root 密码"
grep "^root:" /etc/shadow | cut -d: -f2
echo "===== R2 authorized_keys"
cat /etc/dropbear/authorized_keys 2>&1
echo "===== R3 监听端口"
netstat -lnt 2>/dev/null || ss -lnt
echo "===== L 风扇配置"
uci show fan 2>&1
echo "--- calc for 50/51/52/55"
for t in 50 51 52 55; do echo -n "$t -> "; fan-control calc $t; done
echo "--- pwm1"
for p in /sys/class/hwmon/hwmon*/pwm1; do echo "$p=$(cat $p)"; done
echo "--- cooling"
cat /sys/class/thermal/cooling_device0/type; cat /sys/class/thermal/cooling_device0/cur_state
for z in /sys/class/thermal/thermal_zone*; do echo "$z $(cat $z/type) $(cat $z/temp)"; done
echo "--- fan-control 进程"
ps | grep [f]an-control
echo "--- fan-control --help"
fan-control 2>&1 | head -20
