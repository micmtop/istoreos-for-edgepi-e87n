# EdgePi E87N · iStoreOS (这版有巨大问题别用)

给 EdgePi E87N 路由器编译的 iStoreOS 固件。仓库里放设备树、内核补丁、软件包和 CI 配置，
固件由 GitHub Actions 产出。

当前基线 iStoreOS 25.12.5，内核 6.12.94。成品在
[Releases](https://github.com/micmtop/istoreos-for-edgepi-e87n/releases)。

## 硬件

| 项 | 规格 |
|---|---|
| SoC | MediaTek MT7987A，4 核 Cortex-A53 |
| 存储 | 1 GiB DDR4，8 GB eMMC |
| 分区 | p1 u-boot-env、p2 factory、p3 fip、p4 kernel、p5 rootfs |
| 网口 | eth0 外置 RTL8221B 2.5G，eth1 内置 MT7987 2.5G |
| 扩展 | 两个 M.2 2230，各挂一个 PCIe 控制器；一个 USB 3.2 A 口 |
| 屏幕 | NV3007，428×142，SPI，背光 GPIO524 |
| 其它 | PWM 风扇、双色 LED、reset 键、串口 115200 8N1 |
| 无线 | 没有 |

## 系统里有什么

- iStoreOS 25.12.5，内核 6.12.94
- 双 2.5G 网口，VLAN、PPPoE、IPv6；硬件 NAT 走 mtk_eth_soc 的 PPE 加 nft flow offload
- iStore 商店、网络向导、OTA 预装
- 屏幕 4 个内置页面，可导入自定义主题；中文字体随固件装在 `/usr/share/e87n/font.ttf`
- 风扇按温度曲线调 PWM，曲线在 LuCI 里拖

屏幕、主题包格式和指标接口见 `docs/LVGL-CUSTOM-IMPORT.md`。

## 构建

| Workflow | 用途 | 耗时 |
|---|---|---|
| E87N Build | 整机固件，push 到 main 自动触发 | 1.5 h |
| E87N Kernel Only | 只编内核并生成 FIT | 40 min |
| E87N Theme Build | 只编 `themes/<名字>/` | 20 min |
| Publish firmware | 把某次构建的产物转存成 Release | 1 min |
| E87N Config Diag | 只跑 feeds 和 defconfig，查包为什么没进固件 | 3 min |

```bash
gh workflow run build.yml -R micmtop/istoreos-for-edgepi-e87n
gh workflow run kernel-only.yml -R micmtop/istoreos-for-edgepi-e87n
gh workflow run theme-build.yml -R micmtop/istoreos-for-edgepi-e87n -f theme=aurora
gh workflow run publish.yml -R micmtop/istoreos-for-edgepi-e87n -f run_id=<run id> -f tag=<tag>
```

`apply.sh` 把 `files/` 覆盖进 iStoreOS 源码树，包括设备树、内核补丁、E87N 设备定义
和内核 Kconfig 符号。补丁按上游优先装，上游同号补丁存在就跳过我们的；
6.12 专用的放 `files/target/linux/mediatek/patches-6.12/`。

改过板级 DTS 先跑本地校验，3 秒出结果：

```bash
sh tools/check-dts.sh
```

## 本地构建

本机需要 Linux 或 WSL2。WSL 里把仓库放在 `/home` 下，不要放 `/mnt/c`，
否则编译慢，还可能因为权限和大小写问题失败。磁盘留 30 GB，内存 16 GB 以下把 `-j` 调小。

```bash
# 1. 依赖，Debian 或 Ubuntu
sudo apt install build-essential clang flex bison g++ gawk gcc-multilib   g++-multilib gettext git libncurses-dev libssl-dev python3-distutils   python3-setuptools rsync unzip zlib1g-dev file wget qemu-utils libelf-dev   jq ccache

# 2. 拉仓库和 iStoreOS 源码，源码要放在仓库里的 istoreos/
git clone https://github.com/micmtop/istoreos-for-edgepi-e87n.git e87n
cd e87n
git clone -b istoreos-25.12 --depth 1 https://github.com/istoreos/istoreos.git istoreos

# 3. 加两个 Linkease feed，商店和网络向导来自这里
cd istoreos
printf 'src-git nas https://github.com/linkease/nas-packages.git;linkeasefull\n' >> feeds.conf.default
printf 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main\n' >> feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a
cd ..

# 4. 打补丁、套配置。apply.sh 负责设备树、内核补丁和自定义软件包
bash apply.sh
cd istoreos
cp ../e87n.config .config
make defconfig

# 5. 编译。8 核首次约 45 分钟
make CCACHE=y -j$(nproc)
```

产物在 `istoreos/bin/targets/mediatek/filogic/`，文件名是
`istoreos-mediatek-filogic-edgepi_e87n-squashfs-sysupgrade.bin`。

只改内核不刷整机时，编到内核 FIT 就够：

```bash
make CCACHE=y -j$(nproc) target/linux/prepare
make CCACHE=y -j$(nproc) target/linux/compile
make CCACHE=y -j$(nproc) target/linux/install
```

FIT 在 `build_dir/target-*/linux-mediatek_filogic/edgepi_e87n-kernel.bin`。

`make defconfig` 不会报错，但依赖不满足的包会被直接丢掉。改过 `e87n.config` 后先确认
这几个还在 `.config` 里：

```bash
grep -E 'PACKAGE_(luci-app-store|luci-app-quickstart|quickstart)=y' .config
```

## 刷机

Release 里有两个文件：`squashfs-sysupgrade.bin` 是整机升级包，
`edgepi_e87n-kernel-6.12.94.fit` 是单独的内核，另有 `SHA256SUMS`。
国内下载慢时在前面加镜像前缀。

```bash
curl -LO https://gh-proxy.com/https://github.com/micmtop/istoreos-for-edgepi-e87n/releases/download/<tag>/istoreos-mediatek-filogic-edgepi_e87n-squashfs-sysupgrade.bin
sysupgrade istoreos-mediatek-filogic-edgepi_e87n-squashfs-sysupgrade.bin
```

平台的 `emmc_do_upgrade` 按分区名写盘，整机升级会同时更新 p4 和 p5。
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

## 自检

设备上直接跑，只读，不改状态：

```bash
sh tools/acceptance.sh
```

检查 overlay、eMMC 分区、两个 PHY 的绑定、HNAT 和 flow offload、风扇是否跟随曲线、
LED、USB、两个 PCIe 控制器、屏幕、商店和网络向导。当前版本 45 项全过。

## 目录

```
apply.sh                                  把 files/ 应用进 iStoreOS 源码树
e87n.config                               包选择和内核符号
files/target/linux/mediatek/dts/          MT7987 dtsi 和 E87N 板级 DTS
files/target/linux/mediatek/patches-6.6/  6.6 用补丁
files/target/linux/mediatek/patches-6.12/ 6.12 专用补丁
package/e87n-display                      LVGL 显示程序，装系统字体和演示主题
package/e87n-tools                        风扇、背光、指标、主题管理，纯脚本
package/luci-app-e87n                     LuCI 页面和 CGI
package/mt7987-2p5g-phy-firmware          内置 2.5G PHY 固件
themes/aurora                             演示主题源码，构建时一起编译
docs/                                     主题与指标接口文档、SDK、迁移记录
tools/acceptance.sh                       硬件和功能自检
tools/check-dts.sh                        板级 DTS 校验
```
