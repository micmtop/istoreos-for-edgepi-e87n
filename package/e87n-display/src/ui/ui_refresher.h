#ifndef UI_REFRESHER_H
#define UI_REFRESHER_H

#include "../lib/ui/ui.h"
#include "../data/data_manager.h"
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化 UI 刷新控制器
 * @return 成功返回0，失败返回-1
 */
int ui_refresher_init(void);

/**
 * @brief 销毁 UI 刷新控制器
 */
void ui_refresher_deinit(void);

/**
 * @brief 注册 Label 自动刷新
 * @param type 数据类型
 * @param label 目标 Label 对象
 * @param period_ms 刷新周期（毫秒）
 * @param format 格式字符串（如 "CPU: %s"），为NULL则只显示数据
 * @return 成功返回0，失败返回-1
 */
int ui_refresher_register_label(data_type_t type, lv_obj_t *label,
                                uint32_t period_ms, const char *format);

/**
 * @brief 注销指定数据类型的刷新任务
 * @param type 数据类型
 */
void ui_refresher_unregister_label(data_type_t type);

/**
 * @brief 暂停所有刷新任务
 */
void ui_refresher_pause(void);

/**
 * @brief 恢复所有刷新任务
 */
void ui_refresher_resume(void);

/**
 * @brief 立即刷新所有 Label
 */
void ui_refresher_refresh_now(void);

/**
 * @brief 注册 Screen1 的所有 Label（便捷函数）
 */
void ui_refresher_register_screen1_labels(void);

/**
 * @brief 注销 Screen1 的所有 Label
 */
void ui_refresher_unregister_screen1_labels(void);

/**
 * @brief 注册 Screen2 的所有 Label（时间显示）
 */
void ui_refresher_register_screen2_labels(void);

/**
 * @brief 注销 Screen2 的所有 Label
 */
void ui_refresher_unregister_screen2_labels(void);

/**
 * @brief 注册 Screen3 的图表和标签（网络速度图表）
 */
void ui_refresher_register_screen3_charts(void);

/**
 * @brief 注销 Screen3 的图表和标签
 */
void ui_refresher_unregister_screen3_charts(void);

/**
 * @brief 注册 Screen4 的所有 Arc 和 Label（系统状态圆弧显示）
 */
void ui_refresher_register_screen4_arcs(void);

/**
 * @brief 注销 Screen4 的所有 Arc 和 Label
 */
void ui_refresher_unregister_screen4_arcs(void);

#ifdef __cplusplus
}
#endif

#endif /* UI_REFRESHER_H */
