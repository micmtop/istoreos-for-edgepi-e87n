# 迁移到 iStoreOS 25.12（内核 6.12）

本文是基于对上游仓库的**静态核查**结论写的迁移方案，不是猜测。核查日期：2026-10-18。

---

## 1. 核查到的事实

| 项 | 24.10（当前） | 25.12（目标） |
|---|---|---|
| 内核 | 6.6 | **6.12**（`target/linux/mediatek/Makefile: KERNEL_PATCHVER`） |
| `mt7987a.dtsi` | 上游**没有**，我们自己带 | 上游**有**（但只有 484 B，内容很少，仍需核对是否够用） |
| MT7987 相关补丁 | 我们自己带 360/361/740/750/751/752/821/831/844 | **上游全都有**（同名同号） |
| 733-*（MediaTek PHY 重构 + 2.5G 驱动基础） | 需要（752 依赖它） | **已上游化，不需要** |
| fbtft | `drivers/staging/fbtft` | 仍在 `drivers/staging/fbtft`（v6.12 确认） |
| 分支 | `istoreos-24.10` | `istoreos-25.12` |

结论：**核心的 MT7987 支持（eth / 2.5G PHY / pinctrl / clk / thermal / cpufreq / pwm / PCS）
在 25.12 已经是上游补丁**，我们那份 6.6 的移植工作可以整体丢掉，只需要保留：

1. E87N 板级 DTS；
2. `999-nv3007-fbtft.patch`（屏幕驱动，不是上游）；
3. 可能还需要 2.5G PHY 的两个运行时修复（见 §4 的风险项）。

---

## 2. 需要改的地方（按顺序）

### 2.1 CI 分支

`build.yml` 已加了 `branch` 输入（默认 `istoreos-24.10`）：

```bash
gh workflow run build.yml -R micmtop/istoreos-for-edgepi-e87n -f branch=istoreos-25.12
```

`apply.sh` 里的补丁目录也要跟着变（见 2.2）。

### 2.2 `apply.sh`：补丁按“上游优先，缺了才补”

现在是把 `files/.../patches-6.6/*.patch` 全量 `cp -f` 进目标目录。25.12 已经有同号补丁，
**同名文件会互相覆盖/冲突**。改成：

```sh
TP="$MT/patches-6.12"           # 按 KERNEL_PATCHVER 选择
mkdir -p "$TP"
for p in "$ROOT"/files/target/linux/mediatek/patches-6.6/*.patch; do
    base=$(basename "$p")
    num=${base%%-*}
    case "$num" in
        999) ;;                                  # 屏幕驱动：永远用我们的
        *)
            if ls "$TP/$num"-*.patch >/dev/null 2>&1; then
                echo "skip $base (upstream 25.12 already has $num-*)"
                continue
            fi
            ;;
    esac
    cp -f "$p" "$TP/"
done
```

这样：
- `360/361/740/750/751/752/821/831/844` → 命中上游，自动跳过；
- `999-nv3007-fbtft` → 始终拷贝；
- 我们的 `753/754/755`（2.5G PHY 的锁/LED 极性/MMD 延时修复）→ 先**不**拷，见 §4。

### 2.3 DTS

- 板级 `mt7987a-edgepi-e87n.dts` 继续用我们的（已按实机改过：双 M.2、无 WiFi、无 WPS、
  LED 角色）。
- `mt7987.dtsi / mt7987a.dtsi / mt7987b.dtsi`：25.12 自带一份（484 B，很小），
  **先不要覆盖**；改成“目标缺失才拷贝”，并核对上游那份是否包含
  `ethernet@15100000`、`pcie@11280000/11290000`、`ssusb`、`pwm`、`thermal` 等节点。
  如果上游 dtsi 不完整，再回退到“用我们的 dtsi 覆盖”。

### 2.4 内核配置注入

`apply.sh` 末尾往 `include/kernel-defaults.mk` 注入 `.config.set` 的那段依赖锚点
`$(call Kernel/SetNoInitramfs)`。25.12 若改了这段，脚本会**显式报错**（不是静默失败），
按报错调整锚点即可。

`e87n.config` 里 `CONFIG_TARGET_mediatek_filogic_DEVICE_edgepi_e87n=y` 等目标符号不变；
个别包名（例如 flow offload 相关）若有改名，`make defconfig` 会丢弃并由 CI 门禁暴露。

### 2.5 屏幕补丁 999

fbtft 仍在 `drivers/staging/fbtft`，新文件 hunk 可以照用；风险在
`Kconfig` / `Makefile` 的上下文行（25.12 可能调整过条目顺序）。若 `quilt` 报
`malformed` 或上下文不匹配，按新文件重新生成 hunk 即可（保持等行数替换的习惯）。

---

## 3. 验证顺序（每步都省时间）

1. `gh workflow run build.yml -f branch=istoreos-25.12`，只看前几个门禁：
   `Prepare kernel (apply MT7987 patches via quilt)` 是否通过（补丁冲突会在这里炸）。
2. 通过后再看 `CONFIG_FB_TFT_NV3007=y` 与 `fb_nv3007.o COMPILED` 门禁。
3. 出固件后先刷 **p4** 验证：`dmesg` 里应有
   `MediaTek MT7987 2.5GbE PHY ... Firmware loading/trigger ok`、
   `fb_nv3007 frame buffer, 428x142`。
4. 再跑 `sh tools/acceptance.sh`，重点看：两个 2.5G PHY 绑定、HNAT/flow offload、
   PCIe 控制器、屏幕、LED、风扇。

