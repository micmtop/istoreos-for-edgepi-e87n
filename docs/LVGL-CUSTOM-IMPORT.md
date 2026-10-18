# E87N 屏幕：主题导入 + 指标接口

两条主线：

1. **指标接口** —— 屏幕上的温度/网速等数据，自定义程序直接读，不用自己解析 `/proc`。
2. **主题导入** —— LuCI 里上传主题包，立刻出现在"显示页面"下拉里，选中就生效。

---

## 1. 指标接口（三种，任选）

唯一数据源：`/usr/sbin/e87n-metrics` 每秒采样，原子写入 `/var/run/e87n/metrics.json`。
与内置 UI 同源（`/proc/net/dev` 差分、`thermal_zone0`、`hwmon/pwm1`），数值必然一致。

### 1.1 JSON 文件（推荐）

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
 "backlight":"on","display_page":"4",
 "clients":3,"saying":"与其临渊羡鱼，不如退而结网。"}
```

- 原子替换（写 `.tmp` 再 `mv`），不会读到半截；1 秒一次。
- `rx_bps`/`tx_bps` 是 **字节/秒**（和屏幕 "B/s" 同源）。
- 未知数值为 `-1`，未知字符串为 `""`。
- 换统计接口：`uci set e87n-display.global.iface=eth0 && uci commit e87n-display`

### 1.2 ubus

```sh
ubus call e87n status
```
（`/usr/libexec/rpcd/e87n` 提供，LuCI ACL 已授权 `e87n status`）

### 1.3 C SDK

`docs/sdk/e87n_metrics.{h,c}`，固件里也装到 `/usr/share/e87n-sdk/`。无第三方依赖。

```c
#include "e87n_metrics.h"

e87n_metrics_t m;
if (e87n_metrics_read(&m) == 0) {
    lv_label_set_text_fmt(lbl_temp, "%d°C", m.temp_c);
    lv_label_set_text_fmt(lbl_down, "↓ %lu B/s", m.rx_bps);
}
```

可编译示例：`docs/sdk/example_custom_page.c`。

### 1.4 字段表

| 字段 | 类型 | 说明 |
|---|---|---|
| `ts` / `uptime` | int | 采样时间戳 / 开机秒数 |
| `temp_c` / `temp_ok` | int | 温度 °C（`<0` 无效） / 是否有效 |
| `cpu_pct` / `ram_pct` / `disk_pct` | int | 占用率 % |
| `fan_pwm` / `fan_pct` | int | PWM 0–255 / 百分比 0–100 |
| `fan_mode` | string | auto / manual / off |
| `rx_bps` / `tx_bps` | ulong | 下载/上传 字节/秒 |
| `net_iface` | string | 统计接口（默认 br-lan） |
| `wan_ip` / `wan6` / `lan_ip` / `lan6` | string | 地址（未拨号时为空） |
| `backlight` | string | on / off / unknown |
| `display_page` | string | 1-4 / cycle / theme:<id> |
| `clients` | int | 在线设备数（DHCP 租约 + ARP 按 MAC 去重） |
| `saying` | string | 每日一言（uapis.cn，缓存；离线时为内置兜底句） |

控制类（开关屏/切页/风扇）用 `screen-ctl`、`fanctl`、CGI，不建议自定义程序直接写 GPIO。

---

## 2. 主题导入（LuCI 里上传，自动进"显示页面"列表）

### 2.1 主题包格式

`tar.gz`，根目录（或唯一子目录）内含：

```
theme.json      （必需）{"name":"我的主题","desc":"可选说明"}
app             （二选一）aarch64 ELF —— type=app，程序自己画屏
frame.raw       （二选一）428x142 RGB565 整帧，121552 字节 —— type=image，静态画面
font.ttf        （可选）随主题一起装的字体，app 自行加载（见 2.5）
```

- `app` 必须是 **aarch64 ELF**（安装时会校验 ELF magic + `EM_AARCH64`）。
- `frame.raw` 必须正好 `121552` 字节（安装时校验）。
- 有 `app` 就按 app 运行；否则按 image 显示。
- `font.ttf` 没装也可以，主题自己决定是否要用；装了就在主题目录里，
  app 用 `argv[0]` 推出同目录路径即可加载（主题目录固定为
  `/etc/e87n-display/themes/<id>/`）。

### 2.2 安装 / 使用

- **LuCI**：屏幕控制 → 主题 → 选择 `.tar.gz` → "导入主题"。
  导入成功后主题立刻出现在上方"显示页面"下拉（`主题: <name> [app|image]`），选中 → 应用即可。
- **CLI**：
  ```sh
  e87n-theme install /tmp/mytheme.tar.gz [id]   # id 默认取文件名
  e87n-theme list
  uci set e87n-display.global.page=theme:<id>
  uci commit e87n-display
  /etc/init.d/e87n-display restart
  e87n-theme remove <id>
  ```

主题存放在 `/etc/e87n-display/themes/<id>/`（overlay，重启保留）。

运行时行为：切到主题会先停掉内置 UI（`killall e87n-display`），把 `/dev/fb0` 让出来；
切回 1-4/cycle 时恢复正常。主题目录被删但 `uci page` 还指向它时，启动会自动回退到第 1 页。

### 2.3 做一个 `type=app` 主题

app 运行在 428×142 的 `/dev/fb0` 上，必须自己建 LVGL 显示（或用任意方式写 fb）：

```c
#include "lvgl.h"
#include "e87n_metrics.h"

