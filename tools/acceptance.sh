#!/bin/sh
# acceptance.sh - E87N 硬件与基础功能自检
#
# 在设备上直接运行：sh acceptance.sh
# 只读检查，不改任何状态。输出 [PASS]/[FAIL]/[INFO] 与汇总。
#
# 覆盖：系统 / eMMC / 网口与 PHY / HNAT+flow offload / 风扇+温度 /
#       LED+按键 / USB / PCIe+NVMe / 屏幕+背光 / 服务与接口 / 主题

FAILED=0
PASSED=0

ok()   { PASSED=$((PASSED+1)); printf '[PASS] %s\n' "$*"; }
bad()  { FAILED=$((FAILED+1)); printf '[FAIL] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

need() {   # need <desc> <cmd...>
    d=$1; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

# ---------------- 系统 ----------------
echo "== 系统 =="
info "kernel: $(uname -r) $(uname -v | cut -c1-40)"
info "model : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
info "uptime: $(cut -d. -f1 /proc/uptime)s"
info "hostname: $(uci -q get system.@system[0].hostname)"
mount | grep -q ' / .*overlay' && ok "overlay 已挂载（可写）" || bad "overlay 未挂载"
touch /overlay/.accept_test 2>/dev/null && { rm -f /overlay/.accept_test; ok "overlay 可写"; } || bad "overlay 只读"
[ -f /etc/config/network ] && ok "/etc/config/network 存在" || bad "/etc/config/network 缺失"

# ---------------- eMMC ----------------
echo "== eMMC =="
for p in 1 2 3 4 5; do
    [ -b "/dev/mmcblk0p$p" ] && ok "分区 p$p 存在" || bad "分区 p$p 缺失"
done
[ -b /dev/mmcblk0boot0 ] && ok "boot0 存在" || bad "boot0 缺失"
info "p3(FIP) sha256: $(sha256sum /dev/mmcblk0p3 2>/dev/null | cut -c1-16)..."
info "p4 前 4 字节: $(head -c 4 /dev/mmcblk0p4 2>/dev/null | hexdump -C 2>/dev/null | head -1)"

# ---------------- 网口 / PHY ----------------
echo "== 网络接口 =="
for i in eth0 eth1 br-lan; do
    if [ -e "/sys/class/net/$i" ]; then
        ok "接口 $i 存在 (carrier=$(cat /sys/class/net/$i/carrier 2>/dev/null))"
    else
        bad "接口 $i 缺失"
    fi
done
# PHY 驱动绑定：mdio-bus:03 应为 RTL8221 / mdio-bus:0f 应为 MT7987 2.5G
for a in 03 0f; do
    d=""
    for l in /sys/bus/mdio_bus/devices/mdio-bus:$a/driver; do
        [ -e "$l" ] && d=$(basename "$(readlink -f "$l")")
    done
    if [ -n "$d" ]; then ok "mdio-bus:$a -> $d"; else bad "mdio-bus:$a 未绑定驱动"; fi
done
dmesg | grep -q "MediaTek MT7987 2.5GbE PHY" && ok "MT7987 2.5G PHY 驱动已加载" || bad "MT7987 2.5G PHY 驱动未加载"
info "eth0 MAC: $(cat /sys/class/net/eth0/address 2>/dev/null)  eth1 MAC: $(cat /sys/class/net/eth1/address 2>/dev/null)"
info "br-lan 成员: $(ls /sys/class/net/br-lan/brif 2>/dev/null | tr '\n' ' ')"
info "IPv4: $(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}')"

# ---------------- HNAT / 硬件加速 ----------------
echo "== HNAT / 卸载 =="
[ -n "$(lsmod 2>/dev/null | grep -E '^mtk_ppe|^nf_flow_table')" ] || true
for m in nf_flow_table nf_flow_table_inet nft_flow_offload; do
    if lsmod 2>/dev/null | grep -q "^$m" || [ -d "/sys/module/$m" ]; then ok "模块 $m"; else bad "模块 $m 未加载"; fi
done
if [ -d /sys/module/mtk_ppe ] || lsmod 2>/dev/null | grep -q mtk_ppe; then ok "mtk_ppe 存在"; else info "mtk_ppe 不存在（可能内建或被改名）"; fi
if ls /sys/kernel/debug/ppe* >/dev/null 2>&1; then ok "PPE 调试节点可见"; else info "PPE 调试节点不可见（需要挂载 debugfs）"; fi
fw=$(uci -q get firewall.@defaults[0].flow_offloading)
hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw)
info "防火墙 flow_offloading=$fw hw=$hw"
[ "$fw" = "1" ] && ok "软件 flow offload 已开启" || bad "软件 flow offload 未开启"
[ "$hw" = "1" ] && ok "硬件 flow offload 已开启" || info "硬件 flow offload 未开启"
info "ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)"
info "conntrack 当前/最大: $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)/$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"

# ---------------- 风扇 / 温度 ----------------
echo "== 风扇 / 温度 =="
PWM=""; for f in /sys/class/hwmon/hwmon*/pwm1; do [ -r "$f" ] && PWM=$f; done
[ -n "$PWM" ] && ok "风扇 PWM 节点存在 ($PWM=$(cat $PWM))" || bad "未找到风扇 PWM"
RPM=""; for f in /sys/class/hwmon/hwmon*/fan1_input; do [ -r "$f" ] && RPM=$f; done
[ -n "$RPM" ] && info "风扇转速: $(cat $RPM) RPM" || info "无转速回读"
T=""
for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp1_input; do
    [ -r "$f" ] && { T=$f; break; }
done
[ -n "$T" ] && ok "温度传感器 $T = $(( $(cat $T) / 1000 ))°C" || bad "未找到温度传感器"
pidof fan-control >/dev/null 2>&1 && ok "fan-control 运行中" || bad "fan-control 未运行"

# ---------------- 风扇是否真的听用户态 ----------------
echo "== 风扇控制权 =="
FAN_MODE=$(uci -q get fan.global.mode)
FAN_PWM=$(for p in /sys/class/hwmon/hwmon*/pwm1; do [ -f "$p" ] && cat "$p" && break; done)
if [ "$FAN_MODE" = "auto" ] && [ -x /usr/sbin/fan-control ] && [ -n "$FAN_PWM" ]; then
    T=$(for h in /sys/class/hwmon/hwmon*; do [ -f "$h/temp1_input" ] && cat "$h/temp1_input" && break; done)
    TC=$(( ${T:-0} / 1000 ))
    EXP=$(/usr/sbin/fan-control calc "$TC" 2>/dev/null)
    if [ -n "$EXP" ]; then
        DIFF=$(( FAN_PWM - EXP )); [ "$DIFF" -lt 0 ] && DIFF=$(( -DIFF ))
        if [ "$DIFF" -le 12 ]; then
            ok "风扇跟随曲线：${TC}°C 期望 pwm=$EXP，实际 $FAN_PWM"
        else
            bad "风扇未跟随曲线：${TC}°C 期望 pwm=$EXP，实际 $FAN_PWM（内核 thermal 是否又在抢控制？）"
        fi
    fi
else
    info "风扇 mode=$FAN_MODE，跳过曲线核对"
fi
# 内核 cooling-map 不应再引用 fan：被映射时 cur_state 会被 governor 改写
if [ -e /sys/class/thermal/cooling_device0/cur_state ]; then
    info "cooling_device0(pwm-fan) cur_state=$(cat /sys/class/thermal/cooling_device0/cur_state)（未被 zone 映射时不再变化）"
fi

# ---------------- LED / 按键 ----------------
echo "== LED / 按键 =="
for l in /sys/class/leds/*; do
    [ -d "$l" ] && info "LED $(basename $l) trigger=$(cat $l/trigger 2>/dev/null | tr ' ' '\n' | grep -m1 '\[' | tr -d '[]')"
done
ls /sys/class/leds/ | grep -q . && ok "LED 设备存在" || bad "没有 LED 设备"
ls /sys/class/gpio/gpio524 >/dev/null 2>&1 && info "背光 GPIO524 已导出" || info "背光 GPIO524 未导出（由 screen-ctl 管理）"

# ---------------- USB ----------------
echo "== USB =="
[ -d /sys/bus/usb ] && ok "USB 子系统存在" || bad "USB 子系统缺失"
info "USB bus: $(ls /sys/bus/usb/devices 2>/dev/null | tr '\n' ' ')"
for c in /sys/bus/platform/devices/*usb* /sys/bus/platform/devices/*xhci*; do
    [ -e "$c" ] && info "控制器: $(basename $c)"
done
grep -qi "xhci" /proc/interrupts 2>/dev/null && ok "xhci 中断已注册" || info "xhci 未见中断"

# ---------------- PCIe / NVMe ----------------
echo "== PCIe / NVMe =="
# E87N 两个 M.2 2230 槽位各挂一个控制器：11280000 = pcie0，11290000 = pcie1
n_ok=0
for d in /proc/device-tree/soc/pcie@*; do
    [ -d "$d" ] || continue
    st=$(tr -d '\000' < "$d/status" 2>/dev/null)
    st=${st:-okay}
    info "控制器 $(basename $d) status=$st"
    [ "$st" = "okay" ] && n_ok=$((n_ok + 1))
done
if [ "$n_ok" -ge 2 ]; then
    ok "两个 PCIe 控制器都已启用"
else
    bad "PCIe 控制器启用数量 $n_ok（期望 2，检查 DTS 的 &pcie0 / &pcie1）"
fi

down=$(dmesg | grep -c "PCIe link down")
if [ -n "$(ls /sys/bus/pci/devices 2>/dev/null)" ]; then
    ok "PCI 总线有设备：$(ls /sys/bus/pci/devices | wc -l) 个"
    for d in /sys/bus/pci/devices/*; do
        info "  $(basename $d) vendor=$(cat $d/vendor 2>/dev/null) device=$(cat $d/device 2>/dev/null) class=$(cat $d/class 2>/dev/null)"
    done
elif [ "$down" -gt 0 ]; then
    ok "槽位空置（$down 条 link down，无卡属正常）"
else
    bad "PCIe 既没有设备也没有 link down 记录（控制器可能没 probe）"
fi
if [ -d /sys/module/nvme ] || lsmod 2>/dev/null | grep -q '^nvme'; then ok "nvme 驱动已加载"; else info "nvme 驱动未加载（未插盘/未装包）"; fi

# ---------------- iStoreOS 商店 / 向导 ----------------
echo "== 商店 / 向导 =="
# 商店是 Lua 时代的 app（controller + view 在 /usr/lib/lua/luci/ 下），
# 不是 JS 的 menu.d/resources 结构，两种都认，避免误判。
if [ -f /usr/lib/lua/luci/controller/store.lua ] ||
   [ -f /usr/share/luci/menu.d/luci-app-store.json ] ||
   [ -f /www/luci-static/resources/view/store/main.js ]; then
    ok "iStore 商店已安装（$(ls /usr/lib/lua/luci/controller/store.lua 2>/dev/null || echo JS))"
else
    bad "iStore 商店缺失（luci-app-store 没进固件）"
fi
[ -e /etc/init.d/istore ] && ok "istore 服务存在" || info "istore 服务未见"
if [ -f /usr/share/luci/menu.d/luci-app-quickstart.json ]; then
    ok "网络向导前端已安装"
else
    bad "网络向导缺失（luci-app-quickstart 没进固件）"
fi
[ -x /usr/sbin/quickstart ] && ok "quickstart 守护进程存在" || bad "quickstart 守护进程缺失"

# ---------------- 屏幕 / 背光 ----------------
echo "== 屏幕 =="
if [ -e /sys/class/graphics/fb0 ]; then
    ok "fb0: $(cat /sys/class/graphics/fb0/name 2>/dev/null) size=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null) bpp=$(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null)"
else
    bad "没有 /dev/fb0"
fi
dmesg | grep -q "fb_nv3007 frame buffer" && ok "NV3007 驱动 probe 成功" || bad "NV3007 未 probe"
[ -x /usr/sbin/screen-ctl ] && { /usr/sbin/screen-ctl status 2>/dev/null | sed 's/^/  /'; ok "screen-ctl 可用"; } || bad "screen-ctl 缺失"

# ---------------- 服务 / 接口 ----------------
echo "== 服务与接口 =="
pidof e87n-display >/dev/null 2>&1 && ok "e87n-display 运行中" || info "e87n-display 未运行（可能正在显示主题）"
[ -f /var/run/e87n-display.pid ] && kill -0 "$(cat /var/run/e87n-display.pid)" 2>/dev/null && ok "主题进程运行中"
pidof e87n-metrics >/dev/null 2>&1 && ok "e87n-metrics 运行中" || bad "e87n-metrics 未运行"
[ -r /var/run/e87n/metrics.json ] && ok "metrics.json 可读" || bad "metrics.json 缺失"
if [ -x /usr/sbin/e87n-metrics ]; then
    n=$(/usr/sbin/e87n-metrics once 2>/dev/null | tr ',' '\n' | wc -l)
    [ "$n" -gt 10 ] && ok "e87n-metrics 输出字段数 $n" || bad "e87n-metrics 输出异常"
fi
ubus call e87n status >/dev/null 2>&1 && ok "ubus e87n status 可用" || bad "ubus e87n 不可用"
[ -x /usr/sbin/e87n-theme ] && { info "主题: $(/usr/sbin/e87n-theme list 2>/dev/null)"; ok "e87n-theme 可用"; } || info "e87n-theme 未安装"
[ -x /usr/sbin/e87n-saying ] && ok "e87n-saying 可用（$(e87n-saying show 2>/dev/null | cut -c1-20)...）" || info "e87n-saying 未安装"

# ---------------- 汇总 ----------------
echo
echo "RESULT: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && echo "ALL CRITICAL CHECKS PASSED" || echo "SOME CHECKS FAILED (see [FAIL] above)"
exit 0
