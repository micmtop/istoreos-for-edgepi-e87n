# 屏幕修复验收记录（NV3007）

日期：2026-10-18
结论：**屏已修复并实机验收通过**（四色测试图 + 内置 UI 均正确显示，背光正常）。

---

## 1. 修复内容

驱动 `fb_nv3007` 按厂商内核反汇编结果重建（见 `re/NV3007-OEM-RE.md` 与
`docs/` 中的交叉验证记录）：

| 项 | 修复前 | 修复后 |
|---|---|---|
| 初始化序列 | ArduinoGFX 2.79" 变体（41/84 条值不同） | 厂商内核 84 条逐条一致 |
| MADCTL(0x36) rotate=270 | `0x20`（仅 MV） | `0xA0`（MY\|MV，由 `set_var` 写） |
| 窗口偏移 | 参数化、每次重写 0x36 | `rotate` 感知：270° 只给 y 轴 +12 |
| gamma | init 内联 | `set_gamma` 回调（值不变，顺序对齐厂商） |

DTS 未改（早已与厂商 DTB 逐字段一致：rotate=270 / fps=100 / 142×428 / GPIO10,11 / 52MHz）。

## 2. 构建

- run `39085115016`，commit `bdd11b2`
- `e87n-istoreos-firmware(3).zip` sha256 `7e165f83e810962daa478b4ec9ac0bea54b62c448150cf963cb32805e29bffa5`
- `sysupgrade.bin` sha256 `7c544d16adb61fbfd424eb200559271cc15617271c4cdec33833229ede803aba`
- p4 kernel FIT sha256 `7f9fbe84ce3609f257475cfc84c2b0744f5da5c93775b7875f6cd4a9857eba3b`（4,413,216 B）

## 3. 编译产物校验（对机器码，不对源码）

从 `sysupgrade.bin` 取出 p4 FIT → lzma 解出内核 → 重新反汇编 `fb_nv3007`：

| 检查 | 结果 |
|---|---|
| `init_display` 的 84 条 `write_reg` | 与厂商内核**逐条完全相同** |
| `set_var` rotate=270 分支 | `mov w3,#0xA0; orr w3,w3,w5,lsl#3` |
| `set_addr_win` | 270°：y `+0xc`；0/90°：对应轴 `+0xe`；0x2A/0x2B/0x2C 齐全 |
| gamma 串 / `gamma_num`,`gamma_len` | `00 02 04 07 05 02 21 23 3A 08 13 13 29 31 0F` ×2，2×15 |
| `fbtft_display` | 428/142/8/8, bpp=16 |
| FIT 内 DTB `display@0` | 与厂商 DTB 逐字段一致 |

## 4. 实机验收

刷写方式：仅写 p4（`dd if=kernel.fit of=/dev/mmcblk0p4`），回读校验一致，p3 未动。

- p3 (FIP)：`ad1ff3c9c3148167775116e32f4d933b046c085b1cc57a35853413892b97b60f`（刷前/刷后一致）
- p4：写入前 `2c22764e…e1eec`，写入后前 4,413,216 字节 = `7f9fbe84…7eba3b`
- 重启后内核：`Linux 6.6.144 #0 SMP Thu Oct 15 12:50:05 2026`
- dmesg：`fb_nv3007 frame buffer, 428x142, 118 KiB video memory, fps=100, spi0.0 at 52 MHz`
- `/sys/class/graphics/fb0/name` = `fb_nv3007`，`virtual_size` = `428,142`，bpp=16
- 无 spi/fb 相关错误

### 视觉确认（人工）

- 写入四色测试图（3px 黄框 + 左上红/右上绿/左下蓝/右下白 + 左上品红块 + 中央黑十字）：
  **方位、边界、颜色全部正确**，无偏移/裁切/镜像。
- 背光：**正常点亮**。
- 恢复内置 UI：帧缓冲内容正确（`_fw3/ui_live.bmp`），且连续快照内容变化 → 正常刷新。

## 5. 遗留

- 背光控制仍是 GPIO524 直控（与原厂 `start_display` 一致），未做 `/sys/class/backlight`。
- 页面切换/轮播未逐一目视验收（仅第 3 页与四色图）。