int main(void)
{
    lv_init();
    lv_display_t *d = lv_linux_fbdev_create();
    lv_linux_fbdev_set_file(d, "/dev/fb0");
    /* 建界面 + 1 Hz 定时器读 e87n_metrics_read() */
    for (;;) { lv_timer_handler(); usleep(5000); }
}
```

编译要点（设备是 **musl + aarch64**）：

- 用 **OpenWrt SDK**（与固件同版本）或直接在 `package/` 下加包；
- LVGL 需要一起编进去（设备上没有 `liblvgl.so`），参考 `package/e87n-display/src/CMakeLists.txt`；
- 依赖 `+libstdcpp`（如果用了 C++/LVGL 的 C++ 部分）。

示例主题：**`themes/aurora/`**（完整可用，含 CMake、`lv_conf.h`、SDK 和打包脚本），
建议直接拷一份改。

#### 用 CI 编译（不用本机装工具链）

```bash
# themes/<name>/ 放好 main.c 后
gh workflow run theme-build.yml -R micmtop/istoreos-for-edgepi-e87n -f theme=<name>
gh run list -R micmtop/istoreos-for-edgepi-e87n -w "E87N Theme Build" -L 1
gh run download <run-id> -R micmtop/istoreos-for-edgepi-e87n -n e87n-theme-<name>
# 得到 theme-<name>.tar.gz -> LuCI「屏幕控制 → 主题」导入
```

首次（toolchain 缓存空）约 20 分钟，之后 **4–6 分钟**。

#### 本地编译

```bash
cd themes/aurora
CC=/path/to/aarch64-openwrt-linux-musl-gcc ./build.sh   # 出 aurora.tar.gz
```

### 2.4 做一个 `type=image` 主题（不用编译）

```sh
# 1) 生成 428x142 RGB565 整帧（不传图片则出彩条测试图）
python3 docs/sdk/make-frame.py frame.raw
python3 docs/sdk/make-frame.py frame.raw my.png   # 用自己的图（需 Pillow）

# 2) 写 theme.json + 打包
printf '{"name":"我的主题"}
' > theme.json
tar -czf mytheme.tar.gz theme.json frame.raw

# 3) LuCI 导入，或命令行
e87n-theme install mytheme.tar.gz
```

静态画面不会刷新（没有实时数据）。要显示温度/网速就做 `type=app`。

---

### 2.5 中文显示（字体打包）

内置的 `lv_font_source_han_sans_sc_16_cjk` 只带 1338 个常用字，`临渊羡鱼`、`在线`
这类字会显示成方框。要显示完整中文，把字体裁好塞进主题包：

```sh
# 1) 裁一个覆盖 GB2312 全集的子集（7542 字，约 1.2 MB）
python -m fontTools.subset wqy-microhei.ttc     --text-file=gb2312.txt     --output-file=themes/mine/font.ttf     --layout-features='*' --no-hinting

# 2) 主题 lv_conf.h 里打开 Tiny TTF
#    #define LV_USE_TINY_TTF 1

# 3) 运行期加载（main.c）
#include "lvgl.h"                       /* 已包含 lv_tiny_ttf.h */

static lv_font_t *font;

static void load_font(const char *argv0)
{
    char path[512];
    FILE *f;
    long n;
    void *buf;

    snprintf(path, sizeof(path), "%.*s/font.ttf",
             (int)(strrchr(argv0, '/') - argv0), argv0);
    if (!(f = fopen(path, "rb")))
        return;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = malloc((size_t)n);
    fread(buf, 1, (size_t)n, f);
    fclose(f);
    font = lv_tiny_ttf_create_data(buf, (size_t)n, 16);   /* 16px */
}
```

- 内存占用：字体文件原样留在内存里，1.2 MB 字体约等于 1.2 MB RSS；设备是 1 GB，够用。
- 4 MB 以上的字体不建议塞主题包（安装时要解压进 overlay）。
- 没有 `font.ttf` 时主题应回退到内置 CJK 字体，别让程序崩掉。
- 只需几个字的话，用 `--text=在线临渊羡鱼` 直接生成几十 KB 的极小字体也够。

## 3. 其他导入方式（保留）

- **UCI 自定义文本**：`/etc/config/e87n-display` 的 `list custom_text`（显示在 Screen1 顶部）。
- **图片直接上屏**：LuCI"导入自定义画面"，浏览器端转 RGB565 后 `screen-ctl raw`（一次性，不保存为主题）。
- **源码级替换 UI**：把 SquareLine/LVGL Editor 导出替换 `package/e87n-display/src/lib/ui/`，
  契约是 `ui_init()`；`make package/e87n-display/compile` 即可，不必整机重编。

## 4. 注意

- 屏：428×142 RGB565，`/dev/fb0`，驱动 `fb_nv3007`（内建）。
- 背光：GPIO524，低电平亮；用 `screen-ctl on|off`。
- 主题 app 崩溃不影响指标守护（独立进程）；SSH 进去
  `uci set e87n-display.global.page=1 && /etc/init.d/e87n-display restart` 即可恢复。
- 指标守护开机自启（`/etc/uci-defaults/98-e87n-metrics`）。
