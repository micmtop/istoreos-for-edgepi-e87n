#ifndef DATA_DISK_H
#define DATA_DISK_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化磁盘数据模块
 * @return 成功返回0，失败返回-1
 */
int data_disk_init(void);

/**
 * @brief 销毁磁盘数据模块
 */
void data_disk_deinit(void);

/**
 * @brief 更新磁盘使用数据
 * @return 成功返回0，失败返回-1
 */
int data_disk_update(void);

/**
 * @brief 获取磁盘使用率
 * @return 磁盘使用率百分比 (0-100)
 */
uint32_t data_disk_get_usage(void);

/**
 * @brief 获取磁盘总容量（GB）
 * @return 总容量GB
 */
uint32_t data_disk_get_total_gb(void);

/**
 * @brief 获取磁盘可用空间（GB）
 * @return 可用空间GB
 */
uint32_t data_disk_get_free_gb(void);

#ifdef __cplusplus
}
#endif

#endif /* DATA_DISK_H */
