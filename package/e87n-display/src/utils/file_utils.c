#include "file_utils.h"
#include <stdio.h>
#include <string.h>

int file_read(const char *path, char *buf, size_t size)
{
    if (!path || !buf || size == 0) {
        return -1;
    }

    FILE *fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }

    size_t n = fread(buf, 1, size - 1, fp);
    fclose(fp);

    if (n > 0) {
        buf[n] = '\0';
        // 移除末尾的换行符
        if (n > 0 && buf[n - 1] == '\n') {
            buf[n - 1] = '\0';
        }
        return 0;
    }

    return -1;
}

int file_read_line(const char *path, char *buf, size_t size)
{
    if (!path || !buf || size == 0) {
        return -1;
    }

    FILE *fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }

    if (fgets(buf, (int)size, fp) != NULL) {
        fclose(fp);
        // 移除末尾的换行符
        size_t len = strlen(buf);
        if (len > 0 && buf[len - 1] == '\n') {
            buf[len - 1] = '\0';
        }
        return 0;
    }

    fclose(fp);
    return -1;
}

int file_read_int(const char *path, int *value)
{
    char buf[32];
    if (file_read_line(path, buf, sizeof(buf)) != 0) {
        return -1;
    }

    if (sscanf(buf, "%d", value) != 1) {
        return -1;
    }

    return 0;
}

int file_read_ulong(const char *path, unsigned long *value)
{
    char buf[64];
    if (file_read_line(path, buf, sizeof(buf)) != 0) {
        return -1;
    }

    if (sscanf(buf, "%lu", value) != 1) {
        return -1;
    }

    return 0;
}

int file_read_ullong(const char *path, unsigned long long *value)
{
    char buf[64];
    if (file_read_line(path, buf, sizeof(buf)) != 0) {
        return -1;
    }

    if (sscanf(buf, "%llu", value) != 1) {
        return -1;
    }

    return 0;
}
