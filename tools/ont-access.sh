#!/bin/sh
# 光猫后台访问 + 监控零改动 的配置脚本
#
# 场景：光猫桥接，监控/NVR 的网关写死 192.168.1.1 且改不了。
#
# 做法：
#   LAN 让出 .1，改为 192.168.1.254
#   eth0（WAN）挂 192.168.1.2/32，只用来和光猫对话
#   加 /32 路由把 192.168.1.1 指到 eth0（比 LAN 的 /24 更具体）
#   br-lan 开 proxy_arp：局域网设备 ARP .1 时由路由器代答
#   ont 并入 wan 防火墙区域（masq），光猫回包才找得到路由器
#
# 用法：
#   ont-access.sh apply     应用配置
#   ont-access.sh check     只读检查（会真的去请求光猫）
#   ont-access.sh revert    撤销，把 LAN 还给 .1
#
# 参数（环境变量）：
#   ONT_IP=192.168.1.1  ONT_LOCAL=192.168.1.2  WAN_DEV=eth0  LAN_IP=192.168.1.254

set -e

ONT_IP=${ONT_IP:-192.168.1.1}
ONT_LOCAL=${ONT_LOCAL:-192.168.1.2}
WAN_DEV=${WAN_DEV:-eth0}
LAN_IP=${LAN_IP:-192.168.1.254}
LAN_NET=${LAN_IP%.*}

zone_idx() {
	# 找到 wan 区域的索引
	i=0
	while [ -n "$(uci -q get firewall.@zone[$i])" ]; do
		[ "$(uci -q get firewall.@zone[$i].name)" = "wan" ] && { echo $i; return 0; }
		i=$((i + 1))
	done
	return 1
}

do_apply() {
	echo "==> LAN 设为 $LAN_IP/24（把 $ONT_IP 让出来）"
	uci set network.lan.ipaddr="$LAN_IP"
	uci set network.lan.netmask=255.255.255.0
	uci commit network

	echo "==> WAN 口挂 $ONT_LOCAL/32"
	uci set network.ont=interface
	uci set network.ont.proto=static
	uci set network.ont.device="$WAN_DEV"
	uci set network.ont.ipaddr="$ONT_LOCAL"
	uci set network.ont.netmask=255.255.255.255
	uci set network.ont.defaultroute=0
	uci set network.ont.peerdns=0
	uci -q delete network.ont.gateway || true

	echo "==> 路由 $ONT_IP/32 -> $WAN_DEV"
	uci set network.ont_route=route
	uci set network.ont_route.interface=ont
	uci set network.ont_route.target="$ONT_IP"
	uci set network.ont_route.netmask=255.255.255.255
	uci commit network

	Z=$(zone_idx)
	echo "==> ont 并入 wan 区域（@zone[$Z]，masq）"
	uci -q del_list firewall.@zone[$Z].network=ont || true
	uci add_list firewall.@zone[$Z].network=ont
	uci commit firewall

	echo "==> br-lan 开 proxy_arp"
	grep -q "br-lan.proxy_arp" /etc/sysctl.conf || \
		echo "net.ipv4.conf.br-lan.proxy_arp=1" >> /etc/sysctl.conf
	sysctl -w net.ipv4.conf.br-lan.proxy_arp=1 >/dev/null

	/etc/init.d/network reload >/dev/null 2>&1 || true
	sleep 4
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
	sleep 2
	echo "== 应用完成"
	do_check
}

do_revert() {
	echo "==> 撤销：LAN 还给 $ONT_IP"
	uci -q delete network.ont || true
	uci -q delete network.ont_route || true
	Z=$(zone_idx) && uci -q del_list firewall.@zone[$Z].network=ont || true
	sed -i '/br-lan.proxy_arp/d' /etc/sysctl.conf 2>/dev/null || true
	sysctl -w net.ipv4.conf.br-lan.proxy_arp=0 >/dev/null 2>&1 || true
	uci set network.lan.ipaddr="$ONT_IP"
	uci commit network
	uci commit firewall
	/etc/init.d/network reload >/dev/null 2>&1 || true
	echo "==> 已撤销"
}

do_check() {
	echo
	echo "===== 检查 ====="
	echo "-- LAN   : $(ip -4 addr show br-lan 2>/dev/null | grep -o 'inet [0-9./]*')"
	echo "-- WAN 口 : $WAN_DEV carrier=$(cat /sys/class/net/$WAN_DEV/carrier 2>/dev/null)"
	echo "-- 到 $ONT_IP 的路由: $(ip route get $ONT_IP 2>/dev/null | head -1)"
	echo "-- proxy_arp: $(cat /proc/sys/net/ipv4/conf/br-lan/proxy_arp 2>/dev/null)"
	echo "-- WAN 口邻居表:"; ip neigh show dev "$WAN_DEV" 2>/dev/null | head -3

	printf -- "-- 路由器请求光猫后台: "
	code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$ONT_IP/" 2>/dev/null)
	case "$code" in
		2*|3*) echo "成功（HTTP $code）" ;;
		*)     echo "失败（HTTP ${code:-无响应}）——检查 $WAN_DEV 是否插线、光猫是否在 $ONT_IP" ;;
	esac

	echo "-- 局域网侧 NAT 会话（最近 3 条）:"
	cat /proc/net/nf_conntrack 2>/dev/null | grep "$ONT_IP" | tail -3 || echo "   （暂无）"
	echo "================"
}

case "$1" in
	apply)  do_apply ;;
	revert) do_revert ;;
	check)  do_check ;;
	*) echo "用法: $0 apply|check|revert"; exit 2 ;;
esac
