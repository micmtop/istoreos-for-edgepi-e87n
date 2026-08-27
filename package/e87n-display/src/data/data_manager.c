#include "data_manager.h"
#include "data_network.h"
#include "data_system.h"
#include "data_thermal.h"
#include "data_disk.h"
#include "data_fan.h"
#include <string.h>
#include <stdio.h>
#include <time.h>

// 数据过期时间（秒）- 注意：对于静态数据如IP，使用较长过期时间
#define DATA_EXPIRE_SECONDS 60
#define DATA_EXPIRE_STATIC_SECONDS 300  // 静态数据（IP）5分钟过期

// 数据项数组
static data_item_t g_data_items[DATA_TYPE_MAX];
static bool g_initialized = false;

// 各数据模块的更新周期（毫秒）
static uint32_t g_last_update_time[DATA_TYPE_MAX] = {0};
static const uint32_t g_update_periods[DATA_TYPE_MAX] = {
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
    [DATA_TYPE_DISK_USAGE] = 10000,     // 10秒（磁盘变化不频繁）
    [DATA_TYPE_TIME] = 1000,            // 1秒（带秒的时间）
    [DATA_TYPE_AMPM] = 1000,            // 1秒
    [DATA_TYPE_DATE] = 60000,           // 60秒（日期变化不频繁）
    [DATA_TYPE_WEEK] = 60000,           // 60秒
};

// 获取当前时间（毫秒）
static uint32_t get_tick_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int data_manager_init(void)
{
    if (g_initialized) {
        return 0;
    }

    // 初始化所有数据项
    memset(g_data_items, 0, sizeof(g_data_items));
    for (int i = 0; i < DATA_TYPE_MAX; i++) {
        g_data_items[i].type = (data_type_t)i;
        g_data_items[i].valid = false;
        strncpy(g_data_items[i].value_str, "--", sizeof(g_data_items[i].value_str) - 1);
    }

    memset(g_last_update_time, 0, sizeof(g_last_update_time));

    // 先标记为已初始化，这样子模块可以调用 data_manager_update
    g_initialized = true;

    // 初始化各数据模块（内部会立即获取一次数据）
    if (data_network_init() != 0) {
        printf("[DataManager] Warning: network data init failed\n");
    }

    if (data_system_init() != 0) {
        printf("[DataManager] Warning: system data init failed\n");
    }

    if (data_thermal_init() != 0) {
        printf("[DataManager] Warning: thermal data init failed\n");
    }

    if (data_fan_init() != 0) {
        printf("[DataManager] Warning: fan data init failed\n");
    }

    if (data_disk_init() != 0) {
        printf("[DataManager] Warning: disk data init failed\n");
    } else {
        // 立即获取一次磁盘数据
        data_disk_update();
    }

    // 立即获取一次时间数据，确保启动时显示正确
    data_manager_update_time();

    printf("[DataManager] Initialized\n");
    return 0;
}

void data_manager_deinit(void)
{
    if (!g_initialized) {
        return;
    }

    data_network_deinit();
    data_system_deinit();
    data_thermal_deinit();
    data_fan_deinit();
    data_disk_deinit();

    g_initialized = false;
    printf("[DataManager] Deinitialized\n");
}

// 判断是否为静态数据类型（IP地址等不频繁变化的数据）
static bool is_static_data_type(data_type_t type)
{
    return (type == DATA_TYPE_WAN_IP || type == DATA_TYPE_WAN6_IP ||
            type == DATA_TYPE_LAN_IP || type == DATA_TYPE_LAN6_IP);
}

const char *data_manager_get_string(data_type_t type)
{
    if (type <= DATA_TYPE_NONE || type >= DATA_TYPE_MAX) {
        return "--";
    }

    // 检查数据是否过期 - 使用不同的过期策略
    if (g_data_items[type].valid) {
        time_t now = time(NULL);
        time_t expire_time = is_static_data_type(type) ?
                             DATA_EXPIRE_STATIC_SECONDS : DATA_EXPIRE_SECONDS;

        if (now - g_data_items[type].timestamp > expire_time) {
            // 对于静态数据，即使过期也保留旧值，直到获取到新值
            if (!is_static_data_type(type)) {
                g_data_items[type].valid = false;
            }
        }
    }

    return g_data_items[type].valid ? g_data_items[type].value_str : "--";
}

uint32_t data_manager_get_int(data_type_t type)
{
    if (type <= DATA_TYPE_NONE || type >= DATA_TYPE_MAX) {
        return 0;
    }

    return g_data_items[type].valid ? g_data_items[type].value_int : 0;
}

bool data_manager_is_valid(data_type_t type)
{
    if (type <= DATA_TYPE_NONE || type >= DATA_TYPE_MAX) {
        return false;
    }

    // 检查数据是否过期
    if (g_data_items[type].valid) {
        time_t now = time(NULL);
        if (now - g_data_items[type].timestamp > DATA_EXPIRE_SECONDS) {
            g_data_items[type].valid = false;
        }
    }

    return g_data_items[type].valid;
}

int data_manager_update(data_type_t type, const char *str_val, uint32_t int_val)
{
    if (type <= DATA_TYPE_NONE || type >= DATA_TYPE_MAX) {
        return -1;
    }

    if (str_val) {
        strncpy(g_data_items[type].value_str, str_val, sizeof(g_data_items[type].value_str) - 1);
        g_data_items[type].value_str[sizeof(g_data_items[type].value_str) - 1] = '\0';
    }

    g_data_items[type].value_int = int_val;
    g_data_items[type].timestamp = time(NULL);
    g_data_items[type].valid = true;

    return 0;
}

