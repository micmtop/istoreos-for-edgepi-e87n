#!/bin/sh
# E87N 基础上网配置：LAN + PPPoE 拨号 + IPv6，仅此三件。
#
# 用法：
#   deploy-basic.sh --pppoe-user 账号 --pppoe-pass 密码
#   deploy-basic.sh --lan 192.168.1.254/24 --pppoe-user ... --pppoe-pass ...
#   deploy-basic.sh --check
#
# 默认 LAN 是 192.168.1.254/24（配合家里监控固定在 192.168.1.x；
# 路由器不能取 .1，因为 .1 通常被光猫占用）。
# 账号密码不进仓库，用参数传。

set -e

LAN_CIDR="192.168.1.254/24"
PPPOE_USER=""
PPPOE_PASS=""
VLAN=""
CHECK=0

while [ $# -gt 0 ]; do
	case "$1" in
		--lan)        LAN_CIDR="$2"; shift 2 ;;
		--pppoe-user) PPPOE_USER="$2"; shift 2 ;;
		--pppoe-pass) PPPOE_PASS="$2"; shift 2 ;;
		--vlan)       VLAN="$2"; shift 2 ;;
		--check)      CHECK=1; shift ;;
		-h|--help)    sed -n '2,14p' "$0"; exit 0 ;;
		*) echo "未知参数 $1"; exit 2 ;;
	esac
done

LAN_IP=${LAN_CIDR%/*}
LAN_PREFIX=${LAN_CIDR#*/}
case "$LAN_PREFIX" in
	24) LAN_MASK="255.255.255.0" ;;
	16) LAN_MASK="255.255.0.0" ;;
	8)  LAN_MASK="255.0.0.0" ;;
	*)  echo "只支持 /8 /16 /24"; exit 2 ;;
esac

WAN_DEV="eth1"
[ -n "$VLAN" ] && WAN_DEV="eth1.$VLAN"

if [ "$CHECK" = "1" ]; then
	echo "LAN   : $(uci -q get network.lan.ipaddr)/$(uci -q get network.lan.netmask)"
	echo "WAN   : $(uci -q get network.wan.device) $(uci -q get network.wan.proto) user=$(uci -q get network.wan.username)"
	echo "IPv6  : $(uci -q get network.wan6.proto)"
	echo "地址  : $(ip -4 addr show br-lan | grep -o 'inet [0-9./]*')"
	echo "路由  : $(ip route | grep '^default' || echo '无默认路由')"
	echo "拨号  : $(ifstatus wan 2>/dev/null | grep -o '\"up\": *[a-z]*' | head -1)"
	exit 0
fi

echo "==> LAN $LAN_IP/$LAN_MASK"
uci set network.lan='interface'
uci set network.lan.proto='static'
uci set network.lan.device='br-lan'
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask="$LAN_MASK"
uci set network.lan.ip6assign='64'
uci set network.lan.defaultroute='0'
uci -q delete network.lan.gateway || true

echo "==> WAN PPPoE（$WAN_DEV）"
uci set network.wan='interface'
uci set network.wan.device="$WAN_DEV"
uci set network.wan.proto='pppoe'
[ -n "$PPPOE_USER" ] && uci set network.wan.username="$PPPOE_USER"
[ -n "$PPPOE_PASS" ] && uci set network.wan.password="$PPPOE_PASS"
uci set network.wan.peerdns='1'
uci set network.wan.defaultroute='1'

echo "==> IPv6 客户端"
uci set network.wan6='interface'
uci set network.wan6.device='@wan'
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci set network.wan6.norelease='1'

echo "==> 清理之前多余的光猫访问配置"
uci -q delete network.ont || true
uci -q delete network.ont_route || true
uci -q del_list firewall.@zone[1].network='ont' || true
sed -i '/br-lan.proxy_arp/d' /etc/sysctl.conf 2>/dev/null || true
sysctl -w net.ipv4.conf.br-lan.proxy_arp=0 >/dev/null 2>&1 || true
uci commit network
uci commit firewall

echo "==> 生效"
/etc/init.d/network reload || true
sleep 3

echo
echo "LAN   : $(ip -4 addr show br-lan | grep -o 'inet [0-9./]*')"
echo "路由  : $(ip route | grep '^default' || echo '无（WAN 未接或未拨号）')"
echo
echo "接上光猫后触发拨号：ifup wan；看日志：logread -f | grep pppd"
echo "设备管理和 DHCP 都在 $LAN_IP 这个地址上。"
