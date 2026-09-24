#!/usr/bin/env python3
"""生成 EXIF 内嵌缩略图的测试夹具（283 D1）。

为什么要生成而不是手写：夹具必须是**真实结构**的 JPEG（真编码器写出的 SOI/APP0/
APP1/Exif/TIFF/IFD0/IFD1 + 内嵌缩略图），手写字节容易写出"只有我自己解析器认得"
的假结构；同时 base64 长字面量不适合手抄。

用法（在仓库根目录）：
    python3 tool/gen_exif_test_fixture.py
产出：
    test/features/extensions/remote_storage/exif_fixtures.dart   （测试引用的夹具常量）

夹具内容：
  kExifJpeg          —— 主图 64×48 JPEG，EXIF 的 IFD1 内嵌 32×24 缩略图，Orientation=6
  kExifJpegNoPrefix  —— 同上，但 APP1 里不带 "Exif\\0\\0" 前缀（少数写入器如此）
  kExifEmbeddedThumb —— 内嵌缩略图的**真值字节**（断言用，不是"再解析一次看两边一样"）
  kJpegWithoutExif   —— 同一张主图但完全没有 EXIF（负样本）
"""
import base64
import io
import struct
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / (
    "test/features/extensions/remote_storage/exif_fixtures.dart"
)
LITTLE = "<"


def _entry(tag: int, typ: int, count: int, value_bytes: bytes) -> bytes:
    return struct.pack(LITTLE + "HHI", tag, typ, count) + value_bytes


def _build_exif(thumb: bytes) -> bytes:
    """IFD0[Make, Orientation, ExifIFD] → ExifIFD[DateTimeOriginal] → IFD1[内嵌缩略图]。"""
    ifd0_entries, exif_entries, ifd1_entries = 3, 1, 4
    ifd0_off = 8
    ifd0_size = 2 + ifd0_entries * 12 + 4
    exif_off = ifd0_off + ifd0_size
    exif_size = 2 + exif_entries * 12 + 4
    ifd1_off = exif_off + exif_size
    ifd1_size = 2 + ifd1_entries * 12 + 4
    thumb_off = ifd1_off + ifd1_size
    make = b"BoxTest\x00"
    make_off = thumb_off + len(thumb)
    dto = b"2021:08:07 13:47:19\x00"
    dto_off = make_off + len(make)

    ifd0 = struct.pack(LITTLE + "H", ifd0_entries)
    ifd0 += _entry(0x010F, 2, len(make), struct.pack(LITTLE + "I", make_off))
    ifd0 += _entry(0x0112, 3, 1, struct.pack(LITTLE + "HH", 6, 0))  # Orientation=6
    ifd0 += _entry(0x8769, 4, 1, struct.pack(LITTLE + "I", exif_off))
    ifd0 += struct.pack(LITTLE + "I", ifd1_off)

    exif_ifd = struct.pack(LITTLE + "H", exif_entries)
    exif_ifd += _entry(0x9003, 2, len(dto), struct.pack(LITTLE + "I", dto_off))
    exif_ifd += struct.pack(LITTLE + "I", 0)

    ifd1 = struct.pack(LITTLE + "H", ifd1_entries)
    ifd1 += _entry(0x0103, 3, 1, struct.pack(LITTLE + "HH", 6, 0))  # Compression=JPEG
    ifd1 += _entry(0x0112, 3, 1, struct.pack(LITTLE + "HH", 1, 0))
    ifd1 += _entry(0x0201, 4, 1, struct.pack(LITTLE + "I", thumb_off))
    ifd1 += _entry(0x0202, 4, 1, struct.pack(LITTLE + "I", len(thumb)))
    ifd1 += struct.pack(LITTLE + "I", 0)

    header = b"II" + struct.pack(LITTLE + "H", 42) + struct.pack(LITTLE + "I", ifd0_off)
    return header + ifd0 + exif_ifd + ifd1 + thumb + make + dto


def main() -> None:
    thumb_img = Image.new("RGB", (32, 24), (200, 30, 30))
    buf = io.BytesIO()
    thumb_img.save(buf, format="JPEG", quality=70)
    thumb = buf.getvalue()

    main_img = Image.new("RGB", (64, 48))
    for x in range(64):
        for y in range(48):
            main_img.putpixel((x, y), (x * 4 % 256, y * 5 % 256, 128))

    exif_block = _build_exif(thumb)

    with_exif = io.BytesIO()
    main_img.save(with_exif, format="JPEG", quality=80, exif=b"Exif\x00\x00" + exif_block)
    no_prefix = io.BytesIO()
    main_img.save(no_prefix, format="JPEG", quality=80, exif=exif_block)
    no_exif = io.BytesIO()
    main_img.save(no_exif, format="JPEG", quality=80)

    fixtures = {
        "kExifJpeg": with_exif.getvalue(),
        "kExifJpegNoPrefix": no_prefix.getvalue(),
        "kExifEmbeddedThumb": thumb,
        "kJpegWithoutExif": no_exif.getvalue(),
    }
    docs = {
        "kExifJpeg": "主图（64×48 JPEG），EXIF 的 IFD1 里内嵌 32×24 缩略图，Orientation=6",
        "kExifJpegNoPrefix": "同上，但 APP1 不带 `Exif\\\\0\\\\0` 前缀（少数写入器如此）",
        "kExifEmbeddedThumb": "内嵌缩略图的**真值字节**（断言用）",
        "kJpegWithoutExif": "同一张主图但完全没有 EXIF（负样本）",
    }

    lines = [
        "// EXIF 内嵌缩略图测试夹具（283 D1）——**生成文件，不要手改**。",
        "//",
        "// 由 `python3 tool/gen_exif_test_fixture.py` 生成：真实编码器（PIL）写出的",
        "// JPEG，EXIF 的 IFD1 内嵌一张独立可解码的小 JPEG。手抄 base64 长字面量",
        "// 容易出错，也不该让测试夹具的字节来源不可复现。",
        "",
        "import 'dart:convert';",
        "import 'dart:typed_data';",
        "",
    ]
    for name, data in fixtures.items():
        b64 = base64.b64encode(data).decode()
        lines.append(f"/// {docs[name]}（{len(data)} 字节）。")
        lines.append(f"final Uint8List {name} = base64Decode(")
        lines.append(f"  '{b64}',")
        lines.append(");")
        lines.append("")
    OUT.write_text("\n".join(lines))
    print(f"已写入 {OUT}")
    for name, data in fixtures.items():
        print(f"  {name}: {len(data)} 字节")


if __name__ == "__main__":
    main()
