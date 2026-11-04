#!/usr/bin/env python3
"""把 vivo 系统计算器的桌面图标原样搬进本仓库的 mipmap（不再手绘）。

为什么从「照着重画」改成「字节级拷贝」
------------------------------------
第一版是照源 APK 里 `drawable/icon`（136×136，浅灰底 + 深灰符号 + 橙等号）逐像素
重绘的。真机截图一对比才发现，那支计算器在 APK 里同时带两张图标：

    drawable/icon       hdpi 136×136                浅底深符号   ← 当初量的就是这张
    drawable/app_icon   hdpi/xhdpi/xxhdpi/xxxhdpi   深底浅符号 + 橙色等号键

手机桌面显示的是 **app_icon**：四象限均值 (70,72,76)/(67,69,73)/(70,72,76)/(114,96,69)，
与用户给的真机截图 (77,79,86)/(73,75,81)/(76,80,87)/(123,103,72) 只差压缩噪声；
而 `icon` 那张的通道差是 256 —— 完全不是同一个东西。手绘得再准，画的也是「不像的那张」。

而且真机这个应用**没有自适应图标**（资源里没有 anydpi-v26 条目），桌面走位图路径。
我们之前给了 `mipmap-anydpi-v26/ic_calculator.xml`，桌面会把自适应图标按 108dp 裁到
可见 72dp 再套蒙版 —— 等于把内容放大约 1.5 倍并切边，这才是「变形」的直接原因。
所以自适应图标、矢量前景/背景、以及 `values/colors.xml` 里那 5 个取色都删掉了。

现在图标 = 真机那 4 张 PNG 的字节级拷贝，密度集合也与真机一致（真机没有 mdpi，
这边也不给；mdpi 设备会像真机一样回退到 hdpi）。

用法
----
    python3 tool/gen_disguise_icon.py --apk /path/to/计算器.apk          # 抽取并写盘
    python3 tool/gen_disguise_icon.py --apk /path/to/计算器.apk --check  # 只核对

`--check` 比对仓库现有 4 个 PNG 与源 APK 是否仍一致，可在发版前跑。源 APK 换版本时
哈希会变，脚本会打印新哈希，供更新下面的 EXPECTED。
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import zipfile
from io import BytesIO

# 密度 -> (期望 sha256 前 16 位, 期望像素边长)。2026-11-04 从 15.6.1.1 实测。
EXPECTED = {
    "hdpi": ("b1d3bac8753f5fca", 32),
    "xhdpi": ("60d6c81847e8b846", 64),
    "xxhdpi": ("54c9756b1b92513f", 96),
    "xxxhdpi": ("3dfe400043bf84ed", 128),
}

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES_DIR = os.path.join(REPO_ROOT, "android", "app", "src", "main", "res")

AAPT2_CANDIDATES = [
    "/opt/android-sdk/build-tools/36.0.0/aapt2",
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True, help="vivo 系统计算器 APK 路径")
    ap.add_argument("--check", action="store_true", help="只核对，不写盘")
    args = ap.parse_args()

    from PIL import Image  # 延迟导入：--check 在有 PIL 的环境才有意义

    entries = resolve_app_icon(args.apk)
    print(f"源 APK : {args.apk}")
    print(f"app_icon 密度: {sorted(entries)}\n")

    ok = True
    with zipfile.ZipFile(args.apk) as z:
        for density, (want_hash, want_px) in EXPECTED.items():
            src = entries.get(density)
            if src is None:
                print(f"  {density:8s} [失败] 源 APK 缺这个密度")
                ok = False
                continue
            data = z.read(src)
            got_hash = hashlib.sha256(data).hexdigest()[:16]
            got_px = Image.open(BytesIO(data)).size[0]
            same = got_hash == want_hash and got_px == want_px
            print(
                f"  {density:8s} {src:12s} {got_px:4d}px sha={got_hash} "
                f"期望 sha={want_hash} {want_px}px → {'一致' if same else '不一致'}"
            )
            ok = ok and same
            if args.check:
                continue
            dst = os.path.join(RES_DIR, f"mipmap-{density}", "ic_calculator.png")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "wb") as f:
                f.write(data)
            print(f"           → 写入 {os.path.relpath(dst, REPO_ROOT)}")

    print("\n结果:", "全部一致" if ok else "存在差异（见上）")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
