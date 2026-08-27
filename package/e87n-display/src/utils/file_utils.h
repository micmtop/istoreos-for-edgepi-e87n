#ifndef FILE_UTILS_H
#define FILE_UTILS_H

#include <stddef.h>

/**
 * @brief 读取整个文件内容到缓冲区
 * @param path 文件路径
 * @param buf 输出缓冲区
 * @param size 缓冲区大小
 * @return 成功返回0，失败返回-1
 */
int file_read(const char *path, char *buf, size_t size);

/**
 * @brief 读取文件的第一行
 * @param path 文件路径
 * @param buf 输出缓冲区
 * @param size 缓冲区大小
 * @return 成功返回0，失败返回-1
 */
int file_read_line(const char *path, char *buf, size_t size);

/**
 * @brief 从文件中读取整数
 * @param path 文件路径
 * @param value 输出整数指针
 * @return 成功返回0，失败返回-1
 */
int file_read_int(const char *path, int *value);

/**
 * @brief 从文件中读取无符号长整数
 * @param path 文件路径
 * @param value 输出值指针
 * @return 成功返回0，失败返回-1
 */
int file_read_ulong(const char *path, unsigned long *value);

/**
 * @brief 从文件中读取无符号长长整数
 * @param path 文件路径
 * @param value 输出值指针
 * @return 成功返回0，失败返回-1
 */
int file_read_ullong(const char *path, unsigned long long *value);

#endif /* FILE_UTILS_H */
