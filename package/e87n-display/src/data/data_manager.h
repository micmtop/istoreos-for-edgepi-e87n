#ifndef DATA_MANAGER_H
#define DATA_MANAGER_H

#include <stdint.h>
#include <stdbool.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 数据类型枚举
 */
typedef enum {
    DATA_TYPE_NONE = 0,
    DATA_TYPE_WAN_IP,
    DATA_TYPE_WAN6_IP,          // WAN IPv6 地址
    DATA_TYPE_LAN_IP,           // LAN IPv4 地址
    DATA_TYPE_LAN6_IP,          // LAN IPv6 地址
    DATA_TYPE_DOWNLOAD_SPEED,
    DATA_TYPE_UPLOAD_SPEED,
    DATA_TYPE_CPU_USAGE,
    DATA_TYPE_RAM_USAGE,
    DATA_TYPE_TEMPERATURE,
    DATA_TYPE_FAN_PWM,          // 风扇 PWM 占空比 0-255
    DATA_TYPE_DISK_USAGE,       // 磁盘占用率
    DATA_TYPE_TIME,             // 时间 HH:MM:SS
    DATA_TYPE_AMPM,             // 上午/下午
    DATA_TYPE_DATE,             // 日期 YYYY-MM-DD
    DATA_TYPE_WEEK,             // 星期
    DATA_TYPE_MAX
} data_type_t;

/**
 * @brief 数据项结构
 */
typedef struct {
    data_type_t type;
    char value_str[64];     // 格式化后的字符串值
    uint32_t value_int;     // 原始数值
    time_t timestamp;       // 最后更新时间
    bool valid;             // 数据是否有效
} data_item_t;

/**
 * @brief 初始化数据管理器
 * @return 成功返回0，失败返回-1
 */
int data_manager_init(void);

/**
 * @brief 销毁数据管理器，释放资源
 */
void data_manager_deinit(void);

/**
 * @brief 获取指定数据类型的字符串值
 * @param type 数据类型
 * @return 字符串值指针，如果无效返回"--"
 */
const char *data_manager_get_string(data_type_t type);

/**
 * @brief 获取指定数据类型的整数值
 * @param type 数据类型
 * @return 整数值，如果无效返回0
 */
uint32_t data_manager_get_int(data_type_t type);

/**
 * @brief 检查指定数据类型是否有效
 * @param type 数据类型
 * @return 有效返回true，无效返回false
 */
bool data_manager_is_valid(data_type_t type);

/**
 * @brief 更新指定数据类型的值
 * @param type 数据类型
 * @param str_val 字符串值（可为NULL）
 * @param int_val 整数值
 * @return 成功返回0，失败返回-1
 */
int data_manager_update(data_type_t type, const char *str_val, uint32_t int_val);

/**
 * @brief 刷新所有数据（调用各数据模块的更新函数）
 */
void data_manager_refresh_all(void);

/**
 * @brief 更新时间数据（时间、日期、星期）
 */
void data_manager_update_time(void);

/**
 * @brief 获取数据类型的名称（用于调试）
 * @param type 数据类型
 * @return 类型名称字符串
 */
const char *data_manager_get_type_name(data_type_t type);

#ifdef __cplusplus
}
#endif

#endif /* DATA_MANAGER_H */
