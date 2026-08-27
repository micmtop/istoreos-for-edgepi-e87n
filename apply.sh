#!/bin/bash
# Apply E87N + MT7987 support onto an iStoreOS-24.10 (kernel 6.6) source tree.
# Usage: bash apply.sh   (run from repo root; expects ./istoreos = istoreos source)
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/istoreos"
MT="$SRC/target/linux/mediatek"

[ -d "$MT" ] || { echo "ERROR: $MT not found. Clone istoreos-24.10 into $SRC first."; exit 1; }

echo "==> [1/4] Copy MT7987 SoC dtsi + E87N dts"
cp -f "$ROOT/files/target/linux/mediatek/dts/mt7987.dtsi"           "$MT/dts/"
cp -f "$ROOT/files/target/linux/mediatek/dts/mt7987a.dtsi"          "$MT/dts/"
cp -f "$ROOT/files/target/linux/mediatek/dts/mt7987b.dtsi"          "$MT/dts/"
cp -f "$ROOT/files/target/linux/mediatek/dts/mt7987a-edgepi-e87n.dts" "$MT/dts/"

echo "==> [2/4] Copy MT7987 kernel patches into patches-6.6"
mkdir -p "$MT/patches-6.6"
cp -f "$ROOT"/files/target/linux/mediatek/patches-6.6/*.patch "$MT/patches-6.6/"

echo "==> [2.4/4] Fix mtk_eth_soc pextp PHY get (devm_of_phy_get -> optional_get)"
# E87N net PHY (Airoha EN8811H on mdio-bus) is not described as a `phys`
# phandle on the mac node, so mtk_add_mac()'s devm_of_phy_get() returns
# -ENODEV and aborts the WHOLE mtk_eth probe -> eth0/eth1 never register.
# The official (HiGoROS 6.12) driver uses devm_of_phy_optional_get(), which
# returns NULL (not an error) when the mac has no `phys` property.  Patch the
# stock istoreos 6.6 kernel patch the same way.  (pending-6.6 is applied by
# OpenWrt's kernel build, so patching the .patch here is what survives the CI
# re-clone.)
for P737 in "$SRC"/target/linux/generic/pending-6.6/737-net-ethernet-mtk_eth_soc-add-paths-and-SerDes-modes-.patch; do
  if [ -f "$P737" ]; then
    python3 - "$P737" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p) as f:
    s = f.read()
old = "mac->pextp = devm_of_phy_get(eth->dev, mac->of_node, NULL);"
new = "mac->pextp = devm_of_phy_optional_get(eth->dev, mac->of_node, NULL);"
if new in s:
    print("737 pextp already optional_get")
    sys.exit(0)
if old not in s:
    print("WARN: 737 pextp devm_of_phy_get anchor not found", file=sys.stderr)
    sys.exit(0)
s = s.replace(old, new, 1)
with open(p, 'w') as f:
    f.write(s)
print("737 pextp switched to devm_of_phy_optional_get")
PYEOF
  else
    echo "WARN: 737 patch not found at $P737"
  fi
done

echo "==> [2.5/4] Copy custom packages"
mkdir -p "$SRC/package"
if [ -d "$ROOT/package/firmware/mt7987-2p5g-phy-firmware" ]; then
  cp -rf "$ROOT/package/firmware/mt7987-2p5g-phy-firmware" "$SRC/package/"
  echo "copied mt7987-2p5g-phy-firmware package"
else
  echo "WARN: mt7987-2p5g-phy-firmware package not found, skipping"
fi

echo "==> [2.6/4] Override istoreos-boot.sh (E87N overlay fix)"
# iStoreOS stock code uses partition 3 as overlay. On E87N, partition 3 is the
# FIP / U-Boot partition, so the system overwrote U-Boot on every boot.
# Use fstools rootfs_data instead.
if [ -f "$ROOT/files/lib/functions/istoreos-boot.sh" ]; then
  cp -f "$ROOT/files/lib/functions/istoreos-boot.sh" "$SRC/package/base-files/files/lib/functions/istoreos-boot.sh"
  echo "copied istoreos-boot.sh overlay fix"
else
  echo "WARN: istoreos-boot.sh fix not found, skipping"
fi

echo "==> [2.7/4] Patch mount_root for E87N (delegate overlay to fstools)"
# CRITICAL: preinit PATH puts /usr/sbin before /sbin, so iStoreOS's SHELL
# mount_root (/usr/sbin/mount_root) shadows fstools' C mount_root
# (/sbin/mount_root). Only the C implementation creates /dev/rootfs_data on
# the rootfs partition's free space. Without this patch, the fixed
# istoreos-boot.sh can never find /dev/rootfs_data and the system boots with
# NO overlay at all (read-only rootfs). On E87N we delegate the whole overlay
# mount to the fstools C mount_root (standard OpenWrt behaviour).
MR="$SRC/package/base-files/files/usr/sbin/mount_root"
python3 - "$MR" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p) as f:
    s = f.read()
if 'E87N: overlay via fstools rootfs_data' in s:
    print("mount_root E87N delegation already present")
    sys.exit(0)
anchor = "\t[ ! -e /rom/note ] && return 0\n\n\tinlog get_overlay_partition || return 1\n"
if anchor not in s:
    print("ERROR: mount_root do_mount_overlayfs anchor not found", file=sys.stderr)
    sys.exit(1)
addition = (
    "\t[ ! -e /rom/note ] && return 0\n\n"
    "\t# E87N FIX: this device has no dedicated overlay partition (p3 = FIP/U-Boot).\n"
    "\t# iStoreOS shell overlay logic needs /dev/rootfs_data, which is created only\n"
    "\t# by fstools' C mount_root (/sbin/mount_root). Delegate so fstools creates\n"
    "\t# and mounts rootfs_data on the rootfs partition's free space (standard\n"
    "\t# OpenWrt behaviour). Skip delegation in recovery mode.\n"
    "\tif [ ! -f /.recovery_mode ] && [ -e /sys/block/mmcblk0/mmcblk0p4 ] && \\\n"
    "\t   [ -e /sys/block/mmcblk0/mmcblk0p5 ] && [ -x /sbin/mount_root ]; then\n"
    "\t\tlog \"E87N: overlay via fstools rootfs_data, delegating to /sbin/mount_root\"\n"
    "\t\texec /sbin/mount_root\n"
    "\tfi\n\n"
    "\tinlog get_overlay_partition || return 1\n")
s = s.replace(anchor, addition, 1)
with open(p, 'w') as f:
    f.write(s)
print("mount_root E87N delegation added")
PYEOF

echo "==> [2.8/4] Add E87N emmc upgrade branch to platform.sh"
# Stock filogic platform.sh routes edgepi,e87n to the default nand_do_upgrade
# branch, which breaks eMMC partition detection (kernel/rootfs go to the wrong
# partitions). Add an explicit emmc_do_upgrade branch.
#
# NOTE: we do NOT derive CI_ROOTDEV from cmdline.  The E87N DTS sets
# root=PARTLABEL=rootfs, so `cmdline_get_var root` returns "PARTLABEL=rootfs"
# and the ${rootdev##*/} / ${rootdev%p[0-9]*} parsing used by the unielec
# branch yields an empty/non-mmc string -> E87N would be misrouted to
# nand_do_upgrade.  E87N has exactly one eMMC (mmcblk0); hardcode it.
PLAT="$MT/filogic/base-files/lib/upgrade/platform.sh"
mkdir -p "$(dirname "$PLAT")"
python3 - "$PLAT" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p) as f:
    s = f.read()

