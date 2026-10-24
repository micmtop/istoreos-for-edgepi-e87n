# E87N 全量测试清单

给执行测试的 agent 用。覆盖硬件、系统、网络、卸载、USB、屏幕、风扇、升级与稳定性。
每条用例都给出命令、期望结果和证据要求。

设备信息：iStoreOS 25.12.5，内核 6.12.94，MT7987A。
访问方式：`ssh -o StrictHostKeyChecking=no -i <key> root@192.168.100.1`。
设备上是 busybox：没有 `od`、`pkill`、`timeout`，分别用 `hexdump`、`killall`、后台任务替代。
固件里也没有 `ethtool`、`iperf3`、`nstat`，相关用例给出了替代做法（sysfs、`nc`、`ip -s`）。

## 硬性约束

以下动作**一律禁止**，违反后果不可逆：

| 禁止 | 原因 |
|---|---|
| 写 `/dev/mmcblk0p3` | 里面是 FIP、BL31，写坏只能串口 RAM boot 救 |
| 对 U 盘做 `mkfs`、`dd of=`、`parted`、`fdisk`、`wipefs`、`fsck` 不带 `-n` | 用户要求只读测试，不许写、不许格式化 |
| 以读写方式挂载 U 盘 | 同上。挂载必须 `-o ro`，并在 `/proc/mounts` 里确认是 `ro` |
| 在 U 盘上创建、删除、改时间戳 | 同上 |
| `sysupgrade -F` 刷非本机镜像 | 会写坏 p4、p5 |
| 测试中途拔 eMMC 电源或按 reset | 可能丢配置或损坏 overlay |

只读挂载不到位时，先 `umount` 再 `mount -o ro`；实在不行跳过该用例并标记 `SKIPPED`，不要改成读写。

## 测试前准备

按顺序做完，把结果写进报告开头。

```sh
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
```

`sha256sum /dev/mmcblk0p3` 的完整值抄进报告。全部测试结束后再算一次，两次必须一致。

## A 启动与系统基础

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| A1 | 版本与机型 | `cat /etc/openwrt_release; cat /proc/device-tree/model` | 版本 25.12.5，机型 `EdgePi E87N` |
| A2 | 启动耗时 | `dmesg \| grep -m1 "procd: - init -"`，再看 uptime | 到 init 不超过 12 s |
| A3 | 启动报错 | `dmesg \| grep -iE "error\|failed\|call trace\|warn"` | 无 panic、无 Call trace；已知的 `WARN` 需在报告里列原文 |
| A4 | overlay | `df -h /overlay; touch /etc/.rwtest && rm /etc/.rwtest` | 可写，容量正常 |
| A5 | 时钟 | `date` | 有外网时应与真实时间一致；无外网时允许偏差，记录数值 |
| A6 | 重启记账 | `cat /etc/e87n/reboots.log` | 有本次启动记录；异常重启项应有说明 |
| A7 | 看门狗 | `cat /sys/class/watchdog/watchdog0/state`、`identity`、`timeout` | `active`、`mtk-wdt`、30 左右 |
| A8 | 关机重启 | `reboot`，等 60 s 后连回 | 能正常启动，配置保留，`reboots.log` 无异常项 |

A8 算一次清空测试：重启后确认 `/etc/config` 未被重置、`/etc/dropbear/authorized_keys` 还在。

## B 存储与分区

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| B1 | 分区齐全 | `cat /proc/partitions` | p1 512K、p2 4096K、p3 2048K、p4 32768K、p5 约 7.5G，另有 mmcblk0boot0、boot1 |
| B2 | 分区标签 | `for d in /sys/class/block/mmcblk0p*; do echo "$(basename $d) $(grep PARTNAME $d/uevent)"; done` | 依次是 u-boot-env、factory、fip、kernel、rootfs |
| B3 | p3 未变 | `sha256sum /dev/mmcblk0p3` | 与 baseline 完全一致 |
| B4 | p4 是 FIT | `head -c 4 /dev/mmcblk0p4 \| hexdump -v -e '1/1 "%02x"'` | `d00dfeed` |
| B5 | eMMC 读写 | `dd if=/dev/mmcblk0p5 of=/dev/null bs=1M count=256` | 无 I/O error，耗时可记录 |
| B6 | overlay 剩余 | `df -h /overlay` | 可用空间大于 5 GB |
| B7 | 反复写小文件 | 循环 200 次写 4 KB 文件到 `/root` 再删 | 全部成功，无延迟突增 |

