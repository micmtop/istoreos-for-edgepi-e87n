# EdgePi E87N · iStoreOS

给 **EdgePi / Hiveton E87N（MT7987A）** 路由器编译的 iStoreOS 固件。仓库里是构建脚本、
设备树、内核补丁、自研软件包和 CI，固件本体由 GitHub Actions 产出。

当前基线：**iStoreOS 25.12.5（内核 6.12.94）**，产物已在实机验证（见
`docs/MIGRATE-25.12.md` 第 6 节）。

现成固件（含内核 FIT）在 Releases：
<https://github.com/micmtop/istoreos-for-edgepi-e87n/releases>

---

## 硬件

| 项 | 规格 |
|---|---|
| SoC | MediaTek MT7987A（4×Cortex-A53，内置 2.5G PHY） |
| 内存 / 存储 | 1 GiB DDR4 / 8 GB eMMC（p1 env、p2 factory、p3 fip、p4 kernel、p5 rootfs） |
| 网口 | eth0 = 外置 RTL8221B 2.5G（MDIO 3）；eth1 = 内建 MT7987 2.5G PHY（MDIO 15） |
| 扩展 | 双 M.2 2230（PCIe0 + PCIe1，各一个控制器，按 NVMe 用）、USB 3.2 A 口 |
| 显示 | NewVision NV3007 1.65" 428×142 SPI 屏 + GPIO524 背光 |
| 其它 | PWM 风扇、绿色/琥珀双 LED、reset 键、串口 115200 8N1 |
| 无线 | **无 WiFi**（E87N 没有无线模块，两个 M.2 槽位按 NVMe 使用） |
| MAC | 本机 eMMC factory 分区为空，MAC 由 OpenWrt 随机分配并在首次启动后固定 |

---

## 功能

- **网络**：双 2.5G、VLAN/PPPoE、IPv6（RA/DHCPv6/NDP relay）、fullcone
- **硬件加速**：`mtk_eth_soc` + PPE 硬件 NAT、`nf_flow_table` + `nft_flow_offload`
  （`firewall` 默认 `flow_offloading=1`、`flow_offloading_hw=1`）
- **风扇**：`fan-control` 温度→占空比曲线（百分比可调，LuCI 画布拖拽）
- **屏幕**：内核 `fb_nv3007`（fbtft）+ 用户态 `e87n-display`（LVGL 9.4），
  4 个内置页面 + 轮播，支持**导入自定义主题**
- **中文**：固件自带 `/usr/share/e87n/font.ttf`（GB2312 子集），内置界面和主题
  都从它取字形，不再出现方框；主题包不必再自带字体
- **指标接口**：`/var/run/e87n/metrics.json` 每秒刷新，另有 `ubus call e87n status`
- **每日一言**：`e87n-saying` 从 uapis.cn 取句并缓存，离线时用内置兜底句

---

## 构建

固件在 GitHub Actions 上构建，本机不需要工具链。

| Workflow | 用途 | 耗时 |
|---|---|---|
| `E87N Build` | 整机固件（内核 + 包 + rootfs），push 到 main 自动触发 | 首次 ~1.5 h |
| `E87N Kernel Only` | 只编内核并生成 FIT，改了驱动/DTS 时用 | 首次 ~40 min，之后 ~10 min |
| `E87N Theme Build` | 只交叉编译 `themes/<name>/` 出主题包 | 首次 ~20 min，之后 ~5 min |

```bash
# 整机（默认 istoreos-25.12；换分支用 -f branch=）
gh workflow run build.yml -R micmtop/istoreos-for-edgepi-e87n -f branch=istoreos-25.12
# 只编内核
gh workflow run kernel-only.yml -R micmtop/istoreos-for-edgepi-e87n
# 只编主题
gh workflow run theme-build.yml -R micmtop/istoreos-for-edgepi-e87n -f theme=aurora
```

`apply.sh` 负责把 `files/` 覆盖进 iStoreOS 源码树：设备树、内核补丁、E87N 设备定义、
内核 Kconfig 符号注入。补丁按“**上游优先**”打：上游同号补丁存在就跳过我们的，
所以 6.6（`istoreos-24.10`）和 6.12（`istoreos-25.12`）共用同一份 `files/`。

改过板级 DTS 后可以先本地跑一遍静态校验（3 秒，不用等 1.5 h 编译）：

```sh
sh tools/check-dts.sh      # 校验 &label 引用 + 关键节点是否还在
```

---

## 刷机

固件产物是 `*squashfs-sysupgrade.bin`（tar 包，内含 `kernel` 和 `root`）。

U-Boot 从独立的 p4 分区加载内核 FIT。平台的 `emmc_do_upgrade` 按分区名
（`kernel` / `rootfs`）写盘，所以 **`sysupgrade` 会同时更新 p4 和 p5**；
只有想单独换内核（比如用 `E87N Kernel Only` 产物）时才需要手写 p4：

