#ifndef DATA_NETWORK_H
#define DATA_NETWORK_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化网络数据模块
 * @return 成功返回0，失败返回-1
 */
int data_network_init(void);

/**
 * @brief 销毁网络数据模块
 */
void data_network_deinit(void);

/**
 * @brief 更新网络数据（读取 /proc/net/dev，计算速度）
 * @return 成功返回0，失败返回-1
 */
int data_network_update(void);

/**
 * @brief 设置要监控的网络接口
 * @param iface 接口名称（如 "eth0", "wan"）
 */
void data_network_set_interface(const char *iface);

/**
 * @brief 获取当前 WAN IP
 * @return IP 字符串，失败返回 NULL
 */
const char *data_network_get_wan_ip(void);

/**
 * @brief 获取当前 WAN IPv6 地址
 * @return IPv6 字符串，失败返回 NULL
 */
const char *data_network_get_wan6_ip(void);

/**
 * @brief 获取当前 LAN IP (br-lan 接口)
 * @return IP 字符串，失败返回 NULL
 */
const char *data_network_get_lan_ip(void);

/**
 * @brief 获取当前 LAN IPv6 地址
 * @return IPv6 字符串，失败返回 NULL
 */
const char *data_network_get_lan6_ip(void);

#ifdef __cplusplus
}
#endif

#endif /* DATA_NETWORK_H */
