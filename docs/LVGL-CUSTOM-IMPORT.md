# E87N 屏幕：自定义 LVGL 导入 + 指标接口

面向"把自己的 LVGL 界面放到 E87N 屏幕上，并且要显示温度/网速"的场景。

---

## 1. 数据接口（三种，任选）

屏幕上的数据只有**一个来源**：`/usr/sbin/e87n-metrics` 每秒采样一次，写到
`/var/run/e87n/metrics.json`。它和内置 UI 的「下载/上传/温度/风扇」是同一份算法
（`/proc/net/dev` 差分、`thermal_zone0`、`hwmon pwm1`），所以数值一定对得上。

### 1.1 JSON 文件（推荐，最省事）

```sh
cat /var/run/e87n/metrics.json
```
```json
{"ok":1,"ts":1787843962,"uptime":727,
 "temp_c":49,"temp_ok":1,
 "cpu_pct":5,"ram_pct":15,"disk_pct":3,
 "fan_pwm":109,"fan_pct":42,"fan_mode":"auto",
 "rx_bps":596,"tx_bps":686,"net_iface":"br-lan",
 "wan_ip":"","wan6":"","lan_ip":"192.168.100.1","lan6":"fdb6:a5a1:cf45::1",
 "backlight":"on","display_page":"4"}
```

- 文件是**原子替换**（写 `.tmp` 再 `mv`），不会读到半截内容。
- 1 秒刷新一次；建议你的程序也按 1 Hz 读。
- 单位：`rx_bps`/`tx_bps` 是 **字节/秒**（和屏幕上的 "B/s" 同源，不是 bit）。
- 数值未知时为 `-1`，字符串未知时为 `""`。
- 想换统计接口：`uci set e87n-display.global.iface=eth0 && uci commit e87n-display`

### 1.2 ubus

```sh
ubus call e87n status        # 返回同样的 JSON
```
对象由 `/usr/libexec/rpcd/e87n` 提供（rpcd exec 插件），LuCI 里也已授权
（`luci-app-e87n` 的 acl 增加了 `e87n` 的 `status`）。

### 1.3 C SDK（给 C/C++ 的 LVGL 程序）

源码在 `docs/sdk/`，固件里也带了一份：`/usr/share/e87n-sdk/`。无第三方依赖。

```c
#include "e87n_metrics.h"

static void tick_cb(lv_timer_t *t)
{
    e87n_metrics_t m;
    if (e87n_metrics_read(&m) != 0)
        return;
    lv_label_set_text_fmt(lv_obj_get_child(scr, 0), "%d°C", m.temp_c);
    lv_label_set_text_fmt(lv_obj_get_child(scr, 1), "↓ %lu B/s", m.rx_bps);
    lv_label_set_text_fmt(lv_obj_get_child(scr, 2), "↑ %lu B/s", m.tx_bps);
}

void ui_init(void)
{
    /* ... 建界面 ... */
    lv_timer_create(tick_cb, 1000, NULL);
}
```

完整可编译示例：`docs/sdk/example_custom_page.c`。

### 1.4 字段表

| 字段 | 类型 | 说明 |
|---|---|---|
| `ts` | int | 采样时间戳 |
| `uptime` | int | 开机秒数 |
| `temp_c` | int | 温度 °C（`<0` 表示无效） |
| `temp_ok` | 0/1 | 温度是否有效 |
| `cpu_pct` / `ram_pct` / `disk_pct` | int | 占用率 % |
| `fan_pwm` / `fan_pct` | int | 风扇 PWM(0-255) / 百分比(0-100) |
| `fan_mode` | string | `auto` / `manual` / `off` |
| `rx_bps` / `tx_bps` | ulong | 下载/上传 字节/秒 |
| `net_iface` | string | 统计接口（默认 `br-lan`） |
| `wan_ip` / `wan6` | string | WAN v4 / v6（未拨号时为空） |
| `lan_ip` / `lan6` | string | LAN v4 / v6 |
| `backlight` | string | `on` / `off` / `unknown` |
| `display_page` | string | 当前页 1-4 / `cycle` |

控制类操作（开关屏、切页、风扇）继续用现成的 `screen-ctl` / `fanctl` / CGI，
不建议自定义程序直接写 GPIO。

---

## 2. 自定义 LVGL 导入（三条路径，按需求选）

### 路径 A：只换文字/图片（不用编译）

- 文字：`/etc/config/e87n-display` 里 `list custom_text '...'`，或 LuCI 屏幕页提交。
- 图片：LuCI 屏幕页的"导入图片"，浏览器端转 RGB565 后 `screen-ctl raw` 显示。

适合"换个 logo / 加两行字"。

### 路径 B：整屏自己画（源码级导入，推荐做正经自定义 UI）

内置 UI 是 SquareLine/LVGL Editor 风格的导出（`package/e87n-display/src/lib/ui/`
下的 `ui_init()` + `ui_Screen1..4`）。导入自定义 UI 的契约只有三条：

1. 提供 `void ui_init(void)`，内部创建并加载你的 screen；
2. 你的 screen 用 `lv_screen_active()` 或 `lv_disp_load_scr()` 加载；
3. 需要数据就按 §1 读（**不要**直接解析 `/proc`）。

把导出的 `ui/` 整个替换进 `package/e87n-display/src/lib/ui/`，然后构建
**只编这个包**（比整机快得多）：

```sh
# 本地/CI 均可；首次需要先 prepare 过一次
make package/e87n-display/compile V=s
# 产物: build_dir/target-*/e87n-display/e87n-display  →  scp 到 /usr/bin/
```

> 注意：`ui.c` 里的 `ui_init()` 由 LVGL Editor 生成时通常已经存在；
> 如果你是手写，直接自己写 `ui_init()` 即可。

### 路径 C：运行时上传（不重编固件）

历史上实现过"上传 aarch64 ELF 直接替换显示程序"（commit `48c2e21`），
当前 `screen.js` 只保留了图片导入。要恢复 ELF 上传需要：

- 上传后校验 ELF magic + `EM_AARCH64`；
- 部署到 `/usr/bin/e87n-display.custom`，`/etc/init.d/e87n-display` 优先启动它；
- 失败自动回退到内置程序（避免上传坏的 ELF 把屏搞死）。

需要的话可以加回来（CGI 里 `import_app` + LuCI 一个上传控件，约 100 行）。

---

## 3. 注意

- 屏是 **428×142 RGB565**，`/dev/fb0`，driver 为 `fb_nv3007`（内建，非模块）。
- 背光：GPIO524，**低电平亮**；优先用 `/usr/sbin/screen-ctl on|off`。
- 自定义程序崩溃不会影响指标守护（`e87n-metrics` 独立进程），SSH 进去
  `/etc/init.d/e87n-display restart` 即可恢复。
- 指标守护默认随开机启动（`/etc/uci-defaults/98-e87n-metrics`）。
