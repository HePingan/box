#!/usr/bin/env python3
"""生成伪装计算器图标（vivo 系统计算器那张脸），按 48dp 标准密度出图。

变体要选对（第一步，且仍然成立）
--------------------------------
被仿的 vivo 系统计算器（com.android.bbkcalculator 15.6.1.1）在 APK 里带**两张**图标：

    drawable/icon       hdpi 136×136                浅底深符号   ← 第一版量的就是这张
    drawable/app_icon   hdpi/xhdpi/xxhdpi/xxxhdpi   深底浅符号 + 橙色等号键

真机桌面显示的是 **app_icon**：四象限均值 (70,72,76)/(67,69,73)/(70,72,76)/(114,96,69)，
与用户给的真机截图 (77,79,86)/(73,75,81)/(76,80,87)/(123,103,72) 只差压缩噪声；
而 `icon` 那张的通道差是 256 —— 完全不是同一张脸。手绘得再准，画的也是「不像的那张」。

为什么不再「直接拷字节」（1.21.29+386 的做法）
---------------------------------------------
386 是字节级拷贝，变体对了，但**源 APK 里最大的一档只有 128×128**（hdpi 32 / xhdpi 64 /
xxhdpi 96 / xxxhdpi 128，即 vivo 是按 32dp 出的图）。Android 图标槽位是 48dp：xxxhdpi 要
192px，一加/OriginOS 的桌面槽位往往还更大。桌面拿到 128px 只能自己放大 → 边缘和笔画全被
插值糊掉，这就是「图标还是糊」的直接原因。真机上系统计算器看着清楚，是因为它是系统应用，
桌面用的是自带图标包，不是 APK 里这份 128px 资源。

所以现在改成「**从真机那张图拟合出矢量，再按各密度重新栅格化**」：

- 源图仍是唯一依据：色调、圆心、半径、笔画长宽都从 `drawable/app_icon` 的 128px 那张
  量出来，再用坐标下降拟合到逐像素误差最小（见 PALETTE / GEOMETRY 注释）；
- 保真度**可验证**：`--apk` 时会把自己渲的 96/128px 与源 APK 里那两张逐像素比对，
  平均误差 > 4/255 或「误差 ≤24 的像素占比」< 90% 直接报失败 —— 不允许悄悄换成另一张脸；
- 形状语言跟着源图走：笔画是圆头（源图加号/等号末端是圆角，方头会显得「不是同一个设计」），
  外框是圆角矩形而非超椭圆 —— 按行扫 alpha 轮廓，圆角半径 31.6/128 与源图逐行一致（±1px AA）。

密度的取舍：产出 mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192（48dp 语义）。
源 APK 里没有 mdpi，我们补上，省得 mdpi 设备去放大 hdpi。**不要**为了更清晰把 xxxhdpi
塞成 256px：那会把 intrinsic 尺寸从 48dp 变成 64dp，个别不强制 bounds 的桌面会画得比真
计算器大一截。桌面槽位比 192 更大时，靠矢量重渲染的 192 已经比原来 128 放大清楚一档。

注意：**不要给这个图标加自适应图标（anydpi-v26）**。被仿的应用没有，桌面走位图路径；
给了 anydpi-v26 桌面会把 108dp 裁到可见 72dp 再套蒙版 = 内容放大约 1.5 倍并切边，
那就是用户嘴里的「变形」。契约测试里钉着这条。

用法
----
    python3 tool/gen_disguise_icon.py --apk /path/to/计算器.apk          # 校验源 + 渲染写盘
    python3 tool/gen_disguise_icon.py --apk /path/to/计算器.apk --check  # 只校验/只报告，不写盘

依赖 Pillow（anaconda 的 python3 自带）。跑完会把 5 档的哈希打出来，改图标后记得同步
test/disguise/disguise_android_contract_test.dart 里钉的哈希与边长。
"""

from __future__ import annotations

import argparse
import hashlib
import io
import math
import os
import re
import subprocess
import sys
import zipfile

# 源 APK（vivo 系统计算器 15.6.1.1）里 drawable/app_icon 各密度的 (sha256 前 16 位, 像素边长)。
# 换源版本时这里会变；脚本会打印新哈希，确认变体没被换掉再更新。
EXPECTED_SRC = {
    "hdpi": ("b1d3bac8753f5fca", 32),
    "xhdpi": ("60d6c81847e8b846", 64),
    "xxhdpi": ("54c9756b1b92513f", 96),
    "xxxhdpi": ("3dfe400043bf84ed", 128),
}

# 要产出的密度档 —— 48dp 图标语义（mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192）。
TARGET_BUCKETS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

