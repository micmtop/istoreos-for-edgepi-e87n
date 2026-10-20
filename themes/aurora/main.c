/*
 * aurora - E87N 自定义主题（future cassette-ism 视觉语言）
 *
 * 428x142 / RGB565 / 无触摸。数据来自 /var/run/e87n/metrics.json：
 *   温度、上下行速率、时间、IP、在线数、每日一言。
 *
 * 设计要点（也是低占用的关键）：
 *   - 背景、边框、刻度都是一次性静态绘制，之后不再重绘；
 *   - 只有"会变的那一小块"参与动画：顶部扫描线(2px 高)、分段电平条、
 *     状态灯、一言文字；
 *   - 数据 1 Hz 读一次，值没变就不碰控件（LVGL 只在脏区重绘，
 *     fbtft 只通过 SPI 发变化的行）。
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "lvgl.h"
#include "e87n_metrics.h"

/* ---------- 配色：暗色底 + 琥珀主色 ---------- */
#define C_BG        0x0A0C10
#define C_BG2       0x141922
#define C_PANEL     0x0E1218
#define C_LINE      0x243040
#define C_AMBER     0xFFB347
#define C_AMBER_DIM 0x7A5220
#define C_TEAL      0x3FD0C9
#define C_RED       0xFF5A4F
#define C_TEXT      0xE8E2D0
#define C_MUTED     0x8A93A0
#define C_DIM       0x4A5460

/* ---------- 主题自带 CJK 字体（font.ttf，与 app 同目录） ---------- */
static lv_font_t *g_font_cjk;

static const lv_font_t *cjk_font(void)
{
    return g_font_cjk ? g_font_cjk : &lv_font_source_han_sans_sc_16_cjk;
}

static void load_theme_font(const char *argv0)
{
    char path[512];
    const char *slash;
    FILE *f;
    long n;
    void *buf;

    if (!argv0)
        return;
    slash = strrchr(argv0, '/');
    if (slash)
        snprintf(path, sizeof(path), "%.*s/font.ttf", (int)(slash - argv0), argv0);
    else
        snprintf(path, sizeof(path), "font.ttf");

    f = fopen(path, "rb");
    if (!f) {
        /* 没自带字体就用系统字体（随固件装在 /usr/share/e87n/font.ttf），
         * 主题包因此不必再塞 1.2MB 字体 */
        const char *env = getenv("E87N_FONT");
        snprintf(path, sizeof(path), "%s", env ? env : "/usr/share/e87n/font.ttf");
        f = fopen(path, "rb");
        if (!f)
            return;
    }
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0 || n > 8 * 1024 * 1024) {
        fclose(f);
        return;
    }
    buf = malloc((size_t)n);
    if (!buf) {
        fclose(f);
        return;
    }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        free(buf);
        return;
    }
    fclose(f);
    g_font_cjk = lv_tiny_ttf_create_data(buf, (size_t)n, 16);
    printf("[aurora] font.ttf loaded: %s (%ld bytes)", path, n);
}

/* ---------- 布局 ---------- */
#define W 428
#define H 142

static lv_obj_t *scr;
static lv_obj_t *lbl_time, *lbl_date, *lbl_ip;
static lv_obj_t *lbl_temp, *bar_temp;
static lv_obj_t *lbl_down, *bar_down, *lbl_up, *bar_up;
static lv_obj_t *lbl_clients, *lbl_uptime;
static lv_obj_t *lbl_saying;
static lv_obj_t *sweep;      /* 顶部扫描线 */

/* ---------- 上次的值（只在变化时刷控件） ---------- */
static int last_min = -1, last_temp = -999, last_clients = -999;
static int last_dp = -1, last_up = -1;
static int last_uptime = -1;
static char last_saying[128];
static char last_ip[48];

/* ------------------------------------------------------------------ */
/* 小工具                                                              */
/* ------------------------------------------------------------------ */

static void fmt_rate(char *buf, size_t n, unsigned long bps)
{
    if (bps < 1024UL)
        snprintf(buf, n, "%lu B/s", bps);
    else if (bps < 1024UL * 1024UL)
        snprintf(buf, n, "%.1f KB/s", (double)bps / 1024.0);
    else
        snprintf(buf, n, "%.2f MB/s", (double)bps / 1048576.0);
}