## C 网络：LAN 侧

| ID | 用例 | 命令/操作 | 通过标准 |
|---|---|---|---|
| C1 | 桥与端口 | `brctl show`（或 `ip link show master br-lan`） | eth0 在 br-lan 内 |
| C2 | 地址 | `ip -br addr show br-lan` | 有 IPv4 地址，默认 192.168.100.1/24 |
| C3 | DHCP 服务 | 客户端重新获取地址 | 能拿到 192.168.100.0/24 的地址、网关、DNS |
| C4 | 静态地址 | 客户端改成静态同网段地址 | 能 ping 通路由器，能上网（有外网时） |
| C5 | MTU | PC 侧：Linux `ping -M do -s 1472 192.168.100.1`，Windows `ping -l 1472 -f 192.168.100.1` | 1472 通，1473 不通 |
| C6 | ARP 表 | `ip neigh` | 能看到客户端条目，状态 REACHABLE |
| C7 | 吞吐 | 路由器 `nc -l -p 5201 > /dev/null`，PC 侧 `dd if=/dev/zero bs=64k count=8000 \| nc 192.168.100.1 5201`，用 `time` 计时 | 换算 Mbps；千兆链 ≥ 900，2.5G 链 ≥ 2.0 G。PC 装了 iperf3 时优先用它 |
| C8 | 长时间传输 | 同上，跑 5 分钟 | 无断流、错误计数不涨、温度稳定 |

## D 网络：PHY 与链路

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| D1 | 外置 PHY | `dmesg \| grep mdio-bus:03` | `RTL8221B-VB-CG 2.5Gbps PHY (C45)` |
| D2 | 内置 PHY | `dmesg \| grep mdio-bus:0f` | `MediaTek MT7987 2.5GbE PHY`，固件加载 ok |
| D3 | 驱动绑定 | `dmesg \| grep -E "mtk_soc_eth.*eth[01]"` | 两行都出现，接口由 mtk_soc_eth 注册 |
| D4 | 协商速率 | `cat /sys/class/net/eth0/speed`，换 2.5G 对端再测 | 千兆对端 1000，2.5G 对端 2500 |
| D5 | 错误计数 | `ip -s link show eth0` | RX/TX errors、dropped 不随时间增长 |
| D6 | 拔插恢复 | 拔网线 10 s 再插 | 链路恢复，DHCP 客户端自动续租 |
| D7 | PHY 温度 | `cat /sys/class/hwmon/hwmon1/temp1_input` | 有读数，不异常 |

## E 网络：WAN 侧

没有外网线路时，E 组整体标记 `BLOCKED`，不要记为失败。

| ID | 用例 | 前提 | 通过标准 |
|---|---|---|---|
| E1 | WAN 口链路 | 网线插 eth1 | `carrier=1`，PHY 协商成功 |
| E2 | DHCP 上网 | 上级发 DHCP | 拿到地址、默认路由、DNS，能 ping 外网 |
| E3 | PPPoE 拨号 | 上级是 PPPoE | 拨号成功，`wan_ip` 非空 |
| E4 | VLAN 1150 | 上级要求 VLAN tag | 打 tag 后能拨号或拿地址 |
| E5 | 断线重连 | 拔 WAN 线 30 s | 恢复后自动重连，无需人工干预 |
| E6 | 双栈 | 上级发 IPv6 | wan6 拿到地址，客户端能访问 IPv6 |

## F HNAT / 流量卸载

