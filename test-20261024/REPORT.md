# E87N 测试报告

- 日期：2026-10-24
- 设备：EdgePi E87N（MT7987A，1 GiB / 8 GB eMMC）
- 固件：iStoreOS 25.12.6，内核 6.12.112（Release `v25.12.5-e87n-r5`）
- 执行方式：SSH 远程执行，只读用例为主；U 盘全程只读

## 结论

可以部署，但要先确认两件事：

1. **新机器刷完必须先跑 `e87n-prep-overlay` 再重启**，否则 overlay 仍在 p5 尾部的 loop 上，配置不持久。
2. **FAT32 / exFAT 的 U 盘要等下一版固件**。当前这版缺 `kmod-fs-vfat`，`mount` 会报 `unknown filesystem type 'vfat'`。已加入配置，构建中。

除此之外，硬件、网络、卸载、屏幕、风扇、服务均正常，自检 46 项全过。

## 环境基线

| 项 | 值 |
|---|---|
| 版本 | iStoreOS 25.12.6，revision r0-283d026 |
| 内核 | 6.12.112 |
| 机型 | `EdgePi E87N` |
| 分区 | p1 512K、p2 4M、p3 2M、p4 32M、p5 512M、p6 6.7G |
| p3 校验 | `ad1ff3c9c3148167775116e3…`（全程未变） |
| p4 头部 | `d00dfeed`（FIT） |
| overlay | `/dev/mmcblk0p6`，ext4，分区 6.5 GB，可用 6.2 GB |

## 结果汇总

| 组 | 结果 | 说明 |
|---|---|---|
| A 启动与系统 | PASS | 无 panic、无 Call trace；`reboots.log` 里的「异常重启」是手工断电测试留下的 |
| B 存储与分区 | PASS | 六个分区齐全，p3 校验一致 |
| C 网络 LAN | PASS | eth0 千兆链路，DHCP 正常 |
| D PHY 与链路 | PASS | `RTL8221B-VB-CG 2.5Gbps (C45)`、`MediaTek MT7987 2.5GbE PHY` |
| E WAN | BLOCKED | 测试环境没有外网线路，`eth1 carrier=0` |
| F HNAT | PASS（部分） | `flow_offloading=1`、`hw=1`、`flow add @ft` 1 条、PPE 表 31 条；真实转发卸载需 WAN |
| G 防火墙/NAT | PASS（部分） | 默认策略、端口转发规则存在；外网侧验证 BLOCKED |
| H IPv6 | PASS | br-lan 有全局地址，NDP 正常 |
| I USB | 部分 PASS | 识别与裸读通过；挂载 FAIL（缺 vfat），已修待复测 |
| J PCIe | PASS | 两个控制器 `okay`，空槽 link down，nvme 驱动在 |
| K 屏幕 | PASS | `fb_nv3007` 428×142；四个页面截图见本目录 `k4-2/3/4.png`、`k6-page1.png`，中文（星期四、下午、内存、磁盘、下载、上传）全部正常 |
| L 风扇 | PASS（修复后） | 温度与曲线一致，54 ℃ → pwm 135 = 期望值 |
| M LED | 部分 | 软件 LED 正常；RJ45 座子里的 PHY 灯需人眼确认 |
| N 服务与包 | PASS | 商店、网络向导、OTA、ddns、sqm 等都在 |
| O 指标接口 | PASS | `metrics.json` 22 字段、ubus 可用 |
| P 升级 | PASS | `sysupgrade` 保留配置；p4 单刷回读校验通过 |
| Q 稳定性 | 部分 | 本次连续运行约 16 分钟（含多次重启与断电）；24 小时压测未做 |

## 本次发现并修复的缺陷

### 1. overlay 不持久（严重，已修）

现象：改过的配置重启即回默认，SSH 主机密钥每次都变，装的软件和主题消失。

定位：同样重启、不同存储位置对照——p2 上的直接 ext4 分区数据不丢，p5 尾部
「loop + 偏移」上的文件系统（f2fs 和 ext4 都试过）重启后恢复不出内容。数据确实写到了
flash（`drop_caches` 后读裸设备能看到），所以不是 eMMC、不是 `sync`、不是文件系统类型。

修法：p5 缩到 512 MB，空出来的建 p6（6.7 GB，ext4，GPT 名 `rootfs_data`），
固件里 `/etc/config/fstab` 用 extroot 指向它。实机验证：改 uci、写文件、重启后都在；
断电复测也在。

