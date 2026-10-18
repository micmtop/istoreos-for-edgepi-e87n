#!/bin/sh
# 本地交叉编译主题（需要 OpenWrt toolchain，或设 CC 指向 aarch64 编译器）
set -e
cd "$(dirname "$0")"
CC=${CC:-aarch64-openwrt-linux-musl-gcc}
rm -rf build
cmake -S . -B build \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_C_FLAGS="-O2"
cmake --build build -j"$(nproc 2>/dev/null || echo 4)"
cp -f theme.json build/
FILES="app theme.json"
if [ -f font.ttf ]; then cp -f font.ttf build/; FILES="$FILES font.ttf"; fi
tar -czf aurora.tar.gz -C build $FILES
echo "ok -> $(pwd)/aurora.tar.gz"