| ID | 用例 | 命令/操作 | 通过标准 |
|---|---|---|---|
| F1 | 模块与开关 | `lsmod \| grep -E "nf_flow_table\|nft_flow"; uci show firewall \| grep offload` | 三个模块在，`flow_offloading=1`、`flow_offloading_hw=1` |
| F2 | 卸载表配置 | `nft list ruleset \| sed -n '/flowtable ft {/,/}/p'` | `devices = { "eth0", "eth1" }`，且有 `flow add @ft` 规则 |
| F3 | PPE 引擎 | `ls /sys/kernel/debug/ppe0/; head -c 400 /sys/kernel/debug/ppe0/entries` | 有 `bind`、`entries`，能列出五元组条目 |
| F4 | 软件卸载生效 | 局域网内制造被测流量（见下） | `grep -i OFFLOAD /proc/net/nf_conntrack` 有标记 |
| F5 | 硬件卸载生效 | 走 WAN 跑持续 TCP（需外网） | conntrack 出现 `[HW_OFFLOAD]`，`ppe0/entries` 有对应条目且 `packets/bytes` 增长 |
| F6 | 吞吐对比 | `uci set firewall.@defaults[0].flow_offloading_hw=0` 与 `=1` 各测一次 C7 | 开启后吞吐不低于关闭时；记录两个数值 |
| F7 | PPPoE 卸载 | 有 PPPoE 线路 | `ppe0/entries` 里出现 PPPoE 相关条目；否则记 `BLOCKED` |
| F8 | 卸载不影响短连接 | 大量短连接请求（如 `ab -n 2000`） | 全部成功，无丢包 |

F4 的做法：在设备上起一个转发流不方便，改用真实路径：PC 通过路由器访问外网时观察。没有外网时 F4 记 `BLOCKED`，只做 F1~F3。

## G 防火墙、NAT 与端口转发

| ID | 用例 | 操作 | 通过标准 |
|---|---|---|---|
| G1 | 默认策略 | `nft list ruleset \| head -30`、`uci show firewall` | WAN 入站默认拒绝，LAN 出站放行 |
| G2 | 端口转发 | 加一条 8080→内网某端口 | 外网（或 WAN 侧）能访问，内网正常 |
| G3 | DMZ | 开 DMZ 指到某内网 IP | 全部端口可达；关闭后恢复 |
| G4 | UPnP | 客户端发起 UPnP 映射 | 映射出现，能连；用完能删除 |
| G5 | fullcone NAT | 开 fullcone 后测试 | 外部可主动连入已建连的端口 |
| G6 | 规则回滚 | 改坏一条规则再改回 | 网络恢复，无残留规则 |

## H IPv6

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| H1 | 地址分配 | `ip -6 addr show br-lan` | 有全局或 ULA 地址 |
| H2 | RA/DHCPv6 | 客户端看地址 | 客户端拿到 IPv6 与 DNS |
| H3 | NDP | `ip -6 neigh` | 有条目 |
| H4 | IPv6 防火墙 | 从 WAN 侧访问内网端口 | 默认被拒 |
| H5 | 双栈访问 | 客户端访问双栈站点 | IPv4、IPv6 都通 |

## I USB（只读）

U 盘已插。**只允许读**。

允许的命令：

```sh
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
blkid
cat /proc/partitions
mount -o ro /dev/sda1 /mnt/usbtest     # 只读挂载
cat /proc/mounts | grep usbtest        # 必须看到 ro
dd if=/dev/sda of=/dev/null bs=1M count=64   # 顺序读测试
fsck.ext4 -n /dev/sda1                 # ext4 只检查；FAT 无 fsck 工具，跳过
umount /mnt/usbtest
```

禁止：任何 `of=`、`mkfs`、`parted`、`fdisk`、`wipefs`、不带 `-n` 的 `fsck`、在挂载点里创建或修改文件。

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| I1 | 识别 | `dmesg \| grep -i usb \| tail -20`、`lsblk` | 容量与 U 盘一致，无 reset/error |
| I2 | 分区与文件系统 | `blkid`、`lsblk -f` | 能识别分区与文件系统类型 |
| I3 | 只读挂载 | 上面三条命令 | 挂载成功，`/proc/mounts` 里是 `ro` |
| I4 | 目录可读 | `ls -la /mnt/usbtest \| head`、`du -sh /mnt/usbtest` | 能列出内容，无 I/O error |
| I5 | 顺序读速度 | `dd if=/dev/sda of=/dev/null bs=1M` 读 256 MB | 无错误，记录 MB/s |
| I6 | 随机读 | `dd if=/dev/sda of=/dev/null bs=4k count=2000 skip=1000` | 无错误 |
| I7 | 大文件读 | 找一个最大文件 `cat > /dev/null` | 读完无错误 |
| I8 | 只读不可写验证 | `touch /mnt/usbtest/x` | 必须失败（Read-only file system）。这是预期结果 |
| I9 | 热插拔 | 卸载后拔出，等 10 s 插回 | 能重新识别，自动挂载策略正常 |
| I10 | 负载下拔插 | 正在 `dd` 读时拔出 | 系统不崩，dmesg 有拔出错，重新插入后恢复 |
| I11 | 供电与电流 | 插 U 盘时看 `dmesg` 有无 over-current | 无 over-current、无反复重连 |
| I12 | UAS 模式 | `dmesg \| grep -i uas` | 走 UAS 或 usb-storage 均可，记录实际模式 |
| I13 | 卸载干净 | `umount /mnt/usbtest`，再 `cat /proc/mounts \| grep usbtest` | 无残留挂载点 |
| I14 | 文件完整性 | 对 U 盘内一个已知文件算 sha256 | 与 PC 侧算出的值一致 |

