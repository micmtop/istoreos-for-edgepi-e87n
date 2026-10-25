# 固件里的网络默认值

面向所有人的修正放在 `package/e87n-tools/files/etc/uci-defaults/97-e87n-net-defaults`，
只在「从没应用过」的机器上跑一次（标记 `/etc/e87n/.net-defaults-applied`）。

放进固件的只有对任何用户都成立的三条：

| 设置 | 值 | 原因 |
|---|---|---|
| `dhcp.@dnsmasq[0].filter_aaaa` | `0` | iStoreOS 默认 `1`，会把所有 AAAA 记录丢掉，表现为「没有 IPv6」、IPv6 测速站全部 `no such host` |
| `dhcp.lan.ra_flags` | 删除 | 默认带 `managed-config`，客户端会等 DHCPv6 而不做 SLAAC，Windows 只拿到 ULA |
| `network.lan.ip6assign` | `64` | 从运营商委派的前缀里取一个 /64 给 LAN |

## 故意不放进固件的

| 项 | 原因 |
|---|---|
| `wan6.reqprefix` | 各运营商委派长度不同（电信常见 /60，也有 /56、/64），写死会限制别人 |
| `upnpd.config.enabled` | UPnP 等于允许内网程序开洞，安全上应该默认关闭，由用户在 LuCI 里自己开 |
| `fullcone` | iStoreOS 自带 `99_fullcone_nat_fw4` 已设为 2，不需要重复设 |
| LAN 网段 | 各家不同；固件保持 iStoreOS 默认，避免和光猫 `192.168.1.1` 撞车 |
| 宽带账号 | 绝不入仓、绝不入镜像 |

## 用户自己要做的事

**开 UPnP**（默认关闭）：

```sh
uci set upnpd.config.enabled=1
uci set upnpd.config.secure_mode=1
uci commit upnpd
/etc/init.d/miniupnpd enable && /etc/init.d/miniupnpd restart
```

**IPv6 前缀委派长度**如遇到问题（`wan6` 反复重启），可以试显式指定：

```sh
uci set network.wan6.reqprefix=60     # 或 56 / 64，按运营商实际情况
uci commit network && ifup wan6
```

判断方法：`ifstatus wan_6 | grep -A4 ipv6-prefix` 看 `mask` 实际是多少。
