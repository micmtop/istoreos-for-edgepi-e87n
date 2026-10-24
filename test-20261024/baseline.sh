mkdir -p /tmp/e87n-test
{
  echo "== 版本";        cat /etc/openwrt_release
  echo "== 内核";        uname -a
  echo "== 分区";        cat /proc/partitions
  echo "== p3 校验";     sha256sum /dev/mmcblk0p3
  echo "== p4 头部";     head -c 4 /dev/mmcblk0p4 | hexdump -v -e '1/1 "%02x"'; echo
  echo "== 温度";        cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null
  echo "== 风扇";        cat /sys/class/hwmon/hwmon*/pwm1 2>/dev/null
  echo "== 网络";        ip -br addr; ip route
  echo "== U 盘";        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo "== 挂载";        cat /proc/mounts
} 2>&1 | tee /tmp/e87n-test/baseline.txt