如果 NAS 类服务（samba、filebrowser、DLNA）会自动挂载 U 盘为读写，测试前先停掉这些服务，或确认挂载选项是 `ro`。

## J PCIe 与 NVMe

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| J1 | 两个控制器都在 | `for d in /proc/device-tree/soc/pcie@*; do echo "$(basename $d) $(tr -d '\0' < $d/status)"; done` | 两个都是 `okay` |
| J2 | 空槽行为 | `dmesg \| grep -i "pcie link down"` | 空槽有 link down，属正常 |
| J3 | 插卡识别 | 插 NVMe 后 `lspci`、`lsblk` | 能识别设备与盘 |
| J4 | NVMe 读写 | `dd if=/dev/nvme0n1 of=/dev/null bs=1M count=512` | 无错误，记录速度 |
| J5 | 热插拔 | 运行中插拔 NVMe | 能识别，无内核报错 |

没有 NVMe 卡时 J3~J5 记 `BLOCKED`。

## K 屏幕

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| K1 | 帧缓冲参数 | `cat /sys/class/graphics/fb0/virtual_size`、`bits_per_pixel`、`name` | `428,142`、`16`、`fb_nv3007` |
| K2 | 驱动日志 | `dmesg \| grep fb_nv3007` | 有 `frame buffer, 428x142`，无报错 |
| K3 | 背光 | `screen-ctl off`、`screen-ctl on` | 屏灭、屏亮，`/sys/class/gpio/gpio524/value` 随之变化 |
| K4 | 四个内置页面 | `uci set e87n-display.global.page=N`（N=1..4）各重启服务 | 每页都能显示，方向正确，无花屏 |
| K5 | 轮播 | 设 `page=cycle`，等两轮 | 自动切页，间隔与配置一致 |
| K6 | 中文完整性 | 抓帧 `screen-ctl snapshot /tmp/f.png` 后取回 | 页面里所有中文正常显示，无方框 |
| K7 | 字体文件 | `ls -l /usr/share/e87n/font.ttf` | 存在，约 1.2 MB |
| K8 | 主题列表 | `e87n-theme list` | 至少能看到内置主题 |
| K9 | 主题切换 | 切到内置主题再切回第 1 页 | 切换成功，进程唯一，无残留 |
| K10 | 导入主题 | 用 `tools/` 产出的 tar.gz 导入，再删除 | 导入、列表、切换、删除、回退全部正常 |
| K11 | 非法主题包 | 上传空包、改坏的 ELF、错误大小的 frame.raw | 全部被拒，返回明确错误，不影响当前显示 |
| K12 | 刷屏压力 | 连续切页 50 次 | 无卡死，无进程泄漏 |
| K13 | 长时间显示 | 连续显示 2 小时 | 画面不漂移、不花屏，CPU 占用稳定 |

抓帧换算：`428 × 142 × 2 = 121552` 字节，RGB565 小端。