void data_manager_refresh_all(void)
{
    if (!g_initialized) {
        return;
    }

    uint32_t now = get_tick_ms();

    // 网络数据（IPv4/IPv6 WAN/LAN）- 5秒
    if (now - g_last_update_time[DATA_TYPE_WAN_IP] >= g_update_periods[DATA_TYPE_WAN_IP]) {
        data_network_update();
        g_last_update_time[DATA_TYPE_WAN_IP] = now;
        g_last_update_time[DATA_TYPE_WAN6_IP] = now;  // WAN IPv6 同时更新
        g_last_update_time[DATA_TYPE_LAN_IP] = now;   // LAN IPv4 同时更新
        g_last_update_time[DATA_TYPE_LAN6_IP] = now;  // LAN IPv6 同时更新
    }

    // 网络速度 - 2秒
    if (now - g_last_update_time[DATA_TYPE_DOWNLOAD_SPEED] >= g_update_periods[DATA_TYPE_DOWNLOAD_SPEED]) {
        // 速度更新在 data_network_update 中统一处理
        g_last_update_time[DATA_TYPE_DOWNLOAD_SPEED] = now;
        g_last_update_time[DATA_TYPE_UPLOAD_SPEED] = now;
    }

    // 系统数据（CPU/RAM）- 1秒
    if (now - g_last_update_time[DATA_TYPE_CPU_USAGE] >= g_update_periods[DATA_TYPE_CPU_USAGE]) {
        data_system_update();
        g_last_update_time[DATA_TYPE_CPU_USAGE] = now;
        g_last_update_time[DATA_TYPE_RAM_USAGE] = now;
    }

    // 温度 - 5秒
    if (now - g_last_update_time[DATA_TYPE_TEMPERATURE] >= g_update_periods[DATA_TYPE_TEMPERATURE]) {
        data_thermal_update();
        g_last_update_time[DATA_TYPE_TEMPERATURE] = now;
    }

    // 风扇 PWM - 5秒
    if (now - g_last_update_time[DATA_TYPE_FAN_PWM] >= g_update_periods[DATA_TYPE_FAN_PWM]) {
        data_fan_update();
        g_last_update_time[DATA_TYPE_FAN_PWM] = now;
    }

    // 磁盘使用 - 10秒
    if (now - g_last_update_time[DATA_TYPE_DISK_USAGE] >= g_update_periods[DATA_TYPE_DISK_USAGE]) {
        data_disk_update();
        g_last_update_time[DATA_TYPE_DISK_USAGE] = now;
    }
}

void data_manager_update_time(void)
{
    if (!g_initialized) {
        return;
    }

    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    if (!tm_info) {
        return;
    }

    // 更新时间 HH:MM:SS（12小时制）
    char time_str[32];
    int hour_12 = tm_info->tm_hour % 12;
    if (hour_12 == 0) hour_12 = 12;  // 0点显示为12点
    snprintf(time_str, sizeof(time_str), "%d:%02d:%02d",
             hour_12, tm_info->tm_min, tm_info->tm_sec);
    data_manager_update(DATA_TYPE_TIME, time_str, 0);

    // 更新时段描述（根据小时返回更丰富的描述）
    const char *time_period;
    int hour = tm_info->tm_hour;
    if (hour >= 0 && hour < 6) {
        time_period = "凌晨";
    } else if (hour >= 6 && hour < 8) {
        time_period = "早上";
    } else if (hour >= 8 && hour < 12) {
        time_period = "上午";
    } else if (hour >= 12 && hour < 13) {
        time_period = "中午";
    } else if (hour >= 13 && hour < 18) {
        time_period = "下午";
    } else if (hour >= 18 && hour < 20) {
        time_period = "傍晚";
    } else if (hour >= 20 && hour < 22) {
        time_period = "晚上";
    } else { // 22-24
        time_period = "深夜";
    }
    data_manager_update(DATA_TYPE_AMPM, time_period, 0);

    // 更新日期 YYYY-MM-DD
    char date_str[32];
    snprintf(date_str, sizeof(date_str), "%04d-%02d-%02d",
             tm_info->tm_year + 1900, tm_info->tm_mon + 1, tm_info->tm_mday);
    data_manager_update(DATA_TYPE_DATE, date_str, 0);

    // 更新星期
    const char *weekdays[] = {"星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"};
    data_manager_update(DATA_TYPE_WEEK, weekdays[tm_info->tm_wday], 0);
}

const char *data_manager_get_type_name(data_type_t type)
{
    switch (type) {
        case DATA_TYPE_WAN_IP: return "WAN_IP";
        case DATA_TYPE_WAN6_IP: return "WAN6_IP";
        case DATA_TYPE_LAN_IP: return "LAN_IP";
        case DATA_TYPE_LAN6_IP: return "LAN6_IP";
        case DATA_TYPE_DOWNLOAD_SPEED: return "DOWNLOAD";
        case DATA_TYPE_UPLOAD_SPEED: return "UPLOAD";
        case DATA_TYPE_CPU_USAGE: return "CPU";
        case DATA_TYPE_RAM_USAGE: return "RAM";
        case DATA_TYPE_TEMPERATURE: return "TEMP";
        case DATA_TYPE_FAN_PWM: return "FAN";
        case DATA_TYPE_DISK_USAGE: return "DISK";
        case DATA_TYPE_TIME: return "TIME";
        case DATA_TYPE_AMPM: return "AMPM";
        case DATA_TYPE_DATE: return "DATE";
        case DATA_TYPE_WEEK: return "WEEK";
        default: return "UNKNOWN";
    }
}