# Patch 1: platform_do_upgrade -> emmc_do_upgrade for E87N
if 'edgepi,e87n)' not in s:
    anchor = "\tunielec,u7981-01*)\n"
    if anchor not in s:
        print("ERROR: unielec anchor not found in platform.sh", file=sys.stderr)
        sys.exit(1)
    addition = ("\tedgepi,e87n)\n"
                "\t\tCI_ROOTDEV=\"mmcblk0\"\n"
                "\t\tCI_KERNPART=\"kernel\"\n"
                "\t\tCI_ROOTPART=\"rootfs\"\n"
                "\t\temmc_do_upgrade \"$1\"\n"
                "\t\t;;\n")
    s = s.replace(anchor, addition + anchor, 1)

# Patch 2: platform_copy_config -> save config to eMMC for E87N.
# NOTE: '\tubnt,unifi-6-plus)' appears in BOTH platform_do_upgrade and
# platform_copy_config.  A naive s.replace() with count=1 hits the FIRST
# occurrence (platform_do_upgrade), silently leaving E87N out of the
# emmc_copy_config group -> sysupgrade would lose the config on upgrade.
# Restrict the insertion to the body of platform_copy_config() only.
# The inserted line must end in '|\'+newline (case-pattern continuation),
# matching the file's own style; a bare '|' before a newline is not
# accepted by busybox ash's case parser.
marker = "platform_copy_config() {"
if marker not in s:
    print("ERROR: platform_copy_config() marker not found", file=sys.stderr)
    sys.exit(1)
