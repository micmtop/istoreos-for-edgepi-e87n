# EdgePi E87N · iStoreOS

给 EdgePi E87N 路由器编译的 iStoreOS 固件。仓库里放构建脚本、设备树、内核补丁、
自研软件包和 CI 配置，固件由 GitHub Actions 产出。

当前基线是 iStoreOS 25.12.5，内核 6.12.94，已在实机验证。现成固件在 Releases 页面。

## 硬件

| 项 | 规格 |
|---|---|
| SoC | MediaTek MT7987A，4 核 Cortex-A53，内置 2.5G PHY |
| 内存与存储 | 1 GiB DDR4，8 GB eMMC |
| 分区 | p1 u-boot-env、p2 factory、p3 fip、p4 kernel、p5 rootfs |
| 网口 | eth0 接外置 RTL8221B，2.5G；eth1 接内置 MT7987 PHY，2.5G |
| 扩展 | 两个 M.2 2230 槽位，各挂一个 PCIe 控制器，按 NVMe 使用 |
| USB | 一个 USB 3.2 A 口 |
| 屏幕 | NewVision NV3007，428×142，SPI，背光走 GPIO524 |
| 其它 | PWM 风扇、绿色和琥珀色 LED、reset 键、串口 115200 8N1 |
| 无线 | 没有，板上没有无线模块 |

## 功能

网络支持双 2.5G、VLAN、PPPoE、IPv6 和 fullcone。

硬件加速用 mtk_eth_soc 的 PPE，配合 nf_flow_table 和 nft_flow_offload。
firewall 默认 `flow_offloading=1`、`flow_offloading_hw=1`。

屏幕由内核 fb_nv3007 驱动，用户态程序 e87n-display 用 LVGL 9.4 画 4 个内置页面，
支持轮播和导入自定义主题。中文从固件自带的 `/usr/share/e87n/font.ttf` 取字形，
换主题、删主题都不会缺字。

风扇按温度曲线调 PWM，曲线和档位在 LuCI 里拖动修改。

屏幕数据来自 `/var/run/e87n/metrics.json`，每秒刷新。也可以用
`ubus call e87n status` 取一次。

每日一言由 e87n-saying 从 uapis.cn 取，带缓存，离线时用内置句子。

## 构建

| Workflow | 用途 | 耗时 |
|---|---|---|
| E87N Build | 整机固件，push 到 main 自动触发 | 1.5 h |
| E87N Kernel Only | 只编内核并生成 FIT，改了驱动或 DTS 时用 | 40 min |
| E87N Theme Build | 只交叉编译 `themes/<名字>/`，出主题包 | 20 min |
| Publish firmware | 把某次构建的产物转存成 Release | 1 min |
| E87N Config Diag | 只跑 feeds 和 defconfig，查包为什么没进固件 | 3 min |

```bash
# 整机。默认分支 istoreos-25.12
gh workflow run build.yml -R micmtop/istoreos-for-edgepi-e87n
# 只编内核
gh workflow run kernel-only.yml -R micmtop/istoreos-for-edgepi-e87n
# 只编主题
gh workflow run theme-build.yml -R micmtop/istoreos-for-edgepi-e87n -f theme=aurora
# 转存成 Release，方便国内下载
gh workflow run publish.yml -R micmtop/istoreos-for-edgepi-e87n -f run_id=<run id> -f tag=<tag>
```

`apply.sh` 把 `files/` 覆盖进 iStoreOS 源码树，包括设备树、内核补丁、E87N 设备定义
和内核 Kconfig 符号。补丁按上游优先装：上游同号补丁存在就跳过我们的，
`files/.../patches-6.12/` 放 6.12 专用补丁。

改过板级 DTS 后先跑本地校验，3 秒出结果，不用等整机编译：

```bash
sh tools/check-dts.sh
```

## 下载与刷机

Releases 页面在 <https://github.com/micmtop/istoreos-for-edgepi-e87n/releases>。
里面有两种产物：`squashfs-sysupgrade.bin` 是整机升级包，
`edgepi_e87n-kernel-6.12.94.fit` 是单独的内核。同一个 tag 里还有 `SHA256SUMS`。

国内下载慢时在前面加镜像前缀，链接原样拼在后面：

```bash
curl -LO https://gh-proxy.com/https://github.com/micmtop/istoreos-for-edgepi-e87n/releases/download/<tag>/<文件名>
```

整机升级直接刷，平台的 `emmc_do_upgrade` 会按分区名 kernel 和 rootfs
同时写 p4 和 p5：

```bash
sysupgrade istoreos-mediatek-filogic-edgepi_e87n-squashfs-sysupgrade.bin
```

只想换内核时单独写 p4，写完回读校验：