PALETTE = {
    "base": (57, 59, 64),            # 外框底 #393B40
    "key": (82, 84, 88),             # 三个深灰键 #525458
    "key_accent": (247, 190, 99),    # 等号键 #F7BE63
    "glyph": (230, 230, 230),        # + - ×  #E6E6E6
    "glyph_accent": (192, 129, 33),  # =      #C08121
}

# 以 128px 源图为坐标系（0..128）的实测 + 拟合结果。
# 实测：外框铺满 0..127 的圆角矩形；四键圆心 (37,37)/(90,37)/(37,90)/(90,90)；
#       加号笔画约 21px 长、5px 粗、圆头；等号两条各 5px 粗、中心距 10.4px。
# 拟合：8 倍超采样重绘后降采样到 128 与源图逐像素比对，坐标下降微调（lanczos 抗锯齿口径）。
GEOMETRY = {
    "corner_radius": 31.6,
    "key_radius": 20.5,
    "accent_radius": 20.6,
    "stroke_len": 22.5,
    "stroke_width": 4.95,
    "eq_len": 22.25,
    "eq_width": 5.2,
    "eq_gap": 10.375,
    "row_top": 37.35,
    "row_bottom": 90.434,
    "key_centers": ((37.0, 37.0), (90.0, 37.0), (37.0, 90.0), (90.0, 90.0)),
    "accent_center": (90.0, 90.0),
}

# 保真门槛：把自己渲的图与源 APK 的位图逐像素比。
FIDELITY_MAX_MEAN = 4.0     # 平均绝对误差（0~255）
FIDELITY_MIN_IN_24 = 0.90   # 三通道差都 ≤24 的像素占比

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES_DIR = os.path.join(REPO_ROOT, "android", "app", "src", "main", "res")

AAPT2_CANDIDATES = [
    "/opt/android-sdk/build-tools/36.0.0/aapt2",
    "/opt/android-sdk/build-tools/34.0.0/aapt2",
    "/root/Android/Sdk/build-tools/36.0.0/aapt2",
]


def resolve_app_icon(apk: str) -> dict[str, str]:
    """用 aapt2 解析 drawable/app_icon 在各密度下对应的实际文件路径。"""
    aapt2 = next((p for p in AAPT2_CANDIDATES if os.path.exists(p)), None)
    if aapt2 is None:
        raise SystemExit("找不到 aapt2：请确认 ANDROID_HOME/build-tools 可用")
    dump = subprocess.run(
        [aapt2, "dump", "resources", apk], capture_output=True, text=True, check=True
    ).stdout
    out: dict[str, str] = {}
    cur: tuple[str, str] | None = None
    for line in dump.splitlines():
        m = re.match(r"\s*resource 0x[0-9a-f]+ (\S+)/(\S+)", line)
        if m:
            cur = (m.group(1), m.group(2))
            continue
        m = re.match(r"\s*\(([^)]+)\)\s*\(file\)\s+(\S+)\s+type=PNG", line)
        if m and cur == ("drawable", "app_icon"):
            out[m.group(1)] = m.group(2)
    if not out:
        raise SystemExit("源 APK 里没有 drawable/app_icon —— 这个 APK 可能不是同一支应用")
    return out


def _bar(dr, cx, cy, length, thick, angle_deg, color, k):
    """一条圆头笔画。k = 设计坐标(0..128) → 画布像素的倍率。"""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), math.sin(a)
    half = max(length / 2 - thick / 2, 0)
    p1 = ((cx - ux * half) * k, (cy - uy * half) * k)
    p2 = ((cx + ux * half) * k, (cy + uy * half) * k)
    w = thick * k
    dr.line([p1, p2], fill=color, width=int(round(w)))
    r = w / 2
    for px, py in (p1, p2):
        dr.ellipse([px - r, py - r, px + r, py + r], fill=color)


