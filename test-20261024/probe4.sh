echo "===== vfat/exfat 模块"
uname -r
ls /lib/modules/$(uname -r)/ | grep -iE 'vfat|^fat|exfat|nls' 2>&1
lsmod | grep -iE 'vfat|fat|exfat|nls' 2>&1
echo "--- modules.dep"
grep -E "vfat|exfat|nls_cp437|nls_utf8" /lib/modules/$(uname -r)/modules.dep 2>&1 | head
echo "===== busybox mount 支持"
cat /proc/filesystems | grep -iE 'vfat|fat|exfat'
echo "===== dropbear 启动参数"
grep -n "dropbear" /etc/init.d/dropbear | head -20
cat /etc/config/dropbear
echo "===== 空密码风险确认"
grep -n "PasswordAuth\|RootPasswordAuth" /etc/config/dropbear
echo "===== e87n-metrics 间隔"
grep -nE "sleep|interval|while" /usr/sbin/e87n-metrics | head -20
echo "===== backlight 节点"
ls /sys/class/backlight/ 2>&1
for b in /sys/class/backlight/*; do echo "$b brightness=$(cat $b/brightness 2>&1) max=$(cat $b/max_brightness 2>&1)"; done
echo -n "gpio524 direction="; cat /sys/class/gpio/gpio524/direction 2>&1
echo -n "gpio524 active_low="; cat /sys/class/gpio/gpio524/active_low 2>&1
echo "===== 屏幕服务进程"
ps | grep -E "[e]87n-display|[s]creen"
echo "===== 主题目录"
ls -la /usr/share/e87n/themes/ 2>&1; ls -la /usr/share/e87n/ 2>&1 | head -20
echo "===== metrics 全量配置"
uci show e87n-metrics 2>&1