---

## 4. 已知风险（需要实机才能确认）

| 风险 | 说明 | 应对 |
|---|---|---|
| **2.5G PHY LED 回调** | 24.10 上我们遇到过：`mtk_phy_leds_state_init()` 无条件调用 `phydev->drv->led_hw_control_get()`，而 MT7987 驱动条目没填 → 空指针 panic。25.12 的 `752` 里**仍然没有** `led_hw_control_get/led_brightness_set`，但 6.12 的 `mtk-phy-lib.c` 是否已加判空需要再看 | 若 panic，复用我们的 752 修复（补 5 个 LED 回调） |
| **PHY 固件初始化时序** | 我们的 `753`（固件初始化加锁）与 `755`（MMD 写延时）是实机调出来的 | 若 PHY 报 `Firmware loading failed` 或链路不稳，逐个补回 |
| **LED 极性** | 我们的 `754` 去掉 `MTK_PHY_LED_ON_POLARITY` | 若 WAN/2.5G 灯反向，补回 |
| **上游 dtsi 不完整** | 25.12 的 `mt7987a.dtsi` 只有 484 B | 用我们的 dtsi 覆盖，或补齐节点 |
| **包名/配置改名** | 25.12 与 24.10 的包集合有差异 | 以 CI 的 `make defconfig` + 门禁报错为准逐条修 |

---

## 5. 不建议做的事

- 不要整棵换到 ImmortalWrt / 6.18：那会丢掉 iStoreOS 的工具链、包源和 LuCI 集成，
  与“同步 iStoreOS 大版本”不是一回事。
- 不要保留 24.10 的 733-* 系列补丁：25.12 已经上游化，硬塞会冲突。
- 不要在 6.12 上继续沿用“整份 733-11 生成的 .c 上干跑 752”的老办法：上游文件结构变了。

---

## 6. 迁移结果（2026-10-18，实机验证）

已完成。从 `e87n.config` 到 `files/` 原样搬到 `istoreos-25.12` 分支即可用，
`apply.sh` 的“上游优先”逻辑在 6.12 上只补了 `320-hwrng` / `790-rtl8221-led` /
`999-nv3007` 三个补丁，其余跳过。

| 项 | 结果 |
|---|---|
| 版本 | `iStoreOS 25.12.5 r0-96c7500`（`DISTRIB_TARGET=mediatek/filogic`） |
| 内核 | `6.12.94 #0 SMP Thu Oct 15 11:31:25 2026` |
| p4 FIT | `4,557,960` 字节，sha256 `55abe763…a539`，写入后回读一致 |
| p3(FIP) | 全程未动，sha256 仍为 `ad1ff3c9…b60f` |
| 自检 | `tools/acceptance.sh` → **41 passed / 0 failed** |

自检里和 6.12 相关的关键项：

- **两个 2.5G PHY 都正常绑定**：`mdio-bus:03 RTL8221B-VB-CG 2.5Gbps (C45)`、
  `mdio-bus:0f MediaTek MT7987 2.5GbE PHY`，没有 `Firmware loading failed`。
- **HNAT / 卸载**：`nf_flow_table`、`nf_flow_table_inet`、`nft_flow_offload` 齐全，
  `flow_offloading=1` / `flow_offloading_hw=1`，PPE 调试节点可见。
- **两个 PCIe 控制器都已启用**（`pcie@11280000` + `pcie@11290000`，都是 `okay`），
  空槽位各一条 `link down`，属正常。
- **屏幕**：`fb_nv3007 frame buffer, 428x142, 118 KiB, fps=100, spi0.0 at 52 MHz`，
  `e87n-display` 与自定义主题都能跑。
- **LED**：`green:status`（pio4）/ `amber:wan`（pio3）按新语义注册。
- **风扇**：`fan-control` 自动曲线，52–55 °C 时 PWM 10（3 %）。

### 6.1 风险项结论

| 风险 | 实测 |
|---|---|
| 2.5G PHY LED 回调空指针 panic | **未复现**，6.12 启动无 panic；753/754/755 都没装 |
| PHY 固件初始化时序 | **正常**，固件加载无报错 |
| LED 极性 | 正常（sys 灯亮、WAN 灯灭） |
| 上游 `mt7987a.dtsi` 不完整 | 仍用我们自己的 dtsi（`apply.sh` 只在缺失时拷，25.12 那份太小不能用） |

### 6.2 迁移后顺带修掉的问题

- **`3e1aecb` 误删了板级 DTS 的 nv3007 屏节点和 `pwm_fan_pins`/`pwm_backlight_pins`**，
  导致 `dtc` 报 `phandle_references ERROR` 并中断整机编译。已按 `48c2e21` 的已知good版本
  重建 DTS，并新增 `tools/check-dts.sh` 在编译前 3 秒内校验标签引用与关键节点，
  同时挂进 `build.yml` / `kernel-only.yml`。
- **CI 的 `Verify firmware output` 写死了 `linux-6.6.144`**，6.12 产物会被误判 FATAL。
  已改成 `linux-[0-9]*` 通配。
- **eMMC factory 分区（p2）在本机是全 0**，`mmc-card/block-partition` 那套 nvmem 声明
  没有数据可读，反而在 6.12 触发 `sysfs: cannot create duplicate filename .../mmcblk0p2/mmcblk0p2`
  的 WARN。已从 DTS 移除该块（MAC 本来就走 OpenWrt 的随机分配）。
