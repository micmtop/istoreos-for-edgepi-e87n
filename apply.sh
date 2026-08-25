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

echo "==> [2.5/4] Copy custom packages"
mkdir -p "$SRC/package"
if [ -d "$ROOT/package/firmware/mt7987-2p5g-phy-firmware" ]; then
  cp -rf "$ROOT/package/firmware/mt7987-2p5g-phy-firmware" "$SRC/package/"
  echo "copied mt7987-2p5g-phy-firmware package"
else
  echo "WARN: mt7987-2p5g-phy-firmware package not found, skipping"
fi

echo "==> [3/4] Append E87N device definition to filogic.mk"
FILO="$MT/image/filogic.mk"
sed -i '/# ==== E87N start ====/,/# ==== E87N end ====/d' "$FILO"
cat >> "$FILO" <<'EOF'

# ==== E87N start ====
define Device/edgepi_e87n
  DEVICE_VENDOR := EdgePi
  DEVICE_MODEL := E87N
  DEVICE_DTS := mt7987a-edgepi-e87n
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-hwmon-pwmfan kmod-usb3 f2fsck mkf2fs mt7987-2p5g-phy-firmware
  KERNEL_LOADADDR := 0x40000000
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  BOARD_NAME := edgepi,e87n
  SUPPORTED_DEVICES := edgepi,e87n
endef
TARGET_DEVICES += edgepi_e87n
# ==== E87N end ====
EOF

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
for SYM in CONFIG_HW_RANDOM_MTK_V2=y CONFIG_PINCTRL_MT7987=y CONFIG_COMMON_CLK_MT7987=y CONFIG_FB=y CONFIG_FB_TFT=y CONFIG_FB_TFT_NV3007=y; do
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
            '\techo "CONFIG_FB=y" >> $(LINUX_DIR)/.config.set\n' +
            '\techo "CONFIG_FB_TFT=y" >> $(LINUX_DIR)/.config.set\n' +
            '\techo "CONFIG_FB_TFT_NV3007=y" >> $(LINUX_DIR)/.config.set\n')
s = s.replace(anchor, addition, 1)
with open(p, 'w') as f:
    f.write(s)
print("FB injection added to kernel-defaults.mk")
PYEOF

echo "==> done"
