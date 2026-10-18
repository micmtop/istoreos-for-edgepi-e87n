#!/usr/bin/env python3
"""生成 E87N 主题用的 frame.raw（428x142 RGB565 little-endian，121552 字节）

用法:
    python3 make-frame.py frame.raw                 # 生成内置彩条测试图
    python3 make-frame.py frame.raw my.png          # 用图片（需 Pillow）

打包:
    tar -czf mytheme.tar.gz theme.json frame.raw
"""
import struct
import sys

W, H = 428, 142


def rgb565(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def builtin_pattern():
    px = [rgb565(0, 0, 0)] * (W * H)
    bars = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
            (255, 0, 255), (255, 0, 0), (0, 0, 255)]
    bw = W // len(bars)
    for y in range(H):
        for x in range(W):
            c = bars[min(x // bw, len(bars) - 1)] if 8 <= y < H - 8 else (20, 20, 20)
            px[y * W + x] = rgb565(*c)
    return px


def from_image(path):
    try:
        from PIL import Image
    except ImportError:
        sys.exit("需要 Pillow 才能直接用图片: pip install pillow")

    im = Image.open(path).convert("RGB")
    # 等比缩放并居中（与 LuCI 图片导入一致）
    scale = max(W / im.width, H / im.height)
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))),
                   Image.LANCZOS)
    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    canvas.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
    return [rgb565(*canvas.getpixel((x, y))) for y in range(H) for x in range(W)]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = sys.argv[1]
    px = from_image(sys.argv[2]) if len(sys.argv) > 2 else builtin_pattern()
    data = struct.pack("<%dH" % (W * H), *px)
    assert len(data) == 121552, len(data)
    with open(out, "wb") as f:
        f.write(data)
    print("wrote %s (%d bytes, %dx%d RGB565)" % (out, len(data), W, H))


if __name__ == "__main__":
    main()
