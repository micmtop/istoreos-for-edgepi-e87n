# istoreos-for-edgepi-e87n

为 EdgePi (Hiveton) E87N 路由器编译的 iStoreOS 固件。基于 OpenWrt 24.10（iStoreOS 分支），内核 6.6。

> **【临时警告】屏幕功能未经实机验证**
> 作者本人的 E87N 屏幕排线座已损坏，无法点亮屏幕。本固件的屏幕驱动（`fb_nv3007`）与背光虽已实现并编译进内核，但**未经真机测试**（初始化序列参考 Arduino_GFX / LVGL 官方 NV3007 驱动移植，理论上完整，不保证实机正常）。刷入此固件后，请自行验证屏幕显示与背光是否工作。

## 新功能介绍（相对原厂 HiGoROS）

- 硬件 NAT：MT7987 PPE flow offload（`kmod-nft-offload` / `kmod-ipt-offload`，firewall 默认启用），充分发挥双 2.5G 性能
- 风扇控制：LuCI 风扇百分比控制 + 曲线配置（fan-control）
- 屏幕控制：luci-app-e87n，支持自定义显示（LVGL 应用上传与预览）、背光控制
- 存储修复：overlay 改用 fstools `rootfs_data`，不再占用 p3（FIP/U-Boot）分区——修复了原 iStoreOS 启动脚本把 p3 当 overlay、每次开机覆盖 U-Boot 的严重缺陷
- 系统升级：sysupgrade 走 `emmc_do_upgrade`，同时更新 p4 内核 FIT 与 p5 rootfs（修复原 nand/emmc 分支判断错误）
- 网口：`en8811h` 驱动，eth0/eth1 双 2.5G 正常工作

## 硬件概览

| 组件 | 规格 |
|---|---|
| SoC | MT7987A（4x Cortex-A53） |
| 内存 | 1GB DDR |
| 存储 | 8GB eMMC |
| 网络 | 双 2.5G 网口（Airoha EN8811H PHY），LAN + HNAT |
| 屏幕 | NV3007 控制器（SPI2, 142x428, rotate 270, fbtft） |
| 风扇 | PWM 风扇（内核 channel 1, 20kHz） |
| WiFi | 无（E87N 无 WiFi 功能） |

## 已实现功能

- 网口：`en8811h` 驱动，eth0（LAN）+ eth1（WAN），2.5G 速率
- 屏幕：`fb_nv3007` 驱动（编译进内核，非模块），`pwm-backlight` 背光（PWM2 通道）
- 风扇：PWM 调速，LuCI 风扇曲线控制
- 硬件 NAT：MT7987 PPE flow offload（`kmod-nft-offload` / `kmod-ipt-offload`，firewall 默认启用）
- 存储：eMMC rootfs + f2fs overlay（fstools `rootfs_data`，不占用 FIP/U-Boot 分区）
- 系统升级：sysupgrade（`emmc_do_upgrade`，同时更新 kernel 与 rootfs 分区）
- WebUI：LuCI + 快速向导（quickstart）+ E87N 风扇/屏幕/LVGL 上传控制（luci-app-e87n）

## 构建方法

### 通过 GitHub Actions（推荐）

推送到仓库 `main` 分支即可触发构建（`.github/workflows/build.yml`）。产物在 Actions 的 `e87n-istoreos-firmware` artifact 中。

### 本地构建

```bash
# 依赖 iStoreOS 24.10 源码与 OpenWrt 构建工具链
git clone -b istoreos-24.10 https://github.com/istoreos/istoreos.git istoreos
bash apply.sh              # 应用 E87N + MT7987 补丁
cp e87n.config .config
make defconfig
make -j$(nproc) V=s
```

## 刷机方法

### sysupgrade（运行中系统）

```bash
# 上传固件到 /tmp（使用带前缀文件名，避免与 /tmp/root 冲突）
sysupgrade -n /tmp/e87n_sysupgrade.bin
```

sysupgrade 会通过 `emmc_do_upgrade` 同时更新 p4（kernel FIT）与 p5（rootfs）。

### U-Boot WebUI 恢复

1. 冷启动后按住 reset 约 10 秒，进入 U-Boot httpd 恢复模式
2. 电脑网卡设静态 IP `192.168.1.2/24`
3. 浏览器访问 `http://192.168.1.1`，上传完整固件包

## 恢复与排障

- eMMC 分区：p4 = kernel（FIT），p5 = rootfs（squashfs + f2fs overlay）
- 写 eMMC 必须使用分区设备（`/dev/mmcblk0pN`），绝不用整盘
- U-Boot 环境：`bootcmd=mtkautoboot`、`button_cmd_0_name=reset`、`button_cmd_0=httpd`
- 若 U-Boot 无法启动，需通过 TTL 串口（3.3V，115200 8N1）使用 `mtk_uartboot` RAM boot 恢复

## 免责声明

刷机有变砖风险，请自行评估后再操作。本项目按现状提供，不保证任何功能在您的设备上可用。
