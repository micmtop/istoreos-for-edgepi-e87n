echo "===== nc 用法"
nc --help 2>&1 | head -20
echo "===== 主题安装目录"
ls -la /etc/e87n-display/themes/ 2>&1
echo "===== e87n-theme install/remove 源码"
sed -n '60,200p' /usr/sbin/e87n-theme
echo "===== init.d/e87n-display"
cat /etc/init.d/e87n-display
echo "===== 修复 L9 后风扇恢复"
/etc/init.d/fan restart >/dev/null 2>&1; sleep 7
echo "temp=$(cat /sys/class/hwmon/hwmon0/temp1_input) pwm=$(cat /sys/class/hwmon/hwmon2/pwm1) calc=$(fan-control calc $(( $(cat /sys/class/hwmon/hwmon0/temp1_input)/1000 )))"
echo "===== 温度采样"
for i in 1 2 3; do cat /sys/class/hwmon/hwmon0/temp1_input; sleep 2; done
echo "===== 磁盘/内存"
free -m; df -h /overlay /tmp
echo "===== 运行时长"
cut -d. -f1 /proc/uptime