```sh
# 只在系统能起来时做；写前先备份并核对分区
sha256sum /dev/mmcblk0p3          # 记录，事后必须一致
dd if=/tmp/kernel of=/dev/mmcblk0p4 bs=4096
sync; head -c <FIT 长度> /dev/mmcblk0p4 | sha256sum   # 回读校验
```

**永远不要写 p3（FIP/U-Boot）**。eMMC 引导区的 BL2 与 p3 里的 FIP/BL31 必须成对，
单独替换其中一半会卡在 `BL2: Booting BL31`。恢复靠串口 RAM boot（`mtk_uartboot`）。

写入 eMMC 只用**分区设备**（`/dev/mmcblk0pN`），不要用整盘 + seek。

---

## 屏幕与主题

内置页面：系统概况 / 时间 / 网速图表 / 圆弧状态，支持轮播与自定义文本。

### 导入自定义主题

LuCI → **屏幕控制 → 主题**，上传 `tar.gz` 后主题会出现在"显示页面"下拉里。主题包结构：

```
theme.json     {"name":"我的主题"}
app            aarch64 ELF（自己画屏，可用下面的指标接口）
frame.raw      428x142 RGB565 整帧（静态画面，121552 字节）
font.ttf       可选，随主题安装的字体（要显示完整中文就带上，见 SDK 文档 2.5）
```
`app` 与 `frame.raw` 二选一。安装时会校验 ELF 架构与整帧长度。

命令行等价：

```sh
e87n-theme install mytheme.tar.gz
uci set e87n-display.global.page=theme:mytheme
uci commit e87n-display && /etc/init.d/e87n-display restart
```

参考实现：`themes/aurora/`（暗色 + 琥珀色数字 + 分段电平条 + 扫描线，显示时间、
温度、上下行、IP、在线数、每日一言）。它**内置在固件里**：app 由固件构建过程
一起交叉编译，装到 `/usr/share/e87n/themes/aurora/`，首次启动由 uci-defaults
播种到 overlay，所以刷机后不会消失。字体直接用系统字体。

### 指标接口（给自定义程序）

```sh
cat /var/run/e87n/metrics.json     # 1 Hz，原子写入
ubus call e87n status
```

```c
#include "e87n_metrics.h"          /* docs/sdk/，设备上也在 /usr/share/e87n-sdk/ */
e87n_metrics_t m;
if (e87n_metrics_read(&m) == 0)
    printf("%d°C  %lu B/s  %d clients\n", m.temp_c, m.rx_bps, m.clients);
```

字段见 `docs/LVGL-CUSTOM-IMPORT.md`。控制类操作（开关屏/切页/风扇）用
`screen-ctl`、`fanctl` 或 CGI，不建议直接写 GPIO。

---

## 自检

设备上直接跑，只读、不改状态：

```sh
sh tools/acceptance.sh
```

覆盖系统/overlay、eMMC 分区、网口与 PHY 绑定、HNAT 与 flow offload、风扇温度、
LED、USB、两个 PCIe 控制器、屏幕背光、服务与接口、主题。
25.12 实机结果：**41 passed / 0 failed**。

---

## 已知限制

- **无 WiFi**：E87N 没有无线硬件，M.2 槽位是 NVMe。
- **PCIe 需要插卡才会 link up**：两个控制器的 `status` 都是 `okay`，空槽位时
  `mtk-pcie-gen3` 会各报一条 `link down, current LTSSM state: detect.quiet`，
  这是正常现象；插上 NVMe 才能验证实际链路速率。
- **MAC 是随机分配的**：本机 eMMC factory 分区全 0，没有出厂 MAC 可读，
  OpenWrt 会生成一个本地管理 MAC 并固定下来。
- **WAN 未实机验证**：目前测试环境没有外网线路，PPPoE/VLAN 1150 只能等有线路时验证。
- 背光为 GPIO524 直控（低电平点亮），没有走 `/sys/class/backlight`。

---

## 目录

```
apply.sh                     把 files/ 应用进 iStoreOS 源码树
e87n.config                  目标配置（包选择、内核符号）
files/target/linux/mediatek/dts/        MT7987 dtsi + E87N 板级 DTS
files/target/linux/mediatek/patches-6.6/ 内核补丁（mtk_eth / 2.5G PHY / fbtft-NV3007；6.12 上按上游优先只补缺的）
package/e87n-tools           风扇、背光、指标、一言、主题管理（纯脚本）
package/e87n-display         LVGL 显示程序（内置 4 页）
package/luci-app-e87n        LuCI 页面 + CGI
package/mt7987-2p5g-phy-firmware     内建 2.5G PHY 固件
themes/aurora                示例主题（可复制改造）
docs/                        主题/指标接口文档、SDK、验收记录
tools/acceptance.sh          硬件与功能自检
tools/check-dts.sh           板级 DTS 标签/关键节点静态校验（编译前跑）
```
