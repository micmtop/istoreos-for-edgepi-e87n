/*
 * e87n_metrics.c - 读取 /var/run/e87n/metrics.json
 *
 * 只解析我们自己生成的扁平 JSON（见 e87n-metrics），不引入 JSON 库。
 * 编译: 直接和你的源码一起编即可（gcc/clang，C99）。
 */
#include "e87n_metrics.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define E87N_JSON_MAX 2048

static const char *find_key(const char *json, const char *key)
{
    char pat[64];
    const char *p;

    if (!json || !key || strlen(key) + 3 >= sizeof(pat))
        return NULL;

    snprintf(pat, sizeof(pat), "\"%s\"", key);
    p = strstr(json, pat);
    if (!p)
        return NULL;

    p += strlen(pat);
    while (*p == ' ' || *p == '\t')
        p++;
    if (*p != ':')
        return NULL;
    p++;
    while (*p == ' ' || *p == '\t')
        p++;
    return p;
}

static long jnum(const char *json, const char *key, long dflt)
{
    const char *p = find_key(json, key);
    char *end = NULL;
    long v;

    if (!p)
        return dflt;
    v = strtol(p, &end, 10);
    if (end == p)
        return dflt;
    return v;
}

static void jstr(const char *json, const char *key, char *out, size_t outlen)
{
    const char *p = find_key(json, key);
    size_t n = 0;

    if (!out || outlen == 0)
        return;
    out[0] = '\0';
    if (!p || *p != '"')
        return;
    p++;
    while (*p && *p != '"' && n + 1 < outlen) {
        /* 我们生成的字符串里只可能有 IP/枚举，不处理转义 */
        out[n++] = *p++;
    }
    out[n] = '\0';
}

const char *e87n_metrics_json(char *buf, size_t buflen)
{
    FILE *fp;
    size_t n;

    if (!buf || buflen < 8)
        return NULL;

    fp = fopen(E87N_METRICS_PATH, "r");
    if (!fp)
        return NULL;

    n = fread(buf, 1, buflen - 1, fp);
    fclose(fp);
    buf[n] = '\0';

    return n ? buf : NULL;
}

int e87n_metrics_read(e87n_metrics_t *out)
{
    static char json[E87N_JSON_MAX];

    if (!out)
        return -1;
    memset(out, 0, sizeof(*out));

    if (!e87n_metrics_json(json, sizeof(json)))
        return -1;

    out->ts        = (int)jnum(json, "ts", 0);
    out->uptime    = (int)jnum(json, "uptime", 0);
    out->temp_c    = (int)jnum(json, "temp_c", -1);
    out->temp_ok   = (int)jnum(json, "temp_ok", 0);
    out->cpu_pct   = (int)jnum(json, "cpu_pct", -1);
    out->ram_pct   = (int)jnum(json, "ram_pct", -1);
    out->disk_pct  = (int)jnum(json, "disk_pct", -1);
    out->fan_pwm   = (int)jnum(json, "fan_pwm", -1);
    out->fan_pct   = (int)jnum(json, "fan_pct", -1);
    out->rx_bps    = (unsigned long)jnum(json, "rx_bps", 0);
    out->clients   = (int)jnum(json, "clients", -1);
    out->tx_bps    = (unsigned long)jnum(json, "tx_bps", 0);

    jstr(json, "fan_mode",     out->fan_mode,     sizeof(out->fan_mode));
    jstr(json, "net_iface",    out->net_iface,    sizeof(out->net_iface));
    jstr(json, "wan_ip",       out->wan_ip,       sizeof(out->wan_ip));
    jstr(json, "wan6",         out->wan6,         sizeof(out->wan6));
    jstr(json, "lan_ip",       out->lan_ip,       sizeof(out->lan_ip));
    jstr(json, "lan6",         out->lan6,         sizeof(out->lan6));
    jstr(json, "backlight",    out->backlight,    sizeof(out->backlight));
    jstr(json, "display_page", out->display_page, sizeof(out->display_page));
    jstr(json, "saying",       out->saying,       sizeof(out->saying));

    return 0;
}
