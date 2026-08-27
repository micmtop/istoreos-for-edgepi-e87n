#include "data_system.h"
#include "data_manager.h"
#include "../utils/file_utils.h"
#include <stdio.h>
#include <string.h>

#define PROC_STAT "/proc/stat"
#define PROC_MEMINFO "/proc/meminfo"

// CPU 统计信息
typedef struct {
    unsigned long user;
    unsigned long nice;
    unsigned long system;
    unsigned long idle;
    unsigned long iowait;
    unsigned long irq;
    unsigned long softirq;
} cpu_stat_t;

static cpu_stat_t g_last_cpu_stat = {0};
static bool g_first_cpu_read = true;
static uint32_t g_cpu_usage = 0;
static uint32_t g_ram_usage = 0;

// 读取 /proc/stat 中的 CPU 信息
static int read_proc_stat(cpu_stat_t *stat)
{
    FILE *fp = fopen(PROC_STAT, "r");
    if (!fp) {
        return -1;
    }

    char line[256];
    if (fgets(line, sizeof(line), fp) != NULL) {
        // 解析 "cpu  user nice system idle iowait irq softirq ..."
        if (sscanf(line, "cpu %lu %lu %lu %lu %lu %lu %lu",
                   &stat->user, &stat->nice, &stat->system,
                   &stat->idle, &stat->iowait, &stat->irq, &stat->softirq) == 7) {
            fclose(fp);
            return 0;
        }
    }

    fclose(fp);
    return -1;
}

// 计算 CPU 使用率
static uint32_t calculate_cpu_usage(const cpu_stat_t *prev, const cpu_stat_t *curr)
{
    unsigned long prev_idle = prev->idle + prev->iowait;
    unsigned long curr_idle = curr->idle + curr->iowait;

    unsigned long prev_total = prev->user + prev->nice + prev->system +
                               prev->idle + prev->iowait + prev->irq + prev->softirq;
    unsigned long curr_total = curr->user + curr->nice + curr->system +
                               curr->idle + curr->iowait + curr->irq + curr->softirq;

    unsigned long total_diff = curr_total - prev_total;
    unsigned long idle_diff = curr_idle - prev_idle;

    if (total_diff == 0) {
        return 0;
    }

    uint32_t usage = (uint32_t)(((total_diff - idle_diff) * 100) / total_diff);

    // 限制范围 0-100
    if (usage > 100) usage = 100;

    return usage;
}

// 读取内存信息并计算使用率
static int read_meminfo(void)
{
    FILE *fp = fopen(PROC_MEMINFO, "r");
    if (!fp) {
        return -1;
    }

    unsigned long mem_total = 0;
    unsigned long mem_available = 0;
    unsigned long mem_free = 0;
    unsigned long buffers = 0;
    unsigned long cached = 0;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "MemTotal:", 9) == 0) {
            sscanf(line, "MemTotal: %lu", &mem_total);
        } else if (strncmp(line, "MemAvailable:", 13) == 0) {
            sscanf(line, "MemAvailable: %lu", &mem_available);
        } else if (strncmp(line, "MemFree:", 8) == 0) {
            sscanf(line, "MemFree: %lu", &mem_free);
        } else if (strncmp(line, "Buffers:", 8) == 0) {
            sscanf(line, "Buffers: %lu", &buffers);
        } else if (strncmp(line, "Cached:", 7) == 0) {
            sscanf(line, "Cached: %lu", &cached);
        }
    }

    fclose(fp);

    if (mem_total == 0) {
        return -1;
    }

    // 优先使用 MemAvailable（Linux 3.14+）
    unsigned long mem_used;
    if (mem_available > 0) {
        mem_used = mem_total - mem_available;
    } else {
        // 旧内核使用 MemFree + Buffers + Cached
        mem_used = mem_total - mem_free - buffers - cached;
    }

    g_ram_usage = (uint32_t)((mem_used * 100) / mem_total);

    // 限制范围
    if (g_ram_usage > 100) g_ram_usage = 100;

    return 0;
}

int data_system_init(void)
{
    g_first_cpu_read = true;
    memset(&g_last_cpu_stat, 0, sizeof(g_last_cpu_stat));
    g_cpu_usage = 0;
    g_ram_usage = 0;

    printf("[DataSystem] Initialized\n");

    // 立即获取一次系统数据，确保启动时显示正确
    // 第一次CPU读取会作为基准，实际使用率需要在第二次更新时计算
    data_system_update();

    return 0;
}

void data_system_deinit(void)
{
    printf("[DataSystem] Deinitialized\n");
}

int data_system_update(void)
{
    // 更新 CPU
    cpu_stat_t current_stat;
    if (read_proc_stat(&current_stat) == 0) {
        if (!g_first_cpu_read) {
            g_cpu_usage = calculate_cpu_usage(&g_last_cpu_stat, &current_stat);
        } else {
            g_first_cpu_read = false;
            g_cpu_usage = 0;
        }
        g_last_cpu_stat = current_stat;

        // 格式化并更新数据管理器
        char cpu_str[32];
        snprintf(cpu_str, sizeof(cpu_str), "%u %%", g_cpu_usage);
        data_manager_update(DATA_TYPE_CPU_USAGE, cpu_str, g_cpu_usage);
    }

    // 更新 RAM
    if (read_meminfo() == 0) {
        char ram_str[32];
        snprintf(ram_str, sizeof(ram_str), "%u %%", g_ram_usage);
        data_manager_update(DATA_TYPE_RAM_USAGE, ram_str, g_ram_usage);
    }

    return 0;
}

uint32_t data_system_get_cpu_usage(void)
{
    return g_cpu_usage;
}

uint32_t data_system_get_ram_usage(void)
{
    return g_ram_usage;
}
