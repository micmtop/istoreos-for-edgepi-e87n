/*
 * example_custom_page.c - 自定义 LVGL 页面的最小示例
 *
 * 演示：428x142 屏上放 4 行数据（温度 / 下载 / 上传 / CPU），1 Hz 刷新。
 * 数据来自 /var/run/e87n/metrics.json（见 docs/LVGL-CUSTOM-IMPORT.md）。
 *
 * 编译（与 e87n-display 同一个 LVGL）：
 *   - 放到 package/e87n-display/src/lib/ui/ 里一起编，或
 *   - 用 OpenWrt SDK 单独编：见 docs/LVGL-CUSTOM-IMPORT.md 路径 B
 */
#include "lvgl.h"
#include "e87n_metrics.h"

static lv_obj_t *s_lbl_temp;
static lv_obj_t *s_lbl_down;
static lv_obj_t *s_lbl_up;
static lv_obj_t *s_lbl_cpu;

static void refresh_cb(lv_timer_t *t)
{
    e87n_metrics_t m;

    (void)t;
    if (e87n_metrics_read(&m) != 0) {
        lv_label_set_text(s_lbl_temp, "--");
        return;
    }

    if (m.temp_c >= 0)
        lv_label_set_text_fmt(s_lbl_temp, "温度 %d°C", m.temp_c);
    else
        lv_label_set_text(s_lbl_temp, "温度 --");

    lv_label_set_text_fmt(s_lbl_down, "下载 %lu B/s", m.rx_bps);
    lv_label_set_text_fmt(s_lbl_up,   "上传 %lu B/s", m.tx_bps);
    lv_label_set_text_fmt(s_lbl_cpu,  "CPU %d%%  内存 %d%%", m.cpu_pct, m.ram_pct);
}

/* 契约：LVGL 导入后必须提供 ui_init() */
void ui_init(void)
{
    lv_obj_t *scr = lv_obj_create(NULL);

    lv_obj_set_style_bg_color(scr, lv_color_black(), 0);
    lv_obj_set_style_text_color(scr, lv_color_white(), 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

    s_lbl_temp = lv_label_create(scr);
    lv_obj_set_pos(s_lbl_temp, 6, 6);

    s_lbl_down = lv_label_create(scr);
    lv_obj_set_pos(s_lbl_down, 6, 34);

    s_lbl_up = lv_label_create(scr);
    lv_obj_set_pos(s_lbl_up, 6, 62);

    s_lbl_cpu = lv_label_create(scr);
    lv_obj_set_pos(s_lbl_cpu, 6, 90);

    lv_disp_load_scr(scr);

    /* 1 Hz 刷新：和 metrics.json 的刷新节奏一致 */
    lv_timer_create(refresh_cb, 1000, NULL);
}
