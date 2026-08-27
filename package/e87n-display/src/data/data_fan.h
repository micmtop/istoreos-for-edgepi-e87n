#ifndef DATA_FAN_H
#define DATA_FAN_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化风扇数据模块（探测 pwm1 sysfs 路径）
 * @return 成功返回0，失败返回-1
 */
int data_fan_init(void);

/**
 * @brief 销毁风扇数据模块
 */
void data_fan_deinit(void);

/**
 * @brief 更新风扇数据（当前 PWM 占空比）
 * @return 成功返回0，失败返回-1
 */
int data_fan_update(void);

/**
 * @brief 获取当前风扇 PWM 值（0-255）
 * @return PWM 值，失败返回0
 */
uint32_t data_fan_get_pwm(void);

/**
 * @brief 检查风扇 PWM 是否可用
 * @return 可用返回true，不可用返回false
 */
bool data_fan_is_available(void);

#ifdef __cplusplus
}
#endif

#endif /* DATA_FAN_H */