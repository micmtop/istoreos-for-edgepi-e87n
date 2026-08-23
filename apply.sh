#!/bin/bash
# Apply E87N + MT7987 support onto an iStoreOS-24.10 (kernel 6.6) source tree.
# Usage: bash apply.sh   (run from repo root; expects ./istoreos to be the istoreos source)
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/istoreos"
MT="$SRC/target/linux/mediatek"

[ -d "$MT" ] || { echo "ERROR: $MT not found. Clone istoreos-24.10 into $SRC first."; exit 1; }

echo "==> [1/4] Copy MT7987 SoC dtsi + E87N dts"
cp "$ROOT/files/target/linux/mediatek/dts/mt7987.dtsi"    "$MT/dts/"
cp "$ROOT/files/target/linux/mediatek/dts/mt7987a.dtsi"   "$MT/dts/"
cp "$ROOT/files/target/linux/mediatek/dts/mt7987b.dtsi"   "$MT/dts/"
cp "$ROOT/files/target/linux/mediatek/dts/mt7987a-edgepi-e87n.dts" "$MT/dts/"

echo "==> [2/4] Copy MT7987 kernel patches into patches-6.6"
mkdir -p "$MT/patches-6.6"
cp "$ROOT"/files/target/linux/mediatek/patches-6.6/*.patch "$MT/patches-6.6/"

echo "==> [3/4] Append E87N device definition to filogic.mk"
# Remove any previous block to keep idempotent
sed -i '/# ==== E87N start ====/,/# ==== E87N end ====/d' "$MT/image/filogic.mk"
cat >> "$MT/image/filogic.mk" <<'EOF'

# ==== E87N start ====
define Device/edgepi_e87n
  DEVICE_VENDOR := EdgePi
  DEVICE_MODEL := E87N
  DEVICE_DTS := mt7987a-edgepi-e87n
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-hwmon-pwmfan kmod-usb3 f2fsck mkf2fs
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
# Ensure a case entry exists (idempotent via sed guard)
if ! grep -q 'edgepi,e87n)' "$NET"; then
  sed -i "s#^\tmediatek_setup_interfaces()#\tmediatek_setup_interfaces()#" "$NET"
  sed -i "/^mediatek_setup_interfaces()/{n; a\\\n\tedgepi,e87n)\\\n\t\tucidef_set_interfaces_lan_wan \"eth0\" eth1\\\n\t\t;;" "$NET}"
fi

echo "==> done"
