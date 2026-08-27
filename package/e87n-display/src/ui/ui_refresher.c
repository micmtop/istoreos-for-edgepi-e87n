#include "ui_refresher.h"
#include <string.h>
#include <stdio.h>
#include <time.h>

// 刷新任务结构
typedef struct {
    data_type_t type;
    lv_obj_t *label;
    lv_timer_t *timer;
    uint32_t period_ms;
    char format[64];
    char last_value[64];
    bool paused;
} refresh_task_t;

// 最多支持的数据类型数量
#define MAX_REFRESH_TASKS DATA_TYPE_MAX

static refresh_task_t g_tasks[MAX_REFRESH_TASKS];
static bool g_initialized = false;
static bool g_paused = false;

// 默认刷新周期
static const uint32_t g_default_periods[DATA_TYPE_MAX] = {
    [DATA_TYPE_NONE] = 0,
    [DATA_TYPE_WAN_IP] = 5000,          // 5秒
    [DATA_TYPE_WAN6_IP] = 5000,         // 5秒
    [DATA_TYPE_LAN_IP] = 5000,          // 5秒
    [DATA_TYPE_LAN6_IP] = 5000,         // 5秒
    [DATA_TYPE_DOWNLOAD_SPEED] = 2000,  // 2秒
    [DATA_TYPE_UPLOAD_SPEED] = 2000,    // 2秒
    [DATA_TYPE_CPU_USAGE] = 1000,       // 1秒
    [DATA_TYPE_RAM_USAGE] = 1000,       // 1秒
    [DATA_TYPE_TEMPERATURE] = 5000,     // 5秒
    [DATA_TYPE_FAN_PWM] = 5000,         // 5秒
    [DATA_TYPE_TIME] = 1000,            // 1秒（时间带秒）
    [DATA_TYPE_AMPM] = 1000,            // 1秒
    [DATA_TYPE_DATE] = 60000,           // 60秒
    [DATA_TYPE_WEEK] = 60000,           // 60秒
};

// 定时器回调函数
static void timer_callback(lv_timer_t *timer)
{
    refresh_task_t *task = (refresh_task_t *)lv_timer_get_user_data(timer);

    if (!task || !task->label || task->paused) {
        return;
    }

    // 获取最新数据
    const char *data_str = data_manager_get_string(task->type);
    if (!data_str) {
        data_str = "--";
    }

    // 格式化输出
    char display_str[128];
    if (task->format[0]) {
        snprintf(display_str, sizeof(display_str), task->format, data_str);
    } else {
        strncpy(display_str, data_str, sizeof(display_str) - 1);
        display_str[sizeof(display_str) - 1] = '\0';
    }

    // 只有当值变化时才更新 UI
    if (strcmp(display_str, task->last_value) != 0) {
        lv_label_set_text(task->label, display_str);
        strncpy(task->last_value, display_str, sizeof(task->last_value) - 1);
    }
}

int ui_refresher_init(void)
{
    if (g_initialized) {
        return 0;
    }

    memset(g_tasks, 0, sizeof(g_tasks));

    for (int i = 0; i < MAX_REFRESH_TASKS; i++) {
        g_tasks[i].type = DATA_TYPE_NONE;
        g_tasks[i].label = NULL;
        g_tasks[i].timer = NULL;
        g_tasks[i].paused = false;
        g_tasks[i].last_value[0] = '\0';
    }

    g_paused = false;
    g_initialized = true;

    printf("[UIRefresher] Initialized\n");
    return 0;
}

void ui_refresher_deinit(void)
{
    if (!g_initialized) {
        return;
    }

    // 注销所有任务
    for (int i = 0; i < MAX_REFRESH_TASKS; i++) {
        if (g_tasks[i].timer) {
            lv_timer_delete(g_tasks[i].timer);
            g_tasks[i].timer = NULL;
        }
        g_tasks[i].label = NULL;
        g_tasks[i].type = DATA_TYPE_NONE;
    }

    g_initialized = false;
    printf("[UIRefresher] Deinitialized\n");
}

