#include "data_thermal.h"
#include "data_manager.h"
#include "../utils/file_utils.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// 常见温度传感器路径
static const char *g_thermal_paths[] = {
    "/sys/class/thermal/thermal_zone0/temp",
    "/sys/class/thermal/thermal_zone1/temp",
    "/sys/class/hwmon/hwmon0/temp1_input",
    "/sys/class/hwmon/hwmon1/temp1_input",
    NULL
};

static char g_active_path[128] = "";
static int32_t g_temperature = 0;
static bool g_available = false;

// 探测可用的温度传感器
static int detect_thermal_sensor(void)
{
    for (int i = 0; g_thermal_paths[i] != NULL; i++) {
        if (access(g_thermal_paths[i], R_OK) == 0) {
            // 尝试读取验证
            int temp;
            if (file_read_int(g_thermal_paths[i], &temp) == 0) {
                if (temp > 0 && temp < 150000) {  // 合理的温度范围 0-150°C（千分之一度）
                    strncpy(g_active_path, g_thermal_paths[i], sizeof(g_active_path) - 1);
                    g_active_path[sizeof(g_active_path) - 1] = '\0';
                    return 0;
                }
            }
        }
    }
    return -1;
}

int data_thermal_init(void)
{
    g_temperature = 0;
    g_available = false;
    g_active_path[0] = '\0';

    if (detect_thermal_sensor() == 0) {
        g_available = true;
        printf("[DataThermal] Initialized, sensor: %s\n", g_active_path);
        // 立即获取一次温度数据，确保启动时显示正确
        data_thermal_update();
        return 0;
    } else {
        printf("[DataThermal] No thermal sensor found\n");
        return -1;
    }
}

void data_thermal_deinit(void)
{
    printf("[DataThermal] Deinitialized\n");
}

int data_thermal_update(void)
{
    if (!g_available || g_active_path[0] == '\0') {
        return -1;
    }

    int raw_temp;
    if (file_read_int(g_active_path, &raw_temp) != 0) {
        return -1;
    }

    // 转换为摄氏度（通常是千分之一度）
    int32_t temp_celsius;
    if (raw_temp > 1000) {
        // 千分之一度格式
        temp_celsius = raw_temp / 1000;
    } else {
        // 已经是摄氏度
        temp_celsius = raw_temp;
    }

    // 合理性检查
    if (temp_celsius < -40 || temp_celsius > 150) {
        printf("[DataThermal] Warning: abnormal temperature reading: %d\n", temp_celsius);
        return -1;
    }

    g_temperature = temp_celsius;

    // 格式化并更新数据管理器
    char temp_str[32];
    snprintf(temp_str, sizeof(temp_str), "%d ℃", g_temperature);
    data_manager_update(DATA_TYPE_TEMPERATURE, temp_str, (uint32_t)g_temperature);

    return 0;
}

int32_t data_thermal_get_temperature(void)
{
    return g_temperature;
}

bool data_thermal_is_available(void)
{
    return g_available;
}
