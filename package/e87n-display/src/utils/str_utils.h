#ifndef STR_UTILS_H
#define STR_UTILS_H

#include <stddef.h>
#include <stdint.h>

/**
 * @brief 去除字符串两端的空白字符
 * @param str 输入字符串（会被修改）
 * @return 处理后的字符串指针
 */
char *str_trim(char *str);

/**
 * @brief 格式化字节数为带单位的字符串（自动选择 B/KB/MB/GB）
 * @param bytes 字节数
 * @param out 输出缓冲区
 * @param out_size 缓冲区大小
 * @return 输出字符串指针
 */
char *format_bytes(uint64_t bytes, char *out, size_t out_size);

/**
 * @brief 格式化速度为带单位的字符串
 * @param bytes_per_sec 每秒字节数
 * @param out 输出缓冲区
 * @param out_size 缓冲区大小
 * @return 输出字符串指针
 */
char *format_speed(uint64_t bytes_per_sec, char *out, size_t out_size);

/**
 * @brief 安全字符串复制
 * @param dst 目标缓冲区
 * @param src 源字符串
 * @param size 目标缓冲区大小
 * @return 目标缓冲区指针
 */
char *str_copy(char *dst, const char *src, size_t size);

#endif /* STR_UTILS_H */
