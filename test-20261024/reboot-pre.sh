echo "===== 重启前基线"
sha256sum /dev/mmcblk0p3
dropbearkey -y -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null | head -2
ls -l /etc/dropbear/authorized_keys
uci set e87n-display.global.cycle_seconds=11; uci commit e87n-display
uci get e87n-display.global.cycle_seconds
echo "persist-test-$(date +%s)" > /root/persist-test
sync
cat /root/persist-test
echo "--- reboots.log 尾部"
tail -6 /etc/e87n/reboots.log
echo "--- 当前 pwm/temp"
cat /sys/class/hwmon/hwmon2/pwm1; cat /sys/class/hwmon/hwmon0/temp1_input
echo "===== 即将重启"
sync
reboot
