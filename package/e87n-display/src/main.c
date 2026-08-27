#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

// #include <mtk-spi.h>
// #include <cJSON.h>
#include "lib/lvgl/lvgl.h"
#include "lib/ui/ui.h"
#include "data/data_manager.h"
#include "ui/ui_refresher.h"

#define FBDEV "/dev/fb0"

// 屏幕类型枚举
typedef enum {
    SCREEN_NONE = 0,
    SCREEN_SYSTEM,  // 系统概况 (Screen1)
    SCREEN_TIME,    // 时间显示 (Screen2)
    SCREEN_CHART,   // 网速图表 (Screen3)
    SCREEN_ARC,     // 圆弧状态 (Screen4)
} screen_type_t;

static lv_display_t *get_display(void)
{
    lv_display_t *disp;
#if LV_USE_SDL
    disp = lv_sdl_window_create(428, 142);
#else
    disp = lv_linux_fbdev_create();
    lv_linux_fbdev_set_file(disp, FBDEV);
#endif
    if (disp == NULL) {
        return NULL;
    }
    return disp;
}

static void show_usage(const char *prog_name)
{
    printf("Usage: %s <screen_number> [cycle_seconds] [custom_text...]\n", prog_name);
    printf("  1 - System overview (Screen1)\n");
    printf("  2 - Time display (Screen2)\n");
    printf("  3 - Network chart (Screen3)\n");
    printf("  4 - System status arcs (Screen4)\n");
    printf("  cycle - rotate through all screens\n");
}

static screen_type_t g_current = SCREEN_SYSTEM;
static lv_timer_t *g_cycle_timer = NULL;
static uint32_t g_cycle_seconds = 10;

// 加载指定屏幕并注册对应刷新
static void load_screen(screen_type_t screen)
{
    extern lv_obj_t *ui_Screen2;
    extern lv_obj_t *ui_Screen3;
    extern lv_obj_t *ui_Screen4;

    switch (screen) {
    case SCREEN_SYSTEM:
        ui_refresher_unregister_screen2_labels();
        ui_refresher_unregister_screen3_charts();
        ui_refresher_unregister_screen4_arcs();
        lv_disp_load_scr(ui_Screen1);
        ui_refresher_register_screen1_labels();
        break;
    case SCREEN_TIME:
        ui_refresher_unregister_screen1_labels();
        ui_refresher_unregister_screen3_charts();
        ui_refresher_unregister_screen4_arcs();
        lv_disp_load_scr(ui_Screen2);
        ui_refresher_register_screen2_labels();
        break;
    case SCREEN_CHART:
        ui_refresher_unregister_screen1_labels();
        ui_refresher_unregister_screen2_labels();
        ui_refresher_unregister_screen4_arcs();
        lv_disp_load_scr(ui_Screen3);
        ui_refresher_register_screen3_charts();
        break;
    case SCREEN_ARC:
        ui_refresher_unregister_screen1_labels();
        ui_refresher_unregister_screen2_labels();
        ui_refresher_unregister_screen3_charts();
        lv_disp_load_scr(ui_Screen4);
        ui_refresher_register_screen4_arcs();
        break;
    default:
        break;
    }
    g_current = screen;
    printf("[Display] loaded screen %d\n", (int)screen);
}

// 轮播定时器回调
static void cycle_timer_cb(lv_timer_t *timer)
{
    (void)timer;
    screen_type_t next = SCREEN_SYSTEM;
    switch (g_current) {
    case SCREEN_SYSTEM: next = SCREEN_TIME; break;
    case SCREEN_TIME:   next = SCREEN_CHART; break;
    case SCREEN_CHART:  next = SCREEN_ARC; break;
    default:            next = SCREEN_SYSTEM; break;
    }
    load_screen(next);
}

// 在 Screen1 顶栏下方追加自定义文本（最大两行）
static void apply_custom_text(const char *text)
{
    if (!text || text[0] == '\0') {
        return;
    }
    extern lv_obj_t *ui_LabelCustom;
    if (ui_LabelCustom) {
        lv_label_set_text(ui_LabelCustom, text);
    }
}

