echo "===== I1 USB dmesg"
dmesg | grep -i usb | tail -20
echo "===== I2 blkid / lsblk -f"
blkid; lsblk -f
echo "===== I 写扇区基线 /sys/block/sda/stat"
cat /sys/block/sda/stat
echo "===== I3 只读挂载"
mkdir -p /mnt/usbtest
mount -o ro /dev/sda1 /mnt/usbtest && echo mount-ok || echo mount-FAIL
grep usbtest /proc/mounts
echo "===== I4 目录"
ls -la /mnt/usbtest | head -15
du -sh /mnt/usbtest 2>&1
echo "===== I5 顺序读 256MB"
time dd if=/dev/sda of=/dev/null bs=1M count=256 2>&1 | tail -4
echo "===== I6 随机读"
dd if=/dev/sda of=/dev/null bs=4k count=2000 skip=1000 2>&1 | tail -3
echo "===== I7 大文件（>50M 前 3 个）"
find /mnt/usbtest -type f -size +50M 2>/dev/null | head -3
echo "===== I8 只读验证"
touch /mnt/usbtest/x 2>&1
echo "===== I 写扇区结束"
cat /sys/block/sda/stat
echo "===== I12 UAS"
dmesg | grep -i uas
echo "===== I11 over-current"
dmesg | grep -iE "over-current|overcurrent|reset (high|low).*speed USB" | tail -5
echo "===== I13 卸载"
umount /mnt/usbtest && echo umount-ok
grep usbtest /proc/mounts || echo no-residual
echo "===== K 显示配置"
cat /etc/config/e87n-display
echo "===== screen-ctl"
screen-ctl 2>&1 | head
echo "===== e87n-theme"
e87n-theme 2>&1 | head
echo "===== K3 背光"
echo -n "gpio524 before="; cat /sys/class/gpio/gpio524/value 2>&1
screen-ctl off; sleep 1; echo -n "after off: "; screen-ctl status; echo -n "gpio524="; cat /sys/class/gpio/gpio524/value 2>&1
screen-ctl on; sleep 1; echo -n "after on: "; screen-ctl status; echo -n "gpio524="; cat /sys/class/gpio/gpio524/value 2>&1
echo "===== K6 抓帧"
screen-ctl snapshot /tmp/k6.png 2>&1
ls -l /tmp/k6.png
echo "===== M5 LED 手动"
echo 1 > /sys/class/leds/green:status/brightness; echo "b1=$(cat /sys/class/leds/green:status/brightness)"
echo 0 > /sys/class/leds/green:status/brightness; echo "b0=$(cat /sys/class/leds/green:status/brightness)"
echo "===== O2 刷新频率 1s x 6"
i=0; while [ $i -lt 6 ]; do sed -n 's/.*"ts":\([0-9]*\).*/\1/p' /var/run/e87n/metrics.json; sleep 1; i=$((i+1)); done
echo "===== R3 nft 输入策略"
nft list ruleset | sed -n '1,40p'
echo "===== R4/R5 服务配置"
uci show filebrowser 2>&1 | head -20
uci show upnpd 2>&1 | head -20
uci show ttyd 2>&1 | head -15
uci show ddns 2>&1 | head -20
uci show dropbear 2>&1
echo "===== 外网连通性"
ping -c 2 -W 2 223.5.5.5 2>&1 | tail -3
nslookup baidu.com 127.0.0.1 2>&1 | head -8