int ui_refresher_register_label(data_type_t type, lv_obj_t *label,
                                uint32_t period_ms, const char *format)
{
    if (!g_initialized || type <= DATA_TYPE_NONE || type >= DATA_TYPE_MAX || !label) {
        return -1;
    }

    // 查找是否已存在
    int slot = -1;
    for (int i = 0; i < MAX_REFRESH_TASKS; i++) {
        if (g_tasks[i].type == type) {
            slot = i;
            break;
        }
        if (slot < 0 && g_tasks[i].type == DATA_TYPE_NONE) {
            slot = i;
        }
    }

    if (slot < 0) {
        printf("[UIRefresher] Error: no slot available\n");
        return -1;
    }

    // 如果已存在，先删除旧定时器
    if (g_tasks[slot].timer) {
        lv_timer_delete(g_tasks[slot].timer);
    }

    // 设置新任务
    g_tasks[slot].type = type;
    g_tasks[slot].label = label;
    g_tasks[slot].period_ms = period_ms;
    g_tasks[slot].paused = false;
    g_tasks[slot].last_value[0] = '\0';

    if (format && format[0]) {
        strncpy(g_tasks[slot].format, format, sizeof(g_tasks[slot].format) - 1);
        g_tasks[slot].format[sizeof(g_tasks[slot].format) - 1] = '\0';
    } else {
        g_tasks[slot].format[0] = '\0';
    }

    // 创建定时器
    g_tasks[slot].timer = lv_timer_create(timer_callback, period_ms, &g_tasks[slot]);
    if (!g_tasks[slot].timer) {
        printf("[UIRefresher] Error: failed to create timer\n");
        g_tasks[slot].type = DATA_TYPE_NONE;
        return -1;
    }

    // 立即刷新一次
    timer_callback(g_tasks[slot].timer);

    printf("[UIRefresher] Registered label for type %d with period %ums\n", type, period_ms);
    return 0;
}

void ui_refresher_unregister_label(data_type_t type)
{
    if (!g_initialized || type <= DATA_TYPE_NONE || type >= DATA_TYPE_MAX) {
        return;
    }

    for (int i = 0; i < MAX_REFRESH_TASKS; i++) {
        if (g_tasks[i].type == type) {
            if (g_tasks[i].timer) {
                lv_timer_delete(g_tasks[i].timer);
                g_tasks[i].timer = NULL;
            }
            g_tasks[i].type = DATA_TYPE_NONE;
            g_tasks[i].label = NULL;
            g_tasks[i].last_value[0] = '\0';
            printf("[UIRefresher] Unregistered label for type %d\n", type);
            break;
        }
    }
}

void ui_refresher_pause(void)
{
    if (!g_initialized) {
        return;
    }

    g_paused = true;
    for (int i = 0; i < MAX_REFRESH_TASKS; i++) {
        if (g_tasks[i].timer) {
            lv_timer_pause(g_tasks[i].timer);
            g_tasks[i].paused = true;
        }
    }
    printf("[UIRefresher] Paused\n");
}

void ui_refresher_resume(void)
{
    if (!g_initialized) {
        return;
    }

    g_paused = false;
    for (int i = 0; i < MAX_REFRESH_TASKS; i++) {
        if (g_tasks[i].timer) {
            lv_timer_resume(g_tasks[i].timer);
            g_tasks[i].paused = false;
        }
    }
    printf("[UIRefresher] Resumed\n");
}

void ui_refresher_refresh_now(void)
{
    if (!g_initialized) {
        return;
    }

    for (int i = 0; i < MAX_REFRESH_TASKS; i++) {
        if (g_tasks[i].timer && g_tasks[i].label) {
            timer_callback(g_tasks[i].timer);
        }
    }
}