pre, _, post = s.partition(marker)
if 'edgepi,e87n' not in post.split('esac', 1)[0]:
    cc_anchor = "\tubnt,unifi-6-plus)\n"
    if cc_anchor not in post:
        print("ERROR: copy_config ubnt anchor not found inside platform_copy_config", file=sys.stderr)
        sys.exit(1)
    post2 = post.replace(cc_anchor, "\tedgepi,e87n|\\\n" + cc_anchor, 1)
    s = pre + marker + post2
    print("platform_copy_config E87N emmc group added")
else:
    print("platform_copy_config E87N group already present")

with open(p, 'w') as f:
    f.write(s)
print("platform.sh E87N emmc branch + copy_config added")
PYEOF

echo "==> [3/4] Append E87N device definition to filogic.mk"
# Python implementation for true idempotency: a naive "sed delete + cat append"
# accumulates a blank line after every run (the deleted block's leading blank
# line survives the sed range).  Rebuild the block deterministically instead.
FILO="$MT/image/filogic.mk"
python3 - "$FILO" <<'PYEOF'
import sys, re
p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    s = f.read()
block = (
    "\n# ==== E87N start ====\n"
    "define Device/edgepi_e87n\n"
    "  DEVICE_VENDOR := EdgePi\n"
    "  DEVICE_MODEL := E87N\n"
    "  DEVICE_DTS := mt7987a-edgepi-e87n\n"
    "  DEVICE_DTS_DIR := ../dts\n"
    "  DEVICE_PACKAGES := kmod-hwmon-pwmfan kmod-usb3 e2fsprogs f2fsck mkf2fs mt7987-2p5g-phy-firmware kmod-phy-airoha-en8811h\n"
    "  KERNEL_LOADADDR := 0x40000000\n"
    "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata\n"
    "  BOARD_NAME := edgepi,e87n\n"
    "  SUPPORTED_DEVICES := edgepi,e87n\n"
    "endef\n"
    "TARGET_DEVICES += edgepi_e87n\n"
    "# ==== E87N end ====\n"
)
# Remove ALL existing E87N blocks.  NOTE: plain `.*?` does NOT match newlines
# in Python regex, so a multi-line block could never be matched -> blocks
# silently ACCUMULATED on every run instead of being replaced.  Use [\s\S]*?
# to span lines.  Also collapse runs of blank lines so history cannot accumulate.
s2 = re.sub(r"# ==== E87N start ====[\s\S]*?# ==== E87N end ====\n", "", s)
s2 = re.sub(r"\n[ \t]*(?:\n[ \t]*)+", "\n\n", s2)
s3 = s2.rstrip("\n") + "\n" + block.lstrip("\n")
with open(p, 'w', encoding='utf-8', newline='\n') as f:
    f.write(s3)
print("filogic.mk E87N block (re)appended idempotently")
PYEOF

