#!/usr/bin/env python3
"""生成伪装图标（计算器）的旧格式 PNG。

为什么还需要 PNG：自适应图标（mipmap-anydpi-v26）只有 API 26+ 的桌面认。
本应用的 minSdk 低于 26，那些机器会退回 mipmap-*/ic_calculator.png，
缺了就会在桌面显示成一个透明方块。

几何不是"看着差不多"随手画的，而是从被仿的那支 vivo 计算器
（com.android.bbkcalculator 15.6.1.1，`res/drawable-hdpi/icon.png`，136×136）
量出来的，全部坐标以 136 画布为单位：

    圆角方块      x 11..123, y 9..125, 圆角半径 20
    四象限底色    TL #F1F1F1 / TR #FAFAFA / BL #FFFFFF / BR #EFEFEF
    +            中心 (41,40)，臂长 23，线宽 3，色 #646A6C
    ×            中心 (93,40)，包围盒 17×17，线宽 3，色 #646A6C
    −            中心 (41,94)，长 23，线宽 3，色 #646A6C
    =            两条横线 y=89 / y=99，x 82..104，线宽 3，色 #E9752A

用法（改色或改形状后重跑，产物直接落进 res/）：
    python3 tool/gen_disguise_icon.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

# 画布单位（与源图一致）
DESIGN = 136.0

BG_TOP_LEFT = (241, 241, 241, 255)
BG_TOP_RIGHT = (250, 250, 250, 255)
BG_BOTTOM_LEFT = (255, 255, 255, 255)
BG_BOTTOM_RIGHT = (239, 239, 239, 255)
INK = (100, 106, 108, 255)
ACCENT = (233, 117, 42, 255)

RECT = (11.0, 9.0, 123.0, 125.0)
RECT_RADIUS = 20.0
CENTER_X = 67.0
CENTER_Y = 67.0
# 线宽：源图直线条实测 3px（'−' 正好占 3 行）。PIL 的 line 宽度是整数像素，
# 4 倍超采样后缩回来会被抗锯齿摊薄，所以画的时候要略微加粗（3.4→实测 3px）。
STROKE = 3.4
# '×' 是斜线，同样的线宽在斜向上等效更宽，实测源图斜线约 2.6px。
STROKE_DIAG = 2.6

# mipmap 档位 -> 边长（px）。48/72/96/144/192 是 mdpi..xxxhdpi 的标准尺寸。
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def render(size: int) -> Image.Image:
    # 4 倍超采样再缩，边缘才不锯齿（PIL 不做抗锯齿描边）。
    scale = 4
    canvas = size * scale
    unit = canvas / DESIGN

    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    left, top, right, bottom = (v * unit for v in RECT)
    radius = RECT_RADIUS * unit

    # 圆角方块底：先用左上色铺满，再按象限盖另外三种色，最后用圆角遮罩裁剪。
    draw.rounded_rectangle(
        [(left, top), (right - 1, bottom - 1)], radius=radius, fill=BG_TOP_LEFT
    )
    cx = CENTER_X * unit
    cy = CENTER_Y * unit
    draw.rectangle([(cx, top), (right - 1, cy)], fill=BG_TOP_RIGHT)
    draw.rectangle([(left, cy), (cx, bottom - 1)], fill=BG_BOTTOM_LEFT)
    draw.rectangle([(cx, cy), (right - 1, bottom - 1)], fill=BG_BOTTOM_RIGHT)

    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(left, top), (right - 1, bottom - 1)], radius=radius, fill=255
    )
    clipped = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    clipped.paste(image, (0, 0), mask)
    image = clipped
    draw = ImageDraw.Draw(image)

    stroke = max(1, round(STROKE * unit))

    def bar(x1: float, y1: float, x2: float, y2: float, color,
            width: float | None = None) -> None:
        draw.line(
            [(x1 * unit, y1 * unit), (x2 * unit, y2 * unit)],
            fill=color,
            width=stroke if width is None else max(1, round(width * unit)),
        )

    # 端点各外扩 0.5：line 的宽度是**居中**铺开的，端点本身也要参与覆盖，
    # 不外扩的话缩回来每条线都比源图短 1px（实测 109px vs 129px 的那个差）。
    half = 0.5
    # + ：竖 29..51 / 横 30..52，中心 (41,40)
    bar(41, 29 - half, 41, 51 + half, INK)
    bar(30 - half, 40, 52 + half, 40, INK)
    # × ：包围盒 85..101 / 32..48
    bar(85 - half, 32 - half, 101 + half, 48 + half, INK, width=STROKE_DIAG)
    bar(101 + half, 32 - half, 85 - half, 48 + half, INK, width=STROKE_DIAG)
    # − ：y=94，x 30..52
    bar(30 - half, 94, 52 + half, 94, INK)
    # = ：y=89 / y=99，x 82..104
    bar(82 - half, 89, 104 + half, 89, ACCENT)
    bar(82 - half, 99, 104 + half, 99, ACCENT)

    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res = os.path.join(root, "android", "app", "src", "main", "res")
    for density, size in DENSITIES.items():
        directory = os.path.join(res, f"mipmap-{density}")
        os.makedirs(directory, exist_ok=True)
        target = os.path.join(directory, "ic_calculator.png")
        render(size).save(target)
        print(f"{target}  {size}x{size}")


if __name__ == "__main__":
    main()
