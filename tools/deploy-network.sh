#!/bin/sh
# E87N 上网部署脚本（可重复执行）
#
# 做四件事：
#   1. LAN 改成给监控用的网段（默认 192.168.1.254/24）
#   2. WAN 用 PPPoE 拨号（可带 VLAN tag）
#   3. WAN 口再挂一个 /32 地址，专门访问光猫后台（光猫默认 192.168.1.1）
#   4. 打开 proxy_arp，让局域网电脑也能直接开光猫后台
#
# 用法：
#   deploy-network.sh --pppoe-user 账号 --pppoe-pass 密码
#   deploy-network.sh --lan 192.168.1.254/24 --ont 192.168.1.1
#   deploy-network.sh --vlan 41 --pppoe-user ...     # 上网要打 VLAN tag 时
#   deploy-network.sh --check                        # 只看状态，不改
#
# 注意：账户密码不写进仓库，用参数传。跑完会把凭据存在设备 /etc/config/network 里。

set -e

LAN_CIDR="192.168.1.254/24"
ONT_IP="192.168.1.1"
ONT_LOCAL="192.168.1.2"
PPPOE_USER=""
PPPOE_PASS=""
VLAN=""
CHECK=0

while [ $# -gt 0 ]; do
	case "$1" in
		--lan)        LAN_CIDR="$2"; shift 2 ;;
		--ont)        ONT_IP="$2"; shift 2 ;;
		--ont-local)  ONT_LOCAL="$2"; shift 2 ;;
		--pppoe-user) PPPOE_USER="$2"; shift 2 ;;
		--pppoe-pass) PPPOE_PASS="$2"; shift 2 ;;
		--vlan)       VLAN="$2"; shift 2 ;;
		--check)      CHECK=1; shift ;;
		-h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
		*) echo "未知参数 $1"; exit 2 ;;
	esac
done

LAN_IP=${LAN_CIDR%/*}
LAN_MASK=${LAN_CIDR#*/}
case "$LAN_MASK" in
	24) LAN_MASK="255.255.255.0" ;;
	16) LAN_MASK="255.255.0.0" ;;
	8)  LAN_MASK="255.0.0.0" ;;
esac

WAN_DEV="eth1"
[ -n "$VLAN" ] && WAN_DEV="eth1.$VLAN"

if [ "$CHECK" = "1" ]; then
	echo "== LAN";        uci -q show network.lan | grep -E "ipaddr|netmask"
	echo "== WAN";        uci -q show network.wan | grep -E "device|proto|username"
	echo "== 光猫接口";   uci -q show network.ont 2>/dev/null || echo "（未配置）"
	echo "== 路由";       ip route | grep -E "default|$ONT_IP"
	echo "== proxy_arp";  cat /proc/sys/net/ipv4/conf/br-lan/proxy_arp 2>/dev/null
	echo "== 连通性"
	ping -c2 -W2 "$ONT_IP" >/dev/null 2>&1 && echo "光猫 $ONT_IP 可达" || echo "光猫 $ONT_IP 不可达"
	ip route | grep -q "^default" && echo "默认路由存在" || echo "没有默认路由（拨号还没成功）"
	exit 0
fi

echo "==> 1/5 LAN 设为 $LAN_IP/$LAN_MASK"
uci set network.lan.proto='static'
uci set network.lan.device='br-lan'
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask="$LAN_MASK"
uci set network.lan.defaultroute='0'
uci -q delete network.lan.gateway || true

echo "==> 2/5 WAN：PPPoE（设备 $WAN_DEV）"
uci set network.wan='interface'
uci set network.wan.device="$WAN_DEV"
uci set network.wan.proto='pppoe'
[ -n "$PPPOE_USER" ] && uci set network.wan.username="$PPPOE_USER"
[ -n "$PPPOE_PASS" ] && uci set network.wan.password="$PPPOE_PASS"

# IPv6：沿用原来的 dhcpv6 客户端
uci set network.wan6='interface'
uci set network.wan6.device='@wan'
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci set network.wan6.norelease='1'

echo "==> 3/5 光猫管理口：$ONT_LOCAL/32，路由 $ONT_IP 走 $WAN_DEV"
uci set network.ont='interface'
uci set network.ont.proto='static'
uci set network.ont.device="$WAN_DEV"
uci set network.ont.ipaddr="$ONT_LOCAL"
uci set network.ont.netmask='255.255.255.255'
uci set network.ont.defaultroute='0'
uci set network.ont.peerdns='0'
uci -q delete network.ont.gateway || true

# 清掉旧的同名路由再建，保证可重复执行
uci -q delete network.ont_route 2>/dev/null || true
uci set network.ont_route='route'
uci set network.ont_route.interface='ont'
uci set network.ont_route.target="$ONT_IP"
uci set network.ont_route.netmask='255.255.255.255'
uci commit network

echo "==> 4/5 防火墙：ont 并入 wan 区域（自动 SNAT）"
uci -q del_list firewall.@zone[1].network='ont' || true
uci add_list firewall.@zone[1].network='ont'
uci commit firewall

echo "==> 5/5 proxy_arp：让局域网电脑能直接开光猫后台"
grep -q "br-lan.proxy_arp" /etc/sysctl.conf 2>/dev/null || \
	echo 'net.ipv4.conf.br-lan.proxy_arp=1' >> /etc/sysctl.conf
sysctl -w net.ipv4.conf.br-lan.proxy_arp=1 >/dev/null

echo "==> 生效"
/etc/init.d/network reload
sleep 3
/etc/init.d/firewall reload

echo
echo "==> 结果"
ip -4 addr show br-lan | grep -E "inet " || true
ip route | grep -E "^default|$ONT_IP" || echo "（暂无默认路由，等拨号）"
echo "proxy_arp=$(cat /proc/sys/net/ipv4/conf/br-lan/proxy_arp)"
echo
echo "下一步：把监控和电脑的网关指向 $LAN_IP，然后拔插一次 WAN 网线触发拨号。"
echo "检查拨号：ifup wan && logread | tail -20"