static void start_cycle(void)
{
    if (g_cycle_timer) {
        return;
    }
    g_cycle_timer = lv_timer_create(cycle_timer_cb, g_cycle_seconds * 1000, NULL);
    lv_timer_set_repeat_count(g_cycle_timer, -1);
    printf("[Display] cycle mode: %u s/screen\n", g_cycle_seconds);
}

int main(int argc, char **argv) {
    screen_type_t screen = SCREEN_SYSTEM;  // 默认显示系统概况
    const char *custom_text = NULL;

    if (argc > 1) {
        if (strcmp(argv[1], "cycle") == 0) {
            screen = SCREEN_NONE;  // 轮播由定时器驱动
            if (argc > 2) {
                int sec = atoi(argv[2]);
                if (sec > 0 && sec <= 3600) {
                    g_cycle_seconds = (uint32_t)sec;
                }
            }
        } else {
            int screen_num = atoi(argv[1]);
            if (screen_num == 1) {
                screen = SCREEN_SYSTEM;
                printf("Starting system overview screen (Screen1)\n");
            } else if (screen_num == 2) {
                screen = SCREEN_TIME;
                printf("Starting time display screen (Screen2)\n");
            } else if (screen_num == 3) {
                screen = SCREEN_CHART;
                printf("Starting network chart screen (Screen3)\n");
            } else if (screen_num == 4) {
                screen = SCREEN_ARC;
                printf("Starting system status arcs screen (Screen4)\n");
            } else {
                printf("Invalid screen number: %s\n", argv[1]);
                show_usage(argv[0]);
                return 1;
            }
        }
    } else {
        printf("No screen specified, defaulting to system overview (Screen1)\n");
        show_usage(argv[0]);
    }

    // 剩余参数拼成自定义文本（多行）
    if (argc > 3 || (argc > 2 && screen != SCREEN_NONE)) {
        int start_idx = (screen == SCREEN_NONE) ? 3 : 2;
        if (start_idx < argc) {
            static char custom_buf[512];
            custom_buf[0] = '\0';
            for (int i = start_idx; i < argc && i < start_idx + 4; i++) {
                if (strlen(custom_buf) + strlen(argv[i]) + 1 < sizeof(custom_buf)) {
                    if (custom_buf[0]) strncat(custom_buf, "\n", sizeof(custom_buf) - strlen(custom_buf) - 1);
                    strncat(custom_buf, argv[i], sizeof(custom_buf) - strlen(custom_buf) - 1);
                }
            }
            custom_text = custom_buf;
        }
    }

    lv_init();
    lv_display_t *disp = get_display();
    if (disp == NULL) {
        printf("Failed to init display\n");
        return 1;
    }
    lv_disp_set_default(disp);

    // 初始化数据管理器
    if (data_manager_init() != 0) {
        printf("Failed to initialize data manager\n");
    }

    ui_init();
    apply_custom_text(custom_text);

    // 进入目标屏幕（cycle 模式从 Screen1 开始轮播）
    if (screen == SCREEN_NONE) {
        load_screen(SCREEN_SYSTEM);
        start_cycle();
    } else {
        load_screen(screen);
    }

    uint32_t idle_time;
    uint32_t last_data_refresh = 0;
    const uint32_t DATA_REFRESH_INTERVAL = 100; // 每100ms检查一次数据更新

    while (true) {
        /* Returns the time to the next timer execution */
        idle_time = lv_timer_handler();

        // 定期刷新数据（非阻塞）
        uint32_t now = lv_tick_get();
        if (now - last_data_refresh >= DATA_REFRESH_INTERVAL) {
            if (g_current == SCREEN_SYSTEM || g_current == SCREEN_CHART || g_current == SCREEN_ARC) {
                data_manager_refresh_all();  // 刷新系统数据
            } else if (g_current == SCREEN_TIME) {
                data_manager_update_time();  // 刷新时间数据
            }
            last_data_refresh = now;
        }

        usleep(idle_time * 1000);
    }

    // 清理（实际不会执行到这里）
    ui_refresher_deinit();
    data_manager_deinit();
    return 0;
}