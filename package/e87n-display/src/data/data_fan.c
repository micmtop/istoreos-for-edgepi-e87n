#include "data_fan.h"
#include "data_manager.h"
#include "../utils/file_utils.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>

// 探测 pwm1 所在 hwmon 目录（hwmon 编号会变）
static char g_pwm_path[128] = "";

static int detect_pwm(void)
{
    DIR *dir;
    struct dirent *ent;
    int found = 0;

    dir = opendir("/sys/class/hwmon");
    if (dir) {
        while ((ent = readdir(dir)) != NULL) {
            if (strncmp(ent->d_name, "hwmon", 5) != 0) {
                continue;
            }
            snprintf(g_pwm_path, sizeof(g_pwm_path), "/sys/class/hwmon/%s/pwm1", ent->d_name);
            if (access(g_pwm_path, R_OK) == 0) {
                found = 1;
                break;
            }
        }
        closedir(dir);
    }

    if (!found) {
        // 兜底：直接检查常见编号
        for (int i = 0; i <= 6; i++) {
            snprintf(g_pwm_path, sizeof(g_pwm_path), "/sys/class/hwmon/hwmon%d/pwm1", i);
            if (access(g_pwm_path, R_OK) == 0) {
                found = 1;
                break;
            }
        }
    }
    return found ? 0 : -1;
}

int data_fan_init(void)
{
    if (detect_pwm() != 0) {
        printf("[DataFan] No pwm1 found\n");
        g_pwm_path[0] = '\0';
        return -1;
    }
    printf("[DataFan] Initialized, pwm: %s\n", g_pwm_path);
    data_fan_update();
    return 0;
}

void data_fan_deinit(void)
{
    g_pwm_path[0] = '\0';
}

int data_fan_update(void)
{
    int pwm = 0;

    if (g_pwm_path[0] == '\0' || access(g_pwm_path, R_OK) != 0) {
        // 容错：路径失效时重新探测
        if (detect_pwm() != 0 || g_pwm_path[0] == '\0') {
            return -1;
        }
    }

    if (file_read_int(g_pwm_path, &pwm) != 0) {
        return -1;
    }

    if (pwm < 0 || pwm > 255) {
        pwm = 0;
    }

    char buf[32];
    snprintf(buf, sizeof(buf), "风扇 %d", pwm);
    data_manager_update(DATA_TYPE_FAN_PWM, buf, (uint32_t)pwm);

    return 0;
}

uint32_t data_fan_get_pwm(void)
{
    return data_manager_get_int(DATA_TYPE_FAN_PWM);
}

bool data_fan_is_available(void)
{
    return g_pwm_path[0] != '\0';
}