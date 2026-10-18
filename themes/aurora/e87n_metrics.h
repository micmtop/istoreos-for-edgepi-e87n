/*
 * e87n_metrics.h - E87N 屏幕指标接口（给自定义 LVGL 程序用）
 *
 * 数据来源：/var/run/e87n/metrics.json（由 e87n-metrics daemon 每秒刷新）
 * 也可用 ubus:  ubus call e87n status
 *
 * 用法（不需要任何第三方库）：
 *
 *   #include "e87n_metrics.h"
 *
 *   e87n_metrics_t m;
 *   if (e87n_metrics_read(&m) == 0) {
 *       lv_label_set_text_fmt(label_temp, "%d°C", m.temp_c);
 *       lv_label_set_text_fmt(label_down, "%lu B/s", m.rx_bps);
 *   }
 *
 * 建议 1 Hz 调用一次；文件是原子替换的，不会读到半截内容。
 */
#ifndef E87N_METRICS_H
#define E87N_METRICS_H

#include <stddef.h>

#define E87N_METRICS_ABI   1
#define E87N_METRICS_PATH  "/var/run/e87n/metrics.json"

/* 数值字段未知时为 -1（字符串字段为空串） */
typedef struct e87n_metrics {
    int          ts;                 /* 采样时间戳 (epoch)                  */
    int          uptime;             /* 开机秒数                            */
    int          temp_c;             /* 温度 °C                             */
    int          temp_ok;            /* 1 = 温度有效                        */
    int          cpu_pct;            /* CPU 占用 %                          */
    int          ram_pct;            /* 内存占用 %                          */
    int          disk_pct;           /* 磁盘占用 %                          */
    int          fan_pwm;            /* 风扇 PWM 0..255                     */
    int          fan_pct;            /* 风扇转速 % 0..100                   */
    char         fan_mode[16];       /* auto / manual / off                 */
    unsigned long rx_bps;            /* 下载 字节/秒（与屏幕「下载」同源）   */
    unsigned long tx_bps;            /* 上传 字节/秒                        */
    char         net_iface[16];      /* 统计的接口，默认 br-lan             */
    char         wan_ip[48];
    char         wan6[64];
    char         lan_ip[48];
    char         lan6[64];
    char         backlight[8];       /* on / off / unknown                  */
    char         display_page[16];   /* 当前页面 1-4 / cycle                */
    int          clients;            /* 在线设备数（DHCP 租约 + ARP 去重）  */
    char         saying[128];        /* 每日一言（UTF-8，可能为空）         */
} e87n_metrics_t;

#ifdef __cplusplus
extern "C" {
#endif

/* 读取并解析。返回 0 成功，-1 失败（文件不存在/解析失败）。 */
int e87n_metrics_read(e87n_metrics_t *out);

/* 读取原始 JSON 文本到 buf（含结尾 NUL）。返回 buf，失败返回 NULL。 */
const char *e87n_metrics_json(char *buf, size_t buflen);

#ifdef __cplusplus
}
#endif

#endif /* E87N_METRICS_H */
