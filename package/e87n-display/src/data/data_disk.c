#include "data_disk.h"
#include "data_manager.h"
#include <stdio.h>
#include <string.h>
#include <sys/statfs.h>

// 默认监控根分区
#define DEFAULT_DISK_PATH "/"

static uint32_t g_disk_usage = 0;
static uint32_t g_total_gb = 0;
static uint32_t g_free_gb = 0;
static bool g_initialized = false;

int data_disk_init(void)
{
    g_disk_usage = 0;
    g_total_gb = 0;
    g_free_gb = 0;
    g_initialized = true;

    printf("[DataDisk] Initialized\n");
    return 0;
}

void data_disk_deinit(void)
{
    g_initialized = false;
    printf("[DataDisk] Deinitialized\n");
}

int data_disk_update(void)
{
    if (!g_initialized) {
        return -1;
    }

    struct statfs fs_info;
    if (statfs(DEFAULT_DISK_PATH, &fs_info) != 0) {
        printf("[DataDisk] Error: failed to get disk info\n");
        return -1;
    }

    // 计算总块数、空闲块数
    unsigned long long total_blocks = fs_info.f_blocks;
    unsigned long long free_blocks = fs_info.f_bfree;
    unsigned long long available_blocks = fs_info.f_bavail;

    if (total_blocks == 0) {
        return -1;
    }

    // 块大小
    unsigned long long block_size = fs_info.f_bsize;

    // 计算总容量和可用空间（GB）
    unsigned long long total_bytes = total_blocks * block_size;
    unsigned long long free_bytes = available_blocks * block_size;
    unsigned long long used_bytes = total_bytes - free_bytes;

    g_total_gb = (uint32_t)(total_bytes / (1024ULL * 1024 * 1024));
    g_free_gb = (uint32_t)(free_bytes / (1024ULL * 1024 * 1024));

    // 计算使用率（基于可用空间）
    g_disk_usage = (uint32_t)((used_bytes * 100) / total_bytes);
    if (g_disk_usage > 100) {
        g_disk_usage = 100;
    }

    // 格式化字符串并更新数据管理器
    char disk_str[32];
    snprintf(disk_str, sizeof(disk_str), "%u %%", g_disk_usage);
    data_manager_update(DATA_TYPE_DISK_USAGE, disk_str, g_disk_usage);

    return 0;
}

uint32_t data_disk_get_usage(void)
{
    return g_disk_usage;
}

uint32_t data_disk_get_total_gb(void)
{
    return g_total_gb;
}

uint32_t data_disk_get_free_gb(void)
{
    return g_free_gb;
}
