echo "===== 重启后 A8"
uname -a; cut -d. -f1 /proc/uptime
echo "--- 配置持久"
uci get e87n-display.global.cycle_seconds
cat /root/persist-test
ls -l /etc/dropbear/authorized_keys
echo "--- host key"
dropbearkey -y -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null | head -2
echo "--- p3"
sha256sum /dev/mmcblk0p3
echo "--- reboots.log"
tail -8 /etc/e87n/reboots.log
echo "--- L7 重启后风扇"
cat /sys/class/hwmon/hwmon2/pwm1
cat /sys/class/hwmon/hwmon2/pwm1_enable
cat /sys/class/hwmon/hwmon0/temp1_input
logread | grep -iE "fan-control|fan" | tail -8
echo "--- 版本"
cat /etc/openwrt_release | grep -E "RELEASE|REVISION"
echo "--- A2 启动耗时"
dmesg | grep -m1 "procd: - init -"
echo "--- A7 watchdog"
cat /sys/class/watchdog/watchdog0/state
echo "--- overlay"
grep ' /overlay ' /proc/mounts
df -h /overlay
echo "--- 服务"
ps | grep -E "e87n-display|e87n-metrics|quickstart|fan-control" | grep -v grep
echo "--- N7"
ps | grep e87n-display | grep -v grep | wc -l
echo "--- 恢复测试配置"
uci set e87n-display.global.cycle_seconds=10; uci commit e87n-display
rm -f /root/persist-test
echo "cycle=$(uci get e87n-display.global.cycle_seconds) file=$(ls /root/persist-test 2>&1)"
