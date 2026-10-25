#!/bin/sh
# IPTV 透传（VLAN 型）：把 WAN 侧某 VLAN 桥到 LAN 侧，机顶盒直接拿运营商的地址
#
# 用法：
#   iptv-passthrough.sh apply 45        # 运营商 IPTV VLAN ID
#   iptv-passthrough.sh check
#   iptv-passthrough.sh revert
#
# 变量：
#   WAN_DEV=eth0   LAN_DEV=eth1   （本机交换过网口身份）
#
# 交换机侧配合：
#   上联口（接路由器 LAN）：VLAN 1 untagged（PVID 1）+ VLAN 45 tagged
#   机顶盒口：VLAN 45 untagged（PVID 45），不要加入 VLAN 1
#   其它口：VLAN 1 untagged，不开 IGMP snooping 的话组播会泛洪

set -e

WAN_DEV=${WAN_DEV:-eth0}
LAN_DEV=${LAN_DEV:-eth1}
VID="$2"
BR=br-iptv

do_apply() {
	[ -n "$VID" ] || { echo "用法: $0 apply <vlan-id>"; exit 2; }
	echo "==> IPTV VLAN $VID：$WAN_DEV.$VID <-> $LAN_DEV.$VID"
	uci set network.iptv_wan=device
	uci set network.iptv_wan.name="$WAN_DEV.$VID"
	uci set network.iptv_wan.type=8021q
	uci set network.iptv_wan.ifname="$WAN_DEV"
	uci set network.iptv_wan.vid="$VID"

	uci set network.iptv_lan=device
	uci set network.iptv_lan.name="$LAN_DEV.$VID"
	uci set network.iptv_lan.type=8021q
	uci set network.iptv_lan.ifname="$LAN_DEV"
	uci set network.iptv_lan.vid="$VID"

	uci set network.iptvbr=device
	uci set network.iptvbr.name="$BR"
	uci set network.iptvbr.type=bridge
	uci delete network.iptvbr.ports 2>/dev/null || true
	uci add_list network.iptvbr.ports="$WAN_DEV.$VID"
	uci add_list network.iptvbr.ports="$LAN_DEV.$VID"

	# 纯二层桥，不配 IP、不进防火墙区域
	uci set network.iptv=interface
	uci set network.iptv.proto=none
	uci set network.iptv.device="$BR"
	uci commit network
	/etc/init.d/network reload >/dev/null 2>&1 || true
	sleep 3
	do_check
}

do_check() {
	echo
	echo "===== IPTV 检查 ====="
	echo "-- VLAN 子接口:"
	ip -d link show 2>/dev/null | grep -A1 -E "$WAN_DEV\.|$LAN_DEV\." | grep -E "^[0-9]+:|vlan" | head -6
	echo "-- 桥:"
	brctl show "$BR" 2>/dev/null || echo "   $BR 不存在"
	echo "-- 桥上流量（跑一会儿再看）:"
	[ -d "/sys/class/net/$BR/statistics" ] && {
		echo "   rx=$(cat /sys/class/net/$BR/statistics/rx_packets) tx=$(cat /sys/class/net/$BR/statistics/tx_packets)"; }
	echo "===================="
}

do_revert() {
	echo "==> 撤销 IPTV 透传"
	uci -q delete network.iptv_wan || true
	uci -q delete network.iptv_lan || true
	uci -q delete network.iptvbr || true
	uci -q delete network.iptv || true
	uci commit network
	/etc/init.d/network reload >/dev/null 2>&1 || true
	echo "==> 已撤销"
}

case "$1" in
	apply)  do_apply ;;
	check)  do_check ;;
	revert) do_revert ;;
	*) echo "用法: $0 apply <vlan-id> | check | revert"; exit 2 ;;
esac
