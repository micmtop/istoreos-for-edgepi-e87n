#ifndef DATA_SYSTEM_H
#define DATA_SYSTEM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化系统数据模块
 * @return 成功返回0，失败返回-1
 */
int data_system_init(void);

/**
 * @brief 销毁系统数据模块
 */
void data_system_deinit(void);

/**
 * @brief 更新系统数据（CPU、RAM）
 * @return 成功返回0，失败返回-1
 */
int data_system_update(void);

/**
 * @brief 获取 CPU 使用率（0-100）
 * @return CPU 使用率百分比
 */
uint32_t data_system_get_cpu_usage(void);

/**
 * @brief 获取内存使用率（0-100）
 * @return 内存使用率百分比
 */
uint32_t data_system_get_ram_usage(void);

#ifdef __cplusplus
}
#endif

#endif /* DATA_SYSTEM_H */
