#!/bin/sh
# preflash.sh — 刷机前先礼貌地结束 PPPoE 会话，避免刷完机后 BRAS 残留会话
# 导致 LCP 黑洞（现象：发现阶段成功、LCP timeout 30 秒 ×3，必须断电光猫 5 分钟）。
#
# 原理：ifdown wan 会让 pppd 发出 PADT，主动通知 BRAS 释放会话。
#       等 BRAS 处理完再刷机，重启后拨号就不会撞上残留会话。
#
# 用法：
#   sh /root/preflash.sh                # 默认刷 /tmp/fw.bin
#   sh /root/preflash.sh /tmp/xxx.bin   # 指定固件
#   sh /root/preflash.sh --pad-only     # 只做终止会话这一步，不刷机（可用来观察效果）
#
# 每一步都会停下来等你确认。Ctrl-C 随时可退，退出时会把 WAN 重新拉起来。

FW=/tmp/fw.bin
PAD_ONLY=0
WAIT_AFTER_PADT=25          # 给 BRAS 释放会话的时间（秒）

case "$1" in
	--pad-only) PAD_ONLY=1 ;;
	"") ;;
	*) FW="$1" ;;
esac
[ "$2" = "--pad-only" ] && PAD_ONLY=1

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    %s\033[0m\n' "$*"; }
ask()  {
	printf '\n\033[1;35m??? %s [y/N] \033[0m' "$*"
	read -r ans
	case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

wan_up()    { ifup wan >/dev/null 2>&1; }
wan_state() { ifstatus wan 2>/dev/null | jsonfilter -e '@["up"]' 2>/dev/null; }
wan_ip()    { ip -4 addr show pppoe-wan 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1; }

trap 'warn "中断，恢复 WAN..."; wan_up; exit 1' INT TERM

say "当前状态"
printf '    WAN 地址 : %s\n' "$(wan_ip)"
printf '    WAN MAC  : %s\n' "$(cat /sys/class/net/eth0/address)"
printf '    拨号时长 : %s 秒\n' "$(ifstatus wan 2>/dev/null | sed -n 's/.*"uptime": \([0-9]*\).*/\1/p' | head -1)"
printf '    固件文件 : %s\n' "$FW"
[ "$PAD_ONLY" = "1" ] && warn "本次为 --pad-only 模式：只结束会话，不刷机"

# ---------------------------------------------------------------- 第 1 步
say "第 1 步：终止 PPPoE 会话（发 PADT 让 BRAS 释放）"
if ! ask "执行 ifdown wan？（会短暂断网，几秒）"; then
	warn "已取消，未做任何改动"
	exit 0
fi

MARK=$(date +%s)
ifdown wan >/dev/null 2>&1
sleep 3

if logread 2>/dev/null | tail -40 | grep -q "Sent PADT"; then
	printf '    \033[1;32m✓ 已发出 PADT（BRAS 收到终止通知）\033[0m\n'
else
	warn "日志里没看到 Sent PADT，稍等再看..."
	sleep 3
	logread 2>/dev/null | tail -60 | grep -q "Sent PADT" \
		&& printf '    \033[1;32m✓ 已发出 PADT\033[0m\n' \
		|| warn "仍未看到 PADT（可能 pppd 已经退出较久），继续流程"
fi
printf '    当前 WAN: %s\n' "$(wan_ip)"

# ---------------------------------------------------------------- 第 2 步
say "第 2 步：等 BRAS 释放会话（${WAIT_AFTER_PADT} 秒）"
i=$WAIT_AFTER_PADT
while [ "$i" -gt 0 ]; do
	printf '\r    倒计时 %2d 秒...' "$i"
	sleep 1
	i=$((i-1))
done
printf '\r    等待完成。            \n'

# ---------------------------------------------------------------- 第 3 步
if [ "$PAD_ONLY" = "1" ]; then
	say "完成（pad-only 模式结束）"
	if ask "现在把 WAN 重新拨起来？"; then
		wan_up; sleep 6
		printf '    WAN: %s\n' "$(wan_ip)"
	fi
	exit 0
fi

say "第 3 步：校验固件"
[ -f "$FW" ] || { warn "找不到固件：$FW"; wan_up; exit 1; }
printf '    大小: %s 字节\n' "$(wc -c < "$FW")"
if sysupgrade -T "$FW" >/tmp/fwt.log 2>&1; then
	printf '    \033[1;32m✓ 镜像完整性校验通过\033[0m\n'
else
	warn "镜像校验失败："; cat /tmp/fwt.log; wan_up; exit 1
fi

# ---------------------------------------------------------------- 第 4 步
say "第 4 步：开始刷机"
cat <<EOF

    即将执行: sysupgrade -v "$FW"

    留意：
      * 保留配置（LAN .1 / PPPoE 账号 / MAC / wan6 都会保留）
      * 刷写完成后设备自动重启，SSH 会断开，这是正常的
      * 重启后拨号应该几秒内成功，不再有 LCP 黑洞

EOF
if ! ask "确认现在刷机？"; then
	warn "已取消，恢复 WAN 拨号"
	wan_up
	exit 0
fi

say "刷写中...（这段会断线，属正常）"
exec sysupgrade -v "$FW"