def render(size: int, supersample: int = 8):
    """按 GEOMETRY 渲一张 size×size 的 RGBA 图标（超采样后 LANCZOS 降采样换抗锯齿）。"""
    from PIL import Image, ImageDraw

    W = size * supersample
    k = W / 128.0
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    g = GEOMETRY

    dr.rounded_rectangle(
        [0, 0, W - 1, W - 1], radius=g["corner_radius"] * k, fill=PALETTE["base"] + (255,)
    )
    accent = g["accent_center"]
    for (cx, cy) in g["key_centers"]:
        is_accent = (cx, cy) == accent
        r = (g["accent_radius"] if is_accent else g["key_radius"]) * k
        dr.ellipse(
            [cx * k - r, cy * k - r, cx * k + r, cy * k + r],
            fill=(PALETTE["key_accent"] if is_accent else PALETTE["key"]) + (255,),
        )

    white = PALETTE["glyph"] + (255,)
    dark = PALETTE["glyph_accent"] + (255,)
    top, bottom = g["row_top"], g["row_bottom"]
    _bar(dr, 37, top, g["stroke_len"], g["stroke_width"], 0, white, k)      # + 横
    _bar(dr, 37, top, g["stroke_len"], g["stroke_width"], 90, white, k)     # + 竖
    _bar(dr, 90, top, g["stroke_len"], g["stroke_width"], 0, white, k)      # −
    _bar(dr, 37, bottom, g["stroke_len"], g["stroke_width"], 45, white, k)  # × 一撇
    _bar(dr, 37, bottom, g["stroke_len"], g["stroke_width"], -45, white, k)  # × 一捺
    _bar(dr, 90, bottom - g["eq_gap"] / 2, g["eq_len"], g["eq_width"], 0, dark, k)  # = 上
    _bar(dr, 90, bottom + g["eq_gap"] / 2, g["eq_len"], g["eq_width"], 0, dark, k)  # = 下
    return im.resize((size, size), Image.LANCZOS)


def fidelity(source_pngs: dict[int, bytes]) -> bool:
    """把自己渲的图与源 APK 里的 96/128px 原图逐像素比，确认画的还是同一张脸。"""
    import numpy as np
    from PIL import Image

    ok = True
    for px, data in sorted(source_pngs.items()):
        ref = np.array(Image.open(io.BytesIO(data)).convert("RGBA")).astype(int)
        mine = np.array(render(px)).astype(int)
        d = np.abs(ref - mine)
        mean = d.mean()
        within = (d.max(axis=-1) <= 24).mean()
        passed = mean <= FIDELITY_MAX_MEAN and within >= FIDELITY_MIN_IN_24
        ok = ok and passed
        print(
            f"  保真 {px:4d}px: 平均误差 {mean:.2f}/255, p99={np.percentile(d, 99):.0f}, "
            f"误差≤24 占比 {within:.1%} → {'通过' if passed else '不达标'}"
        )
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True, help="vivo 系统计算器 APK 路径")
    ap.add_argument("--check", action="store_true", help="只校验与报告，不写盘")
    args = ap.parse_args()

    from PIL import Image  # 延迟导入，--help 也就不用装好 Pillow

    entries = resolve_app_icon(args.apk)
    print(f"源 APK : {args.apk}")
    print(f"app_icon 密度: {sorted(entries)}\n")

    src_ok = True
    source_pngs: dict[int, bytes] = {}
    with zipfile.ZipFile(args.apk) as z:
        for density, (want_hash, want_px) in EXPECTED_SRC.items():
            src = entries.get(density)
            if src is None:
                print(f"  {density:8s} [失败] 源 APK 缺这个密度")
                src_ok = False
                continue
            data = z.read(src)
            got_hash = hashlib.sha256(data).hexdigest()[:16]
            got_px = Image.open(io.BytesIO(data)).size[0]
            same = got_hash == want_hash and got_px == want_px
            print(
                f"  {density:8s} {src:12s} {got_px:4d}px sha={got_hash} "
                f"期望 {want_hash} {want_px}px → {'一致' if same else '不一致'}"
            )
            src_ok = src_ok and same
            if got_px in (96, 128):
                source_pngs[got_px] = data

    print("\n保真校验（矢量重渲染 vs 源位图）：")
    fid_ok = fidelity(source_pngs)

    print("\n产出（48dp 语义）：")
    hashes: dict[str, tuple[str, int]] = {}
    for density, px in TARGET_BUCKETS.items():
        img = render(px)
        buf = io.BytesIO()
        img.save(buf, "PNG", optimize=True)
        data = buf.getvalue()
        digest = hashlib.sha256(data).hexdigest()
        hashes[density] = (digest[:16], px)
        dst = os.path.join(RES_DIR, f"mipmap-{density}", "ic_calculator.png")
        if args.check:
            if not os.path.exists(dst):
                state = "现有文件缺失"
            else:
                cur = hashlib.sha256(open(dst, "rb").read()).hexdigest()
                state = "与现有文件一致" if cur == digest else "现有文件不同"
            print(f"  mipmap-{density:10s} {px:4d}px sha={digest[:16]} {len(data):6d}B {state}")
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)
        print(
            f"  mipmap-{density:10s} {px:4d}px sha={digest[:16]} {len(data):6d}B → "
            f"{os.path.relpath(dst, REPO_ROOT)}"
        )

    if not args.check:
        print("\n契约测试要钉的哈希（sha256 前 16 位, 像素边长）：")
        for density, (h, px) in hashes.items():
            print(f"      '{density}': ('{h}', {px}),")

    good = src_ok and fid_ok
    print("\n结果:", "全部一致" if good else "存在差异（见上）")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
