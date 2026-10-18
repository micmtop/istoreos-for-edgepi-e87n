#!/bin/sh
# 一键生成示例主题包 example-theme.tar.gz
#   ./build.sh              # 用内置彩条
#   ./build.sh my.png       # 用你自己的图（需要 Pillow）
set -e
cd "$(dirname "$0")"
if [ -n "$1" ]; then
    python3 make-frame.py frame.raw "$1"
else
    python3 make-frame.py frame.raw
fi
tar -czf example-theme.tar.gz theme.json frame.raw
echo "生成: $(pwd)/example-theme.tar.gz"
