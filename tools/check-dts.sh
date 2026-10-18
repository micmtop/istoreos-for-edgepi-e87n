#!/bin/sh
# 板级 DTS 静态校验：在进 1.5h 全量编译之前，先确认
#   1) 所有 &label 引用都能解析（dtc 报 phandle_references ERROR 就是这类）
#   2) 屏幕 / 背光 / 风扇 / 两个 PCIe 槽位等关键节点没被误删
# 纯 busybox 兼容（grep/sed/sort），无 python/od。
#
# 用法: sh tools/check-dts.sh [dts 目录]

set -e

DTS_DIR="${1:-files/target/linux/mediatek/dts}"
DTS="$DTS_DIR/mt7987a-edgepi-e87n.dts"

fail=0
err() {
    echo "FAIL: $*"
    fail=1
}

[ -f "$DTS" ] || {
    echo "FAIL: 找不到 $DTS"
    exit 1
}

# ---- 1) 标签引用校验 ----
refs=$(grep -o '&[A-Za-z0-9_][A-Za-z0-9_]*' "$DTS" | sed 's/^&//' | sort -u)

defined=$(
    {
        # 本文件 + 同目录所有 dtsi 里定义的 label（形如 "  foo: bar {"）
        grep -ho '^[[:space:]]*[A-Za-z0-9_][A-Za-z0-9_]*:' "$DTS" "$DTS_DIR"/*.dtsi 2>/dev/null |
            sed 's/^[[:space:]]*//; s/:$//'
    } | sort -u
)

missing=""
for r in $refs; do
    if ! echo "$defined" | grep -qx "$r"; then
        missing="$missing $r"
    fi
done

if [ -n "$missing" ]; then
    err "DTS 引用了不存在的标签:$missing"
    echo "      （dtc 会因此报 phandle_references ERROR 并中止 .dtb 生成）"
fi

# ---- 2) 关键节点存在性 ----
check_node() {
    grep -qF "$1" "$DTS" || err "板级 DTS 缺少关键节点: $1"
}

check_node 'compatible = "newvisionu,nv3007"'   # SPI 屏
check_node 'pwm_fan_pins:'                      # 风扇 pinctrl
check_node 'pwm_backlight_pins:'                # 背光 pinctrl（节点本身 disabled，但引用仍在）
check_node '&pcie0 {'                           # 第一个 M.2
check_node '&pcie1 {'                           # 第二个 M.2 2230
check_node 'phy@3 {'                            # 外置 RTL8221 2.5G
check_node 'phy@15 {'                           # 内置 MT7987 2.5G

# 不应存在的节点（E87N 无 WiFi、无 WPS 键）
for bad in 'mt7992' 'button-wps'; do
    if grep -qF "$bad" "$DTS"; then
        err "板级 DTS 出现了不该有的节点: $bad"
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "DTS 校验未通过"
    exit 1
fi

echo "DTS 校验通过：$(echo "$refs" | wc -l) 个标签引用全部可解析，关键节点齐全"
