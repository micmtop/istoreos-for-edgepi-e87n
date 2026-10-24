echo "== ppe 模块/目录"
ls -d /sys/module/mtk_ppe /sys/module/mtk_eth_soc /sys/module/nf_flow_table 2>&1
ls /sys/module/mtk_ppe/parameters 2>&1
for f in /sys/module/mtk_ppe/parameters/*; do [ -f "$f" ] && echo "$(basename $f)=$(cat $f)"; done 2>/dev/null
echo "== debugfs"
find /sys/kernel/debug -maxdepth 1 -name 'ppe*' 2>/dev/null
echo "== bind 原始"
wc -c /sys/kernel/debug/ppe0/bind
hexdump -C /sys/kernel/debug/ppe0/bind 2>/dev/null | head -6
echo "== dmesg ppe/hnat"
dmesg | grep -iE 'ppe|hnat|flowtable|flow offload' | head -20
echo "== 内核配置"
zcat /proc/config.gz 2>/dev/null | grep -iE 'MTK_PPE|HNAT|NETFILTER.*FLOW' | head -20
echo "== 模块信息"
modinfo mtk_ppe 2>&1 | head -8
echo "== 已加载模块里与 ppe 相关"
lsmod | grep -i ppe
echo "== eth0 features"
cat /sys/class/net/eth0/features 2>/dev/null
