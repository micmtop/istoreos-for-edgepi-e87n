#!/bin/sh
# install-kmods.sh — 把与当前内核匹配的 kmod 包装上，修好 apk 的依赖登记
#
# 背景：镜像构建时，用 e87n.config 加的包（kmod-*、dockerd、ksmbd-server...）
# 文件进了镜像，却没有写进 apk 的已安装数据库。于是 apk 认为"没装"，
# 任何依赖 kmod-* 的安装都会报 "no such package"。
#
# 关键事实：模块的 vermagic 是 "6.12.112 SMP mod_unload aarch64"，不含配置哈希，
# 所以同一次构建产出的 .apk（内核包 + 全部 kmod）可以整批装进任何 6.12.112 的机器，
# 装完 apk 的依赖图就自洽了。
#
# 用法（在路由器上）：
#   sh /root/install-kmods.sh                 # 自动从 Release 下载最新匹配的包
#   sh /root/install-kmods.sh /tmp/km         # 用本地已解压的目录
#
# 不改动 p4 里的内核本体，只替换 /lib/modules 下的模块并补数据库登记。

set -u
TAG=${TAG:-v25.12.6-e87n-r8}
REPO=micmtop/istoreos-for-edgepi-e87n
MIRRORS="https://ghfast.top/https://github.com https://ghproxy.net/https://github.com https://github.com"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    %s\033[0m\n' "$*"; }

SRC=${1:-}
say "当前状态"
printf '    内核      : %s\n' "$(uname -r)"
printf '    数据库内核: %s\n' "$(apk list --installed 2>/dev/null | sed -n 's/^\(kernel-[^ ]*\).*/\1/p' | head -1)"
printf '    已登记 kmod: %s 个\n' "$(apk list --installed 2>/dev/null | grep -c '^-*kmod-')"

if [ -z "$SRC" ]; then
	HASH=$(apk list --installed 2>/dev/null | sed -n 's/^kernel-[0-9.]*~\([0-9a-f]*\)-r.*/\1/p' | head -1)
	[ -n "$HASH" ] || { warn "读不到内核 ABI 哈希，退出"; exit 1; }
	FILE="e87n-kmods-${HASH}.tar.gz"
	say "下载 $FILE"
	ok=0
	for M in $MIRRORS; do
		printf '    尝试 %s\n' "$(echo "$M" | cut -d/ -f3)"
		if curl -sL -m 300 --retry 2 -o "/tmp/$FILE" "$M/$REPO/releases/download/$TAG/$FILE" 2>/dev/null \
		   && [ -s "/tmp/$FILE" ]; then ok=1; break; fi
	done
	[ "$ok" = "1" ] || { warn "下载失败。可以手动下载后运行: sh $0 <已解压目录>"; exit 1; }
	SRC=/tmp/km-new
	rm -rf "$SRC"; mkdir -p "$SRC"
	tar -xzf "/tmp/$FILE" -C "$SRC" || { warn "解压失败"; exit 1; }
fi

N=$(ls "$SRC"/*.apk 2>/dev/null | wc -l)
say "包目录 $SRC ：$N 个 apk"
[ "$N" -gt 0 ] || { warn "目录里没有 .apk"; exit 1; }

say "备份现有模块到 /overlay/backup-modules"
mkdir -p /overlay/backup-modules
cp -a "/lib/modules/$(uname -r)" /overlay/backup-modules/ 2>/dev/null
printf '    已备份 %s\n' "$(du -sh /overlay/backup-modules 2>/dev/null | cut -f1)"

say "整批安装（内核包 + 全部 kmod，依赖自洽）"
apk add --allow-untrusted --force-overwrite --force-broken-world "$SRC"/*.apk 2>&1 | tail -6

say "清理无法满足的 world 条目"
for W in $(grep -E '^kmod-' /etc/apk/world 2>/dev/null); do
	apk list --installed 2>/dev/null | grep -q "^-*${W}-[0-9]" || {
		sed -i "/^${W}\$/d" /etc/apk/world
		printf '    移除死依赖: %s\n' "$W"
	}
done

say "结果"
printf '    数据库内核: %s\n' "$(apk list --installed 2>/dev/null | sed -n 's/^\(kernel-[^ ]*\).*/\1/p' | head -1)"
printf '    已登记 kmod: %s 个\n' "$(apk list --installed 2>/dev/null | grep -c '^-*kmod-')"
printf '    关键模块加载: '
for m in veth ksmbd btrfs zram; do
	modprobe "$m" 2>/dev/null && printf '%s✓ ' "$m" || printf '%s✗ ' "$m"
done
printf '\n'
printf '    依赖解析测试: '
if apk add --simulate dockerd >/dev/null 2>&1; then echo "dockerd 可安装 ✓"; else echo "仍有缺依赖 ✗"; fi
say "完成。如果服务有问题，模块已备份在 /overlay/backup-modules/"