void ui_refresher_register_screen1_labels(void)
{
    if (!g_initialized) {
        return;
    }

    // 导入 Screen1 的 Label 变量
    extern lv_obj_t *ui_LabelLan;
    extern lv_obj_t *ui_LabelLan6;
    extern lv_obj_t *ui_LabelDlSpeed;
    extern lv_obj_t *ui_LabelUlSpeed;
    extern lv_obj_t *ui_LabelCpu;
    extern lv_obj_t *ui_LabelRam;
    extern lv_obj_t *ui_LabelTemp;
    extern lv_obj_t *ui_LabelFan;

    // 注册各个 Label，使用默认周期和格式
    if (ui_LabelLan) {
        ui_refresher_register_label(DATA_TYPE_LAN_IP, ui_LabelLan,
                                    g_default_periods[DATA_TYPE_LAN_IP], NULL);
    }

    if (ui_LabelLan6) {
        ui_refresher_register_label(DATA_TYPE_LAN6_IP, ui_LabelLan6,
                                    g_default_periods[DATA_TYPE_LAN6_IP], NULL);
    }

    if (ui_LabelDlSpeed) {
        ui_refresher_register_label(DATA_TYPE_DOWNLOAD_SPEED, ui_LabelDlSpeed,
                                    g_default_periods[DATA_TYPE_DOWNLOAD_SPEED], NULL);
    }

    if (ui_LabelUlSpeed) {
        ui_refresher_register_label(DATA_TYPE_UPLOAD_SPEED, ui_LabelUlSpeed,
                                    g_default_periods[DATA_TYPE_UPLOAD_SPEED], NULL);
    }

    if (ui_LabelCpu) {
        ui_refresher_register_label(DATA_TYPE_CPU_USAGE, ui_LabelCpu,
                                    g_default_periods[DATA_TYPE_CPU_USAGE], NULL);
    }

    if (ui_LabelRam) {
        ui_refresher_register_label(DATA_TYPE_RAM_USAGE, ui_LabelRam,
                                    g_default_periods[DATA_TYPE_RAM_USAGE], NULL);
    }

    if (ui_LabelTemp) {
        ui_refresher_register_label(DATA_TYPE_TEMPERATURE, ui_LabelTemp,
                                    g_default_periods[DATA_TYPE_TEMPERATURE], NULL);
    }

    if (ui_LabelFan) {
        ui_refresher_register_label(DATA_TYPE_FAN_PWM, ui_LabelFan,
                                    g_default_periods[DATA_TYPE_FAN_PWM], NULL);
    }

    printf("[UIRefresher] Registered all Screen1 labels\n");
}

void ui_refresher_unregister_screen1_labels(void)
{
    ui_refresher_unregister_label(DATA_TYPE_LAN_IP);
    ui_refresher_unregister_label(DATA_TYPE_LAN6_IP);
    ui_refresher_unregister_label(DATA_TYPE_DOWNLOAD_SPEED);
    ui_refresher_unregister_label(DATA_TYPE_UPLOAD_SPEED);
    ui_refresher_unregister_label(DATA_TYPE_CPU_USAGE);
    ui_refresher_unregister_label(DATA_TYPE_RAM_USAGE);
    ui_refresher_unregister_label(DATA_TYPE_TEMPERATURE);
    ui_refresher_unregister_label(DATA_TYPE_FAN_PWM);

    printf("[UIRefresher] Unregistered all Screen1 labels\n");
}

// Screen2 时间显示相关变量
static lv_obj_t *g_label_hour = NULL;
static lv_obj_t *g_label_minute = NULL;
static lv_obj_t *g_label_second = NULL;
static lv_obj_t *g_label_colon = NULL;
static lv_timer_t *g_screen2_timer = NULL;