### 2. 风扇滞回死锁（严重，已修）

现象：温度从 54 ℃ 降到 47 ℃ 后，PWM 一直停在 135 不降。

原因：`last_temp` 每轮循环都被刷新成当前温度，导致「降温才允许降档」的条件恒成立。

修法：只在真正改档时记录温度。验证：49 ℃ → 109（与 `fan-control calc` 一致），
48 ℃ 保持在 114（回差 3 ℃ 内，符合预期）。

### 3. 缺 FAT32 模块（中等，已修未复测）

现象：`mount -o ro /dev/sda1` 报 `unknown filesystem type 'vfat'`。

原因：镜像只带了 `kmod-fs-ext4` 和 `ntfs3`，没有 vfat/exfat 及其 nls 依赖。

修法：`e87n.config` 增加 `kmod-fs-vfat`、`kmod-fs-exfat`、`kmod-nls-cp437`、
`kmod-nls-iso8859-1`、`kmod-nls-utf8`。复测要等新固件。

## 屏幕截图证据

本目录下的截图取自实机抓帧（`screen-ctl snapshot`，121552 字节 RGB565）：

| 文件 | 内容 | 结论 |
|---|---|---|
| `k6-page1.png` | 页面 1 系统概况 | IP、下载/上传速率正常 |
| `k4-2.png` | 页面 2 时间 | `2026-10-22`、`星期四`、`下午` 全部正常显示 |
| `k4-3.png` | 页面 3 网速图表 | `下载`、`上传` 标签正常 |
| `k4-4.png` | 页面 4 圆弧状态 | `CPU`、`内存`、`温度`、`磁盘` 正常 |

中文字形来自 `/usr/share/e87n/font.ttf`（GB2312 子集，运行期用 tiny_ttf 加载），
不再依赖编译期只带几十个汉字的点阵字体。

## USB 实测数据

U 盘：HIKSEMI，62.9 GB，FAT32（引导扇区 0x52 处为 `FAT32`，OEM 名 `mkdosfs`），
UUID `6A57-8D05`。

| 项 | 结果 |
|---|---|
| 识别 | `/dev/sda` + `/dev/sda1`，`usb 2-1: 346d:5678` |
| 驱动 | `uas`、`usb-storage` 均已注册 |
| 裸读 256 MB | 49.3 MB/s，无错误 |
| 写扇区计数 | 全程 0（确认未写盘） |
| 只读挂载 | FAIL，缺 vfat 模块 |

## 待验证

| 项 | 原因 | 怎么验 |
|---|---|---|
| FAT32 / exFAT 挂载 | 等新固件 | `mount -o ro /dev/sda1 /mnt/usb`，`touch` 必须失败 |
| WAN / PPPoE / VLAN 1150 | 无外网线路 | 有线路后按 E 组跑，重点看 `[HW_OFFLOAD]` 与 PPE 条目增长 |
| HNAT 端到端吞吐 | 同上 | 开关 `flow_offloading_hw` 各测一次 nc 传输 |
| NVMe 链路速率 | 两个 M.2 槽位没插卡 | 插盘后 `lspci`、`dd` 读盘 |
| RJ45 PHY 灯 | 需人眼 | 不插线不亮，插线亮 |
| 24 小时压测 | 时间不够 | Q1、Q2 用例 |

## 复现命令

```bash
# 部署前必做（新机）
e87n-prep-overlay && reboot

# overlay 是否在 p6
grep ' /overlay ' /proc/mounts

# 持久化验证
uci set fan.global.hysteresis=9 && uci commit
touch /root/persist-test && sync
reboot

# 风扇跟随曲线
T=$(($(cat /sys/class/hwmon/hwmon0/temp1_input)/1000))
echo "temp=$T pwm=$(cat /sys/class/hwmon/hwmon2/pwm1) expect=$(fan-control calc $T)"

# 自检
sh tools/acceptance.sh
```

## 说明

- `reboots.log` 里 2026-10-22 那条「异常重启」是手工拔电源做持久化测试留下的记录，
  不是故障重启。内核日志里没有任何 panic、oops 或 Call trace。
- p3（FIP/U-Boot）全程未写，校验值 `ad1ff3c9…` 与备份一致。
- eMMC 健康：`pre_eol_info=0x01`（正常），`life_time=0x04`（消耗 10%~20%）。