```bash
FIT=edgepi_e87n-kernel-6.12.94.fit
sha256sum /dev/mmcblk0p3                 # 记下来，事后必须一致
dd if=$FIT of=/dev/mmcblk0p4 bs=4096 conv=fsync

SZ=$(stat -c%s $FIT); CNT=$(( (SZ + 4095) / 4096 ))
dd if=/dev/mmcblk0p4 bs=4096 count=$CNT 2>/dev/null | head -c $SZ | sha256sum
sha256sum $FIT                           # 两个值必须一致
```

**不要写 p3。** eMMC 引导区的 BL2 和 p3 里的 FIP、BL31 必须成对，
换掉一半会卡在 `BL2: Booting BL31`，只能靠串口 RAM boot 恢复。
写 eMMC 只用分区设备 `/dev/mmcblk0pN`，不要整盘加 seek 偏移。

## 屏幕与主题

内置 4 个页面：系统概况、时间、网速图表、圆弧状态。LuCI 的“屏幕控制”里可以切页、
设轮播间隔、开关背光。

演示主题 aurora 装在 `/usr/share/e87n/themes/aurora`。
首次启动时，`/etc/uci-defaults/95-e87n-theme-seed` 把它复制到
`/etc/e87n-display/themes/`，刷机后不会丢。
它的 app 在固件构建时一起交叉编译，源码在 `themes/aurora/`。

导入自己的主题，在 LuCI → 屏幕控制 → 主题里上传 `tar.gz`。包结构：

```
theme.json      必需，{"name":"我的主题"}
app             二选一，aarch64 ELF，程序自己画屏
frame.raw       二选一，428×142 RGB565 整帧，121552 字节
font.ttf        可选，自带字体。不带就用系统字体
```

命令行等价操作：

```bash
e87n-theme install mytheme.tar.gz
uci set e87n-display.global.page=theme:mytheme
uci commit e87n-display && /etc/init.d/e87n-display restart
e87n-theme remove mytheme
```

主题可以读指标文件拿温度、网速、在线数。C 接口和字段表见
`docs/LVGL-CUSTOM-IMPORT.md`，SDK 在 `docs/sdk/`，设备上也在 `/usr/share/e87n-sdk/`。

## 风扇

曲线默认 5 个点：35 ℃ 对应 0%，45 ℃ 对应 35%，55 ℃ 对应 55%，65 ℃ 对应 78%，
75 ℃ 对应 100%。中间线性插值，回差 3 ℃，避免在档位边缘来回跳。

内核 `cpu_thermal` 里有三条 cooling-map 把风扇当 cooling device 用。
`step_wise` 在 40 ℃ 以上就会把风扇钉在最低档，并不断覆盖用户态写进去的 PWM，
自定义曲线等于失效。板级 DTS 删掉了这三条 map，保留 CPU 降频那条，
pwm1 由 fan-control 独占。

驱动 probe 后 pwm 是 0，所以 init 脚本启动时先写一个保底 PWM，再交给守护进程。
守护进程每轮回读 pwm，发现被别的驱动覆盖会在 `logread` 里打警告。

## 自检

设备上直接跑，只读，不改状态：

```bash
sh tools/acceptance.sh
```

覆盖系统和 overlay、eMMC 分区、网口与 PHY 绑定、HNAT 与 flow offload。
也检查风扇是否跟随曲线、LED、USB、两个 PCIe 控制器、屏幕背光、
商店和网络向导、主题服务。当前版本 45 项全过。

## 已知限制

WAN 没做端到端验证。测试环境没有外网线路，`wan_ip` 为空，
PPPoE 和 VLAN 1150 等有线路时再验。HNAT 的驱动、PPE 表和 flowtable 配置都已确认在位。

两个 M.2 槽位没插卡，只能看到 `link down`，链路速率要插上 NVMe 才能测。

本机 eMMC factory 分区全 0，没有出厂 MAC，系统随机分配一个并在首次启动后固定。

背光是 GPIO524 直控，低电平点亮，没有走 `/sys/class/backlight`。

## 目录

```
apply.sh                     把 files/ 应用进 iStoreOS 源码树，补丁按内核版本装
e87n.config                  包选择和内核符号
files/target/linux/mediatek/dts/          MT7987 dtsi 和 E87N 板级 DTS
files/target/linux/mediatek/patches-6.6/  6.6 用补丁
files/target/linux/mediatek/patches-6.12/ 6.12 专用补丁
package/e87n-display         LVGL 显示程序，内置 4 页，装系统字体和演示主题
package/e87n-tools           风扇、背光、指标、一言、主题管理，纯脚本
package/luci-app-e87n        LuCI 页面和 CGI
package/mt7987-2p5g-phy-firmware         内置 2.5G PHY 固件
themes/aurora                演示主题源码，固件构建时一起编译
docs/                        主题和指标接口文档、SDK、迁移记录
tools/acceptance.sh          硬件和功能自检
tools/check-dts.sh           板级 DTS 标签和关键节点校验
```