## L 风扇

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| L1 | 控制权归属 | `cat /sys/class/thermal/cooling_device0/cur_state`、`cat /sys/class/hwmon/hwmon2/pwm1` | 内核不再改写 pwm；写 200 后 10 s 仍是 200 |
| L2 | 曲线跟随 | 读温度，用 `fan-control calc <温度>` 算期望值 | 实际 pwm 与期望相差不超过 12 |
| L3 | 手动模式 | `uci set fan.global.mode=manual; manual_pwm=128` | pwm 稳定在 128 |
| L4 | 关闭模式 | `mode=off` | pwm 变 0，风扇停 |
| L5 | 曲线热更新 | 改一个曲线点再 `uci commit` | 10 s 内按新曲线输出 |
| L6 | 回差 | 让温度在 55 ℃ 附近波动 | pwm 不频繁抖动 |
| L7 | 重启保底 | 重启后立刻读 pwm | 不为 0，风扇先转起来再交给曲线 |
| L8 | 高负载温升 | 跑满 CPU 30 分钟 | 温度稳定在阈值以下，风扇随温度上升 |
| L9 | 覆盖告警 | 若 pwm 被外部改写，`logread` 应有 WARN | 日志里能查到告警 |

L2 需要固件里有 `fan-control calc`；老固件没有该子命令时按公式手算：
`pwm = 曲线百分比 × 255 / 100`。

## M LED 与按键

| ID | 用例 | 命令/操作 | 通过标准 |
|---|---|---|---|
| M1 | 软件 LED 存在 | `ls /sys/class/leds/` | 有 `green:status`、`amber:wan` |
| M2 | 系统灯状态机 | 正常运行时看绿灯 | 常亮；进入 failsafe 时闪烁 |
| M3 | WAN 灯 | 插拔 WAN 线 | 跟随链路变化 |
| M4 | 网口 PHY 灯 | 观察 RJ45 座子里的灯 | 没插线不亮，插线亮，有流量闪 |
| M5 | 手动控制 | `echo 1 > /sys/class/leds/green:status/brightness` 再写 0 | 灯跟着变 |
| M6 | reset 键短按 | 按一下 reset | 触发重启 |
| M7 | reset 长按 | 按住 10 s 以上 | 进入恢复或恢复出厂（按当前实现记录实际行为） |

M4 需要人眼确认，agent 只记录“已交人工确认”。

## N 服务与预装包

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| N1 | 商店 | `apk list -I \| grep luci-app-store`、`ls /usr/lib/lua/luci/controller/store.lua` | 两者都在 |
| N2 | 网络向导 | `apk list -I \| grep luci-app-quickstart`、`ps \| grep [q]uickstart` | 包在，守护进程在跑 |
| N3 | OTA | `apk list -I \| grep ota`、LuCI 里能看到 OTA 页面 | 存在且可打开 |
| N4 | 常用包 | `apk list -I \| grep -E "ddns|sqm|nlbwmon|ttyd|upnp|filebrowser"` | 全部已装 |
| N5 | LuCI 页面可打开 | 逐个访问 系统、网络、服务、屏幕控制、风扇控制 | 全部 200，无 JS 报错（看浏览器控制台） |
| N6 | 服务自启 | `ls /etc/rc.d/ \| grep -E "S.*(fan\|screen\|e87n\|istore)"` | 关键服务都是 S 开头 |
| N7 | 进程唯一性 | `ps \| grep -c "[e]87n-display"` | 不超过 1 |

## O 指标接口

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| O1 | 文件存在与格式 | `cat /var/run/e87n/metrics.json` | 合法 JSON，字段齐全 |
| O2 | 刷新频率 | 间隔 3 s 取两次 ts 字段 | 差值约 3 |
| O3 | 字段正确性 | 对照 `cat /sys/class/hwmon/hwmon0/temp1_input` | `temp_c` 与硬件读数一致（±2） |
| O4 | 原子写 | 连续 200 次读取 | 不出现半截 JSON |
| O5 | ubus 接口 | `ubus call e87n status` | 返回同样的数据 |
| O6 | 异常处理 | 停掉数据源（`killall e87n-metrics`） | 文件保留上次内容，重启服务后恢复 |

## P 升级与回滚

