echo "===== screen-ctl 源码"
cat /usr/sbin/screen-ctl
echo "===== e87n-theme 类型与源码头"
file /usr/sbin/e87n-theme 2>&1; head -60 /usr/sbin/e87n-theme 2>&1
echo "===== 主题 aurora 内容"
ls -la /usr/share/e87n/themes/aurora/
echo "===== L3 手动 128"
uci set fan.global.mode=manual; uci set fan.global.manual_pwm=128; uci commit fan
sleep 8; echo "pwm=$(cat /sys/class/hwmon/hwmon2/pwm1)"
echo "===== L4 关闭"
uci set fan.global.mode=off; uci commit fan
sleep 8; echo "pwm=$(cat /sys/class/hwmon/hwmon2/pwm1) enable=$(cat /sys/class/hwmon/hwmon2/pwm1_enable)"
echo "===== L5 曲线热更新（调高到 90%）"
uci set fan.global.mode=auto; uci commit fan
uci -q delete fan.global.curve
uci add_list fan.global.curve='35:0'
uci add_list fan.global.curve='45:90'
uci add_list fan.global.curve='55:90'
uci add_list fan.global.curve='65:90'
uci add_list fan.global.curve='75:100'
uci commit fan
sleep 10
t=$(cat /sys/class/hwmon/hwmon0/temp1_input); tc=$((t/1000))
echo "temp=$tc calc=$(fan-control calc $tc) pwm=$(cat /sys/class/hwmon/hwmon2/pwm1)"
echo "===== L9 外部改写告警"
logread -c 2>/dev/null | tail -2
echo 77 > /sys/class/hwmon/hwmon2/pwm1
sleep 7
echo "pwm-after-external=$(cat /sys/class/hwmon/hwmon2/pwm1)"
logread | grep -i "fan-control" | tail -6
echo "===== L5 恢复原曲线 + auto"
uci -q delete fan.global.curve
uci add_list fan.global.curve='35:0'
uci add_list fan.global.curve='45:35'
uci add_list fan.global.curve='55:55'
uci add_list fan.global.curve='65:78'
uci add_list fan.global.curve='75:100'
uci set fan.global.mode=auto
uci commit fan
sleep 10
echo "curve=$(uci -q get fan.global.curve)"
t=$(cat /sys/class/hwmon/hwmon0/temp1_input); tc=$((t/1000))
echo "temp=$tc calc=$(fan-control calc $tc) pwm=$(cat /sys/class/hwmon/hwmon2/pwm1) mode=$(uci get fan.global.mode)"
echo "===== K5 轮播"
uci set e87n-display.global.page=cycle; uci commit e87n-display
/etc/init.d/e87n-display restart >/dev/null 2>&1
sleep 2; screen-ctl snapshot /tmp/k5-a.raw
sleep 12; screen-ctl snapshot /tmp/k5-b.raw
sleep 12; screen-ctl snapshot /tmp/k5-c.raw
ls -l /tmp/k5-*.raw
md5sum /tmp/k5-*.raw
uci set e87n-display.global.page=1; uci commit e87n-display
/etc/init.d/e87n-display restart >/dev/null 2>&1
echo "===== 显示进程数"
ps | grep "e87n-display" | grep -v grep | wc -l
echo "===== K12 连续切页 20 次（缩短版）"
i=0; while [ $i -lt 20 ]; do p=$((i%4+1)); uci set e87n-display.global.page=$p; uci commit e87n-display; /etc/init.d/e87n-display restart >/dev/null 2>&1; i=$((i+1)); done
echo "after-20: $(ps | grep 'e87n-display' | grep -v grep | wc -l) 进程"
uci set e87n-display.global.page=1; uci commit e87n-display; /etc/init.d/e87n-display restart >/dev/null 2>&1
echo "===== Q7 CPU 满载 60s"
dd if=/dev/zero of=/dev/null bs=1M & dd if=/dev/zero of=/dev/null bs=1M & dd if=/dev/zero of=/dev/null bs=1M & dd if=/dev/zero of=/dev/null bs=1M &
sleep 60
killall dd
echo "load=$(cut -d' ' -f1-3 /proc/loadavg) temp=$(cat /sys/class/hwmon/hwmon0/temp1_input) pwm=$(cat /sys/class/hwmon/hwmon2/pwm1)"
