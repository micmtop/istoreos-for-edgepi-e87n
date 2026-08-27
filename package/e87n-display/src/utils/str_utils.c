#include "str_utils.h"
#include <stdio.h>
#include <string.h>
#include <ctype.h>

char *str_trim(char *str)
{
    if (!str) {
        return NULL;
    }

    // 去除头部空白
    while (isspace((unsigned char)*str)) {
        str++;
    }

    // 去除尾部空白
    if (*str) {
        char *end = str + strlen(str) - 1;
        while (end > str && isspace((unsigned char)*end)) {
            end--;
        }
        end[1] = '\0';
    }

    return str;
}

char *format_bytes(uint64_t bytes, char *out, size_t out_size)
{
    const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int unit_idx = 0;
    double value = (double)bytes;

    while (value >= 1024.0 && unit_idx < 4) {
        value /= 1024.0;
        unit_idx++;
    }

    if (unit_idx == 0) {
        snprintf(out, out_size, "%d %s", (int)value, units[unit_idx]);
    } else {
        snprintf(out, out_size, "%.2f %s", value, units[unit_idx]);
    }

    return out;
}

char *format_speed(uint64_t bytes_per_sec, char *out, size_t out_size)
{
    const char *units[] = {"B/s", "KB/s", "MB/s", "GB/s"};
    int unit_idx = 0;
    double speed = (double)bytes_per_sec;

    while (speed >= 1024.0 && unit_idx < 3) {
        speed /= 1024.0;
        unit_idx++;
    }

    if (unit_idx == 0) {
        snprintf(out, out_size, "%d %s", (int)speed, units[unit_idx]);
    } else {
        snprintf(out, out_size, "%.2f %s", speed, units[unit_idx]);
    }

    return out;
}

char *str_copy(char *dst, const char *src, size_t size)
{
    if (!dst || !src || size == 0) {
        return dst;
    }

    strncpy(dst, src, size - 1);
    dst[size - 1] = '\0';
    return dst;
}