| ID | 用例 | 操作 | 通过标准 |
|---|---|---|---|
| P1 | sysupgrade 保留配置 | 记录若干 uci 值，`sysupgrade` 后检查 | 配置与密钥都在 |
| P2 | sysupgrade 不保留 | 加 `-n` 刷，检查 | 恢复默认，能正常启动 |
| P3 | p4 单刷内核 | `dd` 写 p4 后回读校验 | sha256 与镜像里的 kernel 一致，p3 不变 |
| P4 | 断电模拟 | 刷 p5 过程中强制断电（仅限可恢复环境） | U-Boot 仍能启动到可用系统；记录恢复步骤 |
| P5 | 回滚 | 刷回上一版本 | 能起来，`roboots.log` 无异常 |
| P6 | 版本一致性 | `cat /etc/openwrt_release` 与 Release 说明 | 版本号一致 |

P4 风险高，只在明确允许时做；不做就记 `SKIPPED`。

## Q 稳定性与压力

| ID | 用例 | 操作 | 通过标准 |
|---|---|---|---|
| Q1 | 24 小时空载 | 保持上电，每小时采样 | 内存无持续增长，温度平稳，无异常重启 |
| Q2 | 24 小时带流量 | 持续跑 C7 的 nc 传输，或大文件反复读 | 无断流，无重启，误差计数不涨 |
| Q3 | 内存泄漏 | 每 10 分钟记录 `free -m` 和进程 RSS | 2 小时内 RSS 增长不超过 10% |
| Q4 | 文件描述符 | `ls /proc/<pid>/fd \| wc -l` 定时采样 | 不持续增长 |
| Q5 | 日志增长 | `du -sh /overlay/upper/var` | 不爆涨，日志有轮转 |
| Q6 | 反复重启 10 次 | 循环重启 | 每次都能起来，配置不丢，`reboots.log` 记录正确 |
| Q7 | CPU 满载 | `dd if=/dev/zero of=/dev/null &` × 4 | 系统可响应，温度不失控 |

Q1、Q2 需要长时间，agent 至少要跑 2 小时并在报告里写明实际时长。

## R 安全

| ID | 用例 | 命令 | 通过标准 |
|---|---|---|---|
| R1 | root 密码 | `grep "^root:" /etc/shadow \| cut -d: -f2` | 第二段非空（有密码）。为空时标红并立即告知 |
| R2 | SSH 授权 | `cat /etc/dropbear/authorized_keys` | 只有授权的公钥 |
| R3 | 服务暴露面 | `netstat -lnt` | 只监听必要端口；从 WAN 侧访问管理页应失败 |
| R4 | 默认口令 | 检查 ddns、filebrowser 等服务 | 无默认弱口令 |
| R5 | UPnP 风险 | 关闭 UPnP 后再测 | 外部无法随意建映射 |

## 报告格式

每条用例一行，最后给出总表和结论：

```
| ID | 结果 | 证据（命令输出摘录或文件名） | 耗时 | 备注 |
| A1 | PASS | 25.12.5 / EdgePi E87N | 1m | |
| I5 | PASS | 258 MB/s（读 256 MB 无错） | 3m | |
| F5 | BLOCKED | 无外网线路 | - | 需 WAN 线 |
```

结果只用四种：`PASS`、`FAIL`、`BLOCKED`、`SKIPPED`。

收尾必须包含：

1. `sha256sum /dev/mmcblk0p3` 的终值，与 baseline 对比。
2. 所有 `FAIL` 的复现步骤、原始报错、初步判断。
3. `BLOCKED` 的原因和需要的外部条件。
4. 测试期间的温度峰值、内存峰值、是否发生异常重启（查 `reboots.log`）。

## 当前固件的已知偏差

这些不是新问题，报告里注明即可，不要重复开单：

| 现象 | 原因 | 状态 |
|---|---|---|
| 老固件上风扇被钉在 4%~12% | DTS 里 fan 挂了 cooling-map，内核 governor 覆盖用户态 PWM | 新固件已删那三条 map；老固件可用 `/etc/init.d/fan-guard` 兜底 |
| 网口灯没插线也亮 | 6.12 的 2.5G PHY 驱动重新打开了 LED 极性位 | 新固件补丁 `795` 已修 |
| 演示主题刷机后消失 | 主题原本只在 overlay | 新固件装到只读分区，并由 uci-defaults 播种 |
| 内置页面缺字 | 生成字体只有几十个汉字 | 新固件改用 `/usr/share/e87n/font.ttf` 运行期加载 |
| factory 分区全 0，MAC 随机 | 本机没有出厂数据 | 正常现象 |
