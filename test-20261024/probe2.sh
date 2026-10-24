echo "===== R1 shadow 原文"
grep "^root:" /etc/shadow
echo "===== fan-control 脚本"
cat /usr/sbin/fan-control
echo "===== init.d/fan"
cat /etc/init.d/fan
echo "===== thermal trip / cdev"
for f in /sys/class/thermal/thermal_zone0/trip_point_*_temp /sys/class/thermal/thermal_zone0/trip_point_*_type /sys/class/thermal/thermal_zone0/cdev*_cur_state /sys/class/thermal/thermal_zone0/cdev*_type; do echo -n "$f="; cat $f 2>&1; done
echo "===== logread fan"
logread | grep -iE "fan|thermal" | tail -30
echo "===== L1 kernel 改写测试（停 fan-control，写 200，10s 后读）"
/etc/init.d/fan stop >/dev/null 2>&1
sleep 1
echo 200 > /sys/class/hwmon/hwmon2/pwm1
echo "t0=$(cat /sys/class/hwmon/hwmon2/pwm1)"
sleep 10
echo "t10=$(cat /sys/class/hwmon/hwmon2/pwm1)"
/etc/init.d/fan start >/dev/null 2>&1
sleep 6
echo "after-start=$(cat /sys/class/hwmon/hwmon2/pwm1)"
echo "===== B5 eMMC 顺序读"
time dd if=/dev/mmcblk0p5 of=/dev/null bs=1M count=256 2>&1 | tail -5
echo "===== B7 200 次 4KB 写"
time sh -c 'i=0; while [ $i -lt 200 ]; do dd if=/dev/zero of=/root/t$i bs=4k count=1 2>/dev/null || echo "FAIL $i"; i=$((i+1)); done; rm -f /root/t*'
echo "===== O2 刷新频率"
a=$(sed -n 's/.*"ts":\([0-9]*\).*/\1/p' /var/run/e87n/metrics.json); sleep 3; b=$(sed -n 's/.*"ts":\([0-9]*\).*/\1/p' /var/run/e87n/metrics.json); echo "ts0=$a ts3=$b diff=$((b-a))"
echo "===== O4 200 次读取合法性"
bad=0; i=0; while [ $i -lt 200 ]; do s=$(cat /var/run/e87n/metrics.json); case "$s" in \{*\"temp_c\"*\"lan_ip\"*\}) : ;; *) bad=$((bad+1));; esac; i=$((i+1)); done; echo "bad=$bad"
echo "===== O6 异常处理"
killall e87n-metrics 2>&1; sleep 2; echo "alive=$(pidof e87n-metrics)"; ls -l /var/run/e87n/metrics.json; cat /var/run/e87n/metrics.json | head -c 80; echo
/etc/init.d/e87n-metrics start 2>&1; sleep 3; echo "alive-after=$(pidof e87n-metrics)"; stat -c %Y /var/run/e87n/metrics.json
echo "===== D5 重复计数"
ip -s link show eth0 | tail -6
echo "===== C 侧 MTU 路由器"
ip link show br-lan | head -1