echo "==> [4/4] Add E87N network layout to board.d/02_network"
NET="$MT/filogic/base-files/etc/board.d/02_network"
mkdir -p "$(dirname "$NET")"
python3 - "$NET" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p) as f:
    s = f.read()
if 'edgepi,e87n)' in s:
    print("E87N block already present")
    sys.exit(0)
block = '\tedgepi,e87n)\n\t\tucidef_set_interfaces_lan_wan "eth0" eth1\n\t\t;;\n'
marker = '\tcase $board in\n'
if marker not in s:
    print("ERROR: cannot find case marker in %s" % p, file=sys.stderr)
    sys.exit(1)
s = s.replace(marker, marker + block, 1)
with open(p, 'w') as f:
    f.write(s)
print("E87N network block inserted")
PYEOF

echo "==> [5/5] Set new MT7987 kernel symbols so kconfig does not prompt"
FCFG="$MT/filogic/config-6.6"
mkdir -p "$(dirname "$FCFG")"
# These symbols are added by our MT7987 patches and are NOT in the stock
# filogic config fragment, so OpenWrt's kernel syncconfig would ask for them
# interactively (CI has no tty -> "syncconfig ... Error 1"). Set them here.
# FB_TFT in 6.6 depends on FB && SPI && FB_DEVICE && GPIOLIB (and needs
# STAGING for the staging/fbtft tree to be visible). Injecting FB_TFT=y
# alone was reset by syncconfig because FB_DEVICE/STAGING were not forced.
for SYM in CONFIG_HW_RANDOM_MTK_V2=y CONFIG_PINCTRL_MT7987=y CONFIG_COMMON_CLK_MT7987=y CONFIG_PHY_REALTEK=y CONFIG_STAGING=y CONFIG_FB=y CONFIG_FB_DEVICE=y CONFIG_FB_TFT=y CONFIG_FB_TFT_NV3007=y; do
  NAME="${SYM%%=*}"
  if ! grep -q "^${NAME}=" "$FCFG" 2>/dev/null; then
    echo "$SYM" >> "$FCFG"
    echo "appended $SYM to $FCFG"
  else
    echo "$FCFG already defines $NAME"
  fi
done

echo "==> [6/6] Force FB symbols into the generated kernel .config"
# The kernel config fragment above is NOT reliable for enabling FB_TFT_NV3007
# (empirically the built kernel came out with fbdev disabled in run 32791064989
# even though the merge analysis said FB=y). Guarantee the symbols by injecting
# them into $(LINUX_DIR)/.config.set right before OpenWrt copies it to .config.
# kconfig's conf uses the LAST occurrence of a symbol in .config, so appending
# CONFIG_FB_TFT_NV3007=y here wins even if a "# ... is not set" line precedes it.
KDM="$SRC/include/kernel-defaults.mk"
python3 - "$KDM" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p) as f:
    s = f.read()
if 'CONFIG_FB_TFT_NV3007=y" >> $(LINUX_DIR)/.config.set' in s:
    print("FB injection already present")
    sys.exit(0)
anchor = "\t$(call Kernel/SetNoInitramfs)\n"
if anchor not in s:
    print("ERROR: cannot find SetNoInitramfs anchor in kernel-defaults.mk",
          file=sys.stderr)
    sys.exit(1)
addition = (anchor +
            '\techo "CONFIG_STAGING=y" >> $(LINUX_DIR)/.config.set\n' +
            '\techo "CONFIG_FB=y" >> $(LINUX_DIR)/.config.set\n' +
            '\techo "CONFIG_FB_DEVICE=y" >> $(LINUX_DIR)/.config.set\n' +
            '\techo "CONFIG_FB_TFT=y" >> $(LINUX_DIR)/.config.set\n' +
            '\techo "CONFIG_FB_TFT_NV3007=y" >> $(LINUX_DIR)/.config.set\n')
s = s.replace(anchor, addition, 1)
with open(p, 'w') as f:
    f.write(s)
print("FB injection added to kernel-defaults.mk")
PYEOF

echo "==> done"