// Screen2 时间刷新回调
static void screen2_time_timer_callback(lv_timer_t *timer)
{
    (void)timer;

    if (!g_initialized) return;

    // 获取当前时间
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    if (!tm_info) return;

    // 转换为12小时制
    int hour_12 = tm_info->tm_hour % 12;
    if (hour_12 == 0) hour_12 = 12;

    // 更新小时
    if (g_label_hour) {
        char hour_str[8];
        snprintf(hour_str, sizeof(hour_str), "%02d", hour_12);
        lv_label_set_text(g_label_hour, hour_str);
    }

    // 更新分钟
    if (g_label_minute) {
        char minute_str[8];
        snprintf(minute_str, sizeof(minute_str), "%02d", tm_info->tm_min);
        lv_label_set_text(g_label_minute, minute_str);
    }

    // 更新秒
    if (g_label_second) {
        char second_str[8];
        snprintf(second_str, sizeof(second_str), "%02d", tm_info->tm_sec);
        lv_label_set_text(g_label_second, second_str);
    }

    // 冒号闪烁效果：每秒切换显示/隐藏
    if (g_label_colon) {
        // 根据秒数的奇偶性切换
        if (tm_info->tm_sec % 2 == 0) {
            lv_obj_clear_flag(g_label_colon, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(g_label_colon, LV_OBJ_FLAG_HIDDEN);
        }
    }
}

void ui_refresher_register_screen2_labels(void)
{
    if (!g_initialized) {
        return;
    }

    // 导入 Screen2 的 Label 变量
    extern lv_obj_t *ui_LabelHour;
    extern lv_obj_t *ui_LabelMinute;
    extern lv_obj_t *ui_LabelSecond;
    extern lv_obj_t *ui_LabelColon;
    extern lv_obj_t *ui_LabelAmpm;
    extern lv_obj_t *ui_LabelDate;
    extern lv_obj_t *ui_LabelWeek;

    // 保存引用
    g_label_hour = ui_LabelHour;
    g_label_minute = ui_LabelMinute;
    g_label_second = ui_LabelSecond;
    g_label_colon = ui_LabelColon;

    // 删除旧定时器（如果存在）
    if (g_screen2_timer) {
        lv_timer_delete(g_screen2_timer);
        g_screen2_timer = NULL;
    }

    // 创建时间刷新定时器（每秒刷新）
    g_screen2_timer = lv_timer_create(screen2_time_timer_callback, 1000, NULL);

    // 立即刷新一次
    screen2_time_timer_callback(NULL);

    // 注册 AM/PM Label
    if (ui_LabelAmpm) {
        ui_refresher_register_label(DATA_TYPE_AMPM, ui_LabelAmpm,
                                    g_default_periods[DATA_TYPE_AMPM], NULL);
    }

    // 注册日期 Label（每分钟刷新即可）
    if (ui_LabelDate) {
        ui_refresher_register_label(DATA_TYPE_DATE, ui_LabelDate,
                                    g_default_periods[DATA_TYPE_DATE], NULL);
    }

    // 注册星期 Label
    if (ui_LabelWeek) {
        ui_refresher_register_label(DATA_TYPE_WEEK, ui_LabelWeek,
                                    g_default_periods[DATA_TYPE_WEEK], NULL);
    }

    printf("[UIRefresher] Registered all Screen2 labels\n");
}

void ui_refresher_unregister_screen2_labels(void)
{
    // 删除 Screen2 时间定时器
    if (g_screen2_timer) {
        lv_timer_delete(g_screen2_timer);
        g_screen2_timer = NULL;
    }

    // 清除引用
    g_label_hour = NULL;
    g_label_minute = NULL;
    g_label_second = NULL;
    g_label_colon = NULL;

    // 注销其他 Label
    ui_refresher_unregister_label(DATA_TYPE_AMPM);
    ui_refresher_unregister_label(DATA_TYPE_DATE);
    ui_refresher_unregister_label(DATA_TYPE_WEEK);

    printf("[UIRefresher] Unregistered all Screen2 labels\n");
}

// ===================== Screen3 图表管理 =====================

#define CHART_POINT_COUNT 60

// 图表数据数组（Y轴百分比值 0-100）
static lv_coord_t g_chart_dl_data[CHART_POINT_COUNT] = {0};
static lv_coord_t g_chart_ul_data[CHART_POINT_COUNT] = {0};

// 实际速度值数组（字节/秒，用于计算百分比）
static uint64_t g_chart_dl_speeds[CHART_POINT_COUNT] = {0};
static uint64_t g_chart_ul_speeds[CHART_POINT_COUNT] = {0};

// 图表系列指针
static lv_chart_series_t *g_dl_series = NULL;
static lv_chart_series_t *g_ul_series = NULL;
static lv_obj_t *g_dl_label = NULL;
static lv_obj_t *g_ul_label = NULL;
static lv_timer_t *g_chart_timer = NULL;

// 格式化速度为人类可读格式
static void format_speed(uint64_t bytes_per_sec, char *buf, size_t buf_size)
{
    if (bytes_per_sec >= 1024 * 1024 * 1024) {
        snprintf(buf, buf_size, "%.2f GB/s", bytes_per_sec / (1024.0 * 1024 * 1024));
    } else if (bytes_per_sec >= 1024 * 1024) {
        snprintf(buf, buf_size, "%.2f MB/s", bytes_per_sec / (1024.0 * 1024));
    } else if (bytes_per_sec >= 1024) {
        snprintf(buf, buf_size, "%.2f KB/s", bytes_per_sec / 1024.0);
    } else {
        snprintf(buf, buf_size, "%llu B/s", (unsigned long long)bytes_per_sec);
    }
}

// 更新图表数据：新数据插入末尾（右侧），旧数据向左移动
static void update_chart_data(lv_coord_t *y_data, uint64_t *speed_data,
                              uint64_t new_speed)
{
    // 移动数据：索引0是最旧的，索引19是最新的
    // 新数据从右侧进入，所以向左移动所有数据
    for (int i = 0; i < CHART_POINT_COUNT - 1; i++) {
        y_data[i] = y_data[i + 1];
        speed_data[i] = speed_data[i + 1];
    }

    // 插入新速度到末尾
    speed_data[CHART_POINT_COUNT - 1] = new_speed;

    // 计算当前最大值（用于百分比转换）
    uint64_t max_speed = 100; // 最小基准值避免除零
    for (int i = 0; i < CHART_POINT_COUNT; i++) {
        if (speed_data[i] > max_speed) {
            max_speed = speed_data[i];
        }
    }

    // 将速度转换为百分比（基于当前最大值）
    for (int i = 0; i < CHART_POINT_COUNT; i++) {
        y_data[i] = (lv_coord_t)((speed_data[i] * 100) / max_speed);
        if (y_data[i] > 100) y_data[i] = 100;
    }
}

// 图表刷新定时器回调
static void chart_timer_callback(lv_timer_t *timer)
{
    (void)timer;

    if (!g_initialized) return;

    // 导入 Screen3 的图表对象
    extern lv_obj_t *ui_ChartDlSpeed;
    extern lv_obj_t *ui_ChartUlSpeed;

    // 从数据管理器获取当前速度（原始字节/秒值）
    uint32_t dl_speed = data_manager_get_int(DATA_TYPE_DOWNLOAD_SPEED);
    uint32_t ul_speed = data_manager_get_int(DATA_TYPE_UPLOAD_SPEED);

    // 更新图表数据
    update_chart_data(g_chart_dl_data, g_chart_dl_speeds, dl_speed);
    update_chart_data(g_chart_ul_data, g_chart_ul_speeds, ul_speed);

    // 更新图表显示
    if (g_dl_series && ui_ChartDlSpeed) {
        lv_chart_set_series_ext_y_array(ui_ChartDlSpeed, g_dl_series, g_chart_dl_data);
        lv_chart_refresh(ui_ChartDlSpeed);
    }

    if (g_ul_series && ui_ChartUlSpeed) {
        lv_chart_set_series_ext_y_array(ui_ChartUlSpeed, g_ul_series, g_chart_ul_data);
        lv_chart_refresh(ui_ChartUlSpeed);
    }

    // 更新标签显示实际速度（标签本身显示"下载"/"上传"，这里只更新数值）
    if (g_dl_label) {
        char speed_str[32];
        format_speed(dl_speed, speed_str, sizeof(speed_str));
        lv_label_set_text(g_dl_label, speed_str);
    }

    if (g_ul_label) {
        char speed_str[32];
        format_speed(ul_speed, speed_str, sizeof(speed_str));
        lv_label_set_text(g_ul_label, speed_str);
    }
}

void ui_refresher_register_screen3_charts(void)
{
    if (!g_initialized) {
        return;
    }

    // 导入 Screen3 的变量
    extern lv_obj_t *ui_ChartDlSpeed;
    extern lv_obj_t *ui_ChartUlSpeed;
    extern lv_obj_t *ui_LabelChartDlValue;
    extern lv_obj_t *ui_LabelChartUlValue;

    // 获取图表系列
    if (ui_ChartDlSpeed) {
        g_dl_series = lv_chart_get_series_next(ui_ChartDlSpeed, NULL);
    }
    if (ui_ChartUlSpeed) {
        g_ul_series = lv_chart_get_series_next(ui_ChartUlSpeed, NULL);
    }

    g_dl_label = ui_LabelChartDlValue;
    g_ul_label = ui_LabelChartUlValue;

    // 初始化图表数据数组
    memset(g_chart_dl_data, 0, sizeof(g_chart_dl_data));
    memset(g_chart_ul_data, 0, sizeof(g_chart_ul_data));
    memset(g_chart_dl_speeds, 0, sizeof(g_chart_dl_speeds));
    memset(g_chart_ul_speeds, 0, sizeof(g_chart_ul_speeds));

    // 如果系列存在，设置外部数组
    if (g_dl_series) {
        lv_chart_set_series_ext_y_array(ui_ChartDlSpeed, g_dl_series, g_chart_dl_data);
    }
    if (g_ul_series) {
        lv_chart_set_series_ext_y_array(ui_ChartUlSpeed, g_ul_series, g_chart_ul_data);
    }

    // 删除旧定时器（如果存在）
    if (g_chart_timer) {
        lv_timer_delete(g_chart_timer);
        g_chart_timer = NULL;
    }

    // 创建图表刷新定时器（500ms刷新一次，比Label快以显示更流畅的图表）
    g_chart_timer = lv_timer_create(chart_timer_callback, 500, NULL);

    // 立即刷新一次
    chart_timer_callback(NULL);

    printf("[UIRefresher] Registered Screen3 charts\n");
}

void ui_refresher_unregister_screen3_charts(void)
{
    if (g_chart_timer) {
        lv_timer_delete(g_chart_timer);
        g_chart_timer = NULL;
    }

    g_dl_series = NULL;
    g_ul_series = NULL;
    g_dl_label = NULL;
    g_ul_label = NULL;

    printf("[UIRefresher] Unregistered Screen3 charts\n");
}

// ===================== Screen4 Arc 管理 =====================

// Screen4 定时器
static lv_timer_t *g_screen4_timer = NULL;

// 刷新周期配置（毫秒）
#define SCREEN4_ARC_REFRESH_PERIOD 1000  // 1秒刷新一次

// 更新单个 Arc 的辅助函数
// direct_value=true: 直接将 value 设置给 Arc（Arc 范围已配置为 0-max_value）
// direct_value=false: 将 value 转换为百分比后设置给 Arc（Arc 范围为 0-100）
static void update_arc(lv_obj_t *arc, lv_obj_t *label, data_type_t type,
                          const char *unit, uint32_t max_value)
{
    if (!arc || !label) return;

    uint32_t value = data_manager_get_int(type);

    // 限制最大值
    if (value > max_value) {
        value = max_value;
    }

    // 计算 Arc 值
    int32_t arc_value;
    arc_value = (int32_t)value;

    // 更新 Arc 值
    lv_arc_set_value(arc, arc_value);

    // 更新 Label 显示
    char label_str[32];
    if (unit) {
        snprintf(label_str, sizeof(label_str), "%u %s", value, unit);
    } else {
        snprintf(label_str, sizeof(label_str), "%u", value);
    }
    lv_label_set_text(label, label_str);
}

// Screen4 刷新定时器回调
static void screen4_timer_callback(lv_timer_t *timer)
{
    (void)timer;

    if (!g_initialized) return;

    // 导入 Screen4 的变量
    extern lv_obj_t *ui_ArcCpu;
    extern lv_obj_t *ui_LabelArcCpuValue;
    extern lv_obj_t *ui_ArcRam;
    extern lv_obj_t *ui_LabelArcRamValue;
    extern lv_obj_t *ui_ArcTemp;
    extern lv_obj_t *ui_LabelArcTempValue;
    extern lv_obj_t *ui_ArcDisk;
    extern lv_obj_t *ui_LabelArcDiskValue;

    // 更新 CPU Arc（范围 0-100%）
    update_arc(ui_ArcCpu, ui_LabelArcCpuValue, DATA_TYPE_CPU_USAGE, "%", 100);

    // 更新 RAM Arc（范围 0-100%）
    update_arc(ui_ArcRam, ui_LabelArcRamValue, DATA_TYPE_RAM_USAGE, "%", 100);

    // 更新温度 Arc（范围 0-120°C，Arc 已设置范围为 0-120，直接使用实际值）
    update_arc(ui_ArcTemp, ui_LabelArcTempValue, DATA_TYPE_TEMPERATURE, "℃", 120);

    // 更新磁盘 Arc（范围 0-100%）
    update_arc(ui_ArcDisk, ui_LabelArcDiskValue, DATA_TYPE_DISK_USAGE, "%", 100);
}

void ui_refresher_register_screen4_arcs(void)
{
    if (!g_initialized) {
        return;
    }

    // 删除旧定时器（如果存在）
    if (g_screen4_timer) {
        lv_timer_delete(g_screen4_timer);
        g_screen4_timer = NULL;
    }

    // 创建 Screen4 刷新定时器
    g_screen4_timer = lv_timer_create(screen4_timer_callback, SCREEN4_ARC_REFRESH_PERIOD, NULL);

    // 立即刷新一次
    screen4_timer_callback(NULL);

    printf("[UIRefresher] Registered Screen4 arcs\n");
}

void ui_refresher_unregister_screen4_arcs(void)
{
    if (g_screen4_timer) {
        lv_timer_delete(g_screen4_timer);
        g_screen4_timer = NULL;
    }

    printf("[UIRefresher] Unregistered Screen4 arcs\n");
}
