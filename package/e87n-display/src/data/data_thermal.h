#ifndef DATA_THERMAL_H
#define DATA_THERMAL_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化温度数据模块
 * @return 成功返回0，失败返回-1
 */
int data_thermal_init(void);

/**
 * @brief 销毁温度数据模块
 */
void data_thermal_deinit(void);

/**
 * @brief 更新温度数据
 * @return 成功返回0，失败返回-1
 */
int data_thermal_update(void);

/**
 * @brief 获取当前温度（摄氏度）
 * @return 温度值，失败返回0
 */
int32_t data_thermal_get_temperature(void);

/**
 * @brief 检查温度传感器是否可用
 * @return 可用返回true，不可用返回false
 */
bool data_thermal_is_available(void);

#ifdef __cplusplus
}
#endif

#endif /* DATA_THERMAL_H */