/* 速率 -> 电平条百分比（对数刻度，低速也看得见） */
static int rate_pct(unsigned long bps)
{
    int v;
    if (bps == 0)
        return 0;
    v = (int)(log10((double)bps + 1.0) * 22.0);
    if (v < 1)
        v = 1;
    if (v > 100)
        v = 100;
    return v;
}

static int temp_pct(int t)
{
    int v;
    if (t < 0)
        return 0;
    v = (t - 20) * 100 / 70;     /* 20..90°C 映射到 0..100 */
    if (v < 0)
        v = 0;
    if (v > 100)
        v = 100;
    return v;
}

static uint32_t temp_color(int t)
{
    if (t < 0)
        return C_DIM;
    if (t < 45)
        return C_TEAL;
    if (t < 60)
        return C_AMBER;
    return C_RED;
}

/* UTF-8 安全截断到 max_chars 个字符 */
static void utf8_trunc(char *s, size_t max_chars)
{
    size_t cnt = 0;
    unsigned char *p = (unsigned char *)s;

    while (*p) {
        if ((*p & 0xC0) != 0x80) {
            if (cnt >= max_chars) {
                *p = '\0';
                return;
            }
            cnt++;
        }
        p++;
    }
}

/* ------------------------------------------------------------------ */
/* 静态装饰                                                            */
/* ------------------------------------------------------------------ */

static lv_obj_t *rect(lv_obj_t *parent, int x, int y, int w, int h, uint32_t color)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_size(o, w, h);
    lv_obj_set_style_radius(o, 0, 0);
    lv_obj_set_style_border_width(o, 0, 0);
    lv_obj_set_style_pad_all(o, 0, 0);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(o, lv_color_hex(color), 0);
    return o;
}

static lv_obj_t *label(lv_obj_t *parent, int x, int y, const lv_font_t *font,
                       uint32_t color, const char *text)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_pos(l, x, y);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, lv_color_hex(color), 0);
    lv_label_set_text(l, text);
    return l;
}

/* 分段电平条：bar 本体 + 覆盖其上的"切口"，做出 VU 表质感 */
static lv_obj_t *seg_bar(lv_obj_t *parent, int x, int y, int w, int h,
                         int segments, uint32_t on_color)
{
    lv_obj_t *bar = lv_bar_create(parent);
    lv_obj_set_pos(bar, x, y);
    lv_obj_set_size(bar, w, h);
    lv_bar_set_range(bar, 0, 100);
    lv_bar_set_value(bar, 0, LV_ANIM_OFF);
    lv_obj_set_style_radius(bar, 0, LV_PART_MAIN);
    lv_obj_set_style_radius(bar, 0, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_bg_color(bar, lv_color_hex(C_BG2), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(bar, lv_color_hex(on_color), LV_PART_INDICATOR);
    lv_obj_set_style_anim_duration(bar, 420, LV_PART_INDICATOR);

    /* 切口（静态，只画一次） */
    if (segments > 1) {
        int i;
        for (i = 1; i < segments; i++) {
            int tx = (w * i) / segments;
            lv_obj_t *t = rect(parent, x + tx - 1, y, 2, h, C_BG);
        }
    }
    return bar;
}

/* ------------------------------------------------------------------ */
/* 动画                                                                */
/* ------------------------------------------------------------------ */

/* 顶部扫描线：2px 高，横向移动。脏区只有 2 行 -> SPI 几乎无感 */
static void anim_sweep_cb(lv_anim_t *a, int32_t v)
{
    lv_obj_set_x((lv_obj_t *)a->var, v);
}

static void start_sweep(lv_obj_t *line)
{
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, line);
    lv_anim_set_custom_exec_cb(&a, anim_sweep_cb);
    lv_anim_set_values(&a, -60, W);
    lv_anim_set_duration(&a, 4200);
    lv_anim_set_repeat_count(&a, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_repeat_delay(&a, 2600);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_start(&a);
}

/* 一言换句时从左滑入 */
static void anim_slide_cb(lv_anim_t *a, int32_t v)
{
    lv_obj_set_x((lv_obj_t *)a->var, v);
}

static void saying_slide_in(lv_obj_t *l)
{
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, l);
    lv_anim_set_custom_exec_cb(&a, anim_slide_cb);
    lv_anim_set_values(&a, 16, 0);
    lv_anim_set_duration(&a, 460);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_out);
    lv_anim_start(&a);
}

/* ------------------------------------------------------------------ */
/* 界面构建                                                            */
/* ------------------------------------------------------------------ */

static void build_ui(void)
{
    lv_obj_t *top, *mid, *sep;

    scr = lv_obj_create(NULL);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(scr, 0, 0);
    lv_obj_set_style_border_width(scr, 0, 0);
    lv_obj_set_style_radius(scr, 0, 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(scr, lv_color_hex(C_BG), 0);
    lv_obj_set_style_bg_grad_color(scr, lv_color_hex(C_BG2), 0);
    lv_obj_set_style_bg_grad_dir(scr, LV_GRAD_DIR_VER, 0);

    /* 顶部细线 + 扫描线（扫描线初始在屏幕外） */
    rect(scr, 0, 0, W, 2, C_LINE);
    sweep = rect(scr, -60, 0, 60, 2, C_AMBER);
    start_sweep(sweep);

    /* ---- 左：时间 / 日期 / IP ---- */
    lbl_time = label(scr, 8, 4, &lv_font_montserrat_44, C_AMBER, "00:00");
    lbl_date = label(scr, 10, 52, &lv_font_montserrat_12, C_MUTED, "--");
    lbl_ip   = label(scr, 10, 70, &lv_font_montserrat_12, C_DIM, "---");

    /* ---- 中：温度卡片 ---- */
    mid = lv_obj_create(scr);
    lv_obj_remove_flag(mid, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(mid, 152, 6);
    lv_obj_set_size(mid, 104, 74);
    lv_obj_set_style_radius(mid, 3, 0);
    lv_obj_set_style_bg_opa(mid, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(mid, lv_color_hex(C_PANEL), 0);
    lv_obj_set_style_border_width(mid, 1, 0);
    lv_obj_set_style_border_color(mid, lv_color_hex(C_AMBER_DIM), 0);
    lv_obj_set_style_pad_all(mid, 0, 0);

    lbl_temp = label(mid, 0, 6, &lv_font_montserrat_28, C_TEAL, "--");
    lv_obj_set_width(lbl_temp, 104);
    lv_obj_set_style_text_align(lbl_temp, LV_TEXT_ALIGN_CENTER, 0);

    bar_temp = seg_bar(scr, 160, 56, 88, 8, 8, C_TEAL);

    /* 卡片上沿的琥珀刻度点，纯装饰 */
    rect(scr, 152, 6, 24, 2, C_AMBER);

    /* ---- 右：上下行 ---- */
    lbl_down = label(scr, 266, 2, &lv_font_montserrat_14, C_TEAL, "DN --");
    bar_down = seg_bar(scr, 266, 22, 152, 6, 10, C_TEAL);

    lbl_up = label(scr, 266, 34, &lv_font_montserrat_14, C_AMBER, "UP --");
    bar_up = seg_bar(scr, 266, 54, 152, 6, 10, C_AMBER);

    lbl_clients = label(scr, 266, 66, cjk_font(), C_MUTED, "在线 --");

    /* ---- 分隔线 ---- */
    sep = rect(scr, 8, 84, W - 16, 1, C_LINE);
    (void)sep;

    /* ---- 底：一言 ---- */
    lbl_saying = lv_label_create(scr);
    lv_obj_set_pos(lbl_saying, 10, 92);
    lv_obj_set_size(lbl_saying, W - 20, 34);
    lv_obj_set_style_text_font(lbl_saying, cjk_font(), 0);
    lv_obj_set_style_text_color(lbl_saying, lv_color_hex(C_TEXT), 0);
    lv_obj_set_style_text_letter_space(lbl_saying, 0, 0);
    lv_label_set_long_mode(lbl_saying, LV_LABEL_LONG_MODE_WRAP);
    lv_obj_set_style_text_align(lbl_saying, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_text(lbl_saying, "");

    /* 右下角运行时长，很淡 */
    lbl_uptime = label(scr, W - 92, 126, &lv_font_montserrat_12, C_DIM, "");

    lv_screen_load(scr);
}

/* ------------------------------------------------------------------ */
/* 数据刷新                                                            */
/* ------------------------------------------------------------------ */

static void tick_cb(lv_timer_t *t)
{
    e87n_metrics_t m;
    time_t now = time(NULL);
    struct tm tmv;
    char buf[64];

    (void)t;

    localtime_r(&now, &tmv);

    /* 时间：只在分钟变化时改 */
    if (tmv.tm_min != last_min) {
        snprintf(buf, sizeof(buf), "%02d:%02d", tmv.tm_hour, tmv.tm_min);
        lv_label_set_text(lbl_time, buf);
        strftime(buf, sizeof(buf), "%m-%d  %a", &tmv);
        {
            char *p;
            for (p = buf; *p; p++)
                if (*p >= 'a' && *p <= 'z')
                    *p -= 32;
        }
        lv_label_set_text(lbl_date, buf);
        last_min = tmv.tm_min;
    }

    if (e87n_metrics_read(&m) != 0)
        return;

    /* IP */
    const char *ip = m.lan_ip[0] ? m.lan_ip : (m.wan_ip[0] ? m.wan_ip : "---");
    if (strcmp(ip, last_ip) != 0) {
        snprintf(last_ip, sizeof(last_ip), "%s", ip);
        snprintf(buf, sizeof(buf), "LAN  %s", ip);
        lv_label_set_text(lbl_ip, buf);
    }

    /* 温度 */
    if (m.temp_c != last_temp) {
        last_temp = m.temp_c;
        if (m.temp_c >= 0) {
            snprintf(buf, sizeof(buf), "%d°C", m.temp_c);
            lv_obj_set_style_text_color(lbl_temp, lv_color_hex(temp_color(m.temp_c)), 0);
        } else {
            snprintf(buf, sizeof(buf), "--");
        }
        lv_label_set_text(lbl_temp, buf);
        lv_obj_set_style_bg_color(bar_temp, lv_color_hex(temp_color(m.temp_c)),
                                  LV_PART_INDICATOR);
        lv_bar_set_value(bar_temp, temp_pct(m.temp_c), LV_ANIM_ON);
    }

    /* 速率 */
    int dp = rate_pct(m.rx_bps);
    int up = rate_pct(m.tx_bps);
    if (dp != last_dp) {
        last_dp = dp;
        lv_bar_set_value(bar_down, dp, LV_ANIM_ON);
    }
    if (up != last_up) {
        last_up = up;
        lv_bar_set_value(bar_up, up, LV_ANIM_ON);
    }
    fmt_rate(buf, sizeof(buf), m.rx_bps);
    lv_label_set_text_fmt(lbl_down, "DN %s", buf);
    fmt_rate(buf, sizeof(buf), m.tx_bps);
    lv_label_set_text_fmt(lbl_up, "UP %s", buf);

    /* 在线数 */
    if (m.clients != last_clients) {
        last_clients = m.clients;
        if (m.clients >= 0)
            lv_label_set_text_fmt(lbl_clients, "在线  %d", m.clients);
        else
            lv_label_set_text(lbl_clients, "在线  --");
    }

    /* 运行时长 */
    if (m.uptime / 60 != last_uptime) {
        last_uptime = m.uptime / 60;
        snprintf(buf, sizeof(buf), "UP %dd %02dh %02dm",
                 m.uptime / 86400, (m.uptime / 3600) % 24, (m.uptime / 60) % 60);
        lv_label_set_text(lbl_uptime, buf);
    }

    /* 一言：变化时截断 + 滑入 */
    if (strcmp(m.saying, last_saying) != 0) {
        snprintf(last_saying, sizeof(last_saying), "%s", m.saying);
        if (m.saying[0] && strcmp(m.saying, "--") != 0) {
            char s[128];
            snprintf(s, sizeof(s), "%s", m.saying);
            utf8_trunc(s, 30);
            lv_label_set_text(lbl_saying, s);
            saying_slide_in(lbl_saying);
        } else {
            lv_label_set_text(lbl_saying, "");
        }
    }
}

/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    lv_display_t *disp;

    (void)argc;
    lv_init();
    load_theme_font(argv ? argv[0] : NULL);

    disp = lv_linux_fbdev_create();
    if (!disp)
        return 1;
    lv_linux_fbdev_set_file(disp, "/dev/fb0");
    lv_display_set_default(disp);

    build_ui();
    tick_cb(NULL);
    lv_timer_create(tick_cb, 1000, NULL);

    for (;;) {
        uint32_t idle = lv_timer_handler();
        if (idle < 5)
            idle = 5;
        if (idle > 50)
            idle = 50;
        usleep(idle * 1000);
    }

    return 0;
}
