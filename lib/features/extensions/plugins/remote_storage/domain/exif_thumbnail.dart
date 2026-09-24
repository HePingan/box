// EXIF 内嵌缩略图（283 D1）：从 JPEG 的文件开头取出相机写进去的小图。
//
// 为什么需要它：缩略图**必须完整文件才能解码**（JPEG/PNG 都要读到结尾），所以
// "整取一张图来当缩略图"的代价等于原图大小——这就是 `kThumbnailMaxBytes`（3MB）
// 存在的理由，代价是 4MB 以上的照片在列表里只能显示通用图标。
//
// 但手机/相机导出的 JPEG 一般在 EXIF 的 **IFD1** 里内嵌一张 160×120 左右的缩略图
// （`JPEGInterchangeFormat` / `JPEGInterchangeFormatLength`），它是一段**独立可解码
// 的 JPEG**，而且位置就在文件开头几 KB 内。于是"大图缩略图"变成一次有界读
// （[kExifProbeBytes]）+ 一次小图解码。
//
// 本文件是纯逻辑：不做 IO、不引依赖（`dart:core` + `dart:typed_data`）。
// 所有读取都带边界检查——输入是"网络前缀"，随时可能在任意位置被截断。

import 'dart:typed_data';

/// EXIF 内嵌缩略图解析结果。
class ExifThumbnail {
  const ExifThumbnail({required this.bytes, this.orientation});

  /// 内嵌缩略图的 JPEG 字节（已确认以 SOI 开头）。
  final Uint8List bytes;

  /// EXIF Orientation（1–8）；IFD0 里没有该标签时为 null。
  ///
  /// 现在只做记录（列表缩略图不需要方向）；它的价值是给"预览方向修正"留出数据通道，
  /// 那条要不要做取决于真机验证（见方案 §5 未验证项 2）。
  final int? orientation;
}

/// 从 JPEG 字节（可以是文件开头的一段前缀）里取 EXIF 内嵌缩略图。
///
/// 返回 null 的常见原因：不是 JPEG、没有 EXIF、EXIF 里没有 IFD1 缩略图、
/// 缩略图字节被前缀截断、偏移/长度越界。**这些都不是错误**，调用方回退通用图标即可。
ExifThumbnail? parseExifThumbnail(Uint8List data) {
  final tiff = _findExifTiffBlock(data);
  if (tiff == null) return null;
  final reader = _TiffReader(tiff);
  final orientation = reader.shortTag(reader.ifd0Offset, _tagOrientation);
  final ifd1 = reader.nextIfdOffset(reader.ifd0Offset);
  if (ifd1 == null || ifd1 == 0) return null;
  final thumbOffset = reader.longTag(ifd1, _tagThumbnailOffset);
  final thumbLength = reader.longTag(ifd1, _tagThumbnailLength);
  if (thumbOffset == null || thumbLength == null) return null;
  if (thumbLength < 4) return null;
  if (thumbOffset + thumbLength > tiff.length) return null;
  final bytes = Uint8List.fromList(
    Uint8List.sublistView(tiff, thumbOffset, thumbOffset + thumbLength),
  );
  // 内嵌缩略图本身必须是 JPEG（有些写入器往里塞 TIFF 条带，那种解不了）。
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  return ExifThumbnail(bytes: bytes, orientation: orientation);
}

/// 只取 EXIF Orientation（同一份解析逻辑的另一半）。
int? parseExifOrientation(Uint8List data) {
  final tiff = _findExifTiffBlock(data);
  if (tiff == null) return null;
  final reader = _TiffReader(tiff);
  return reader.shortTag(reader.ifd0Offset, _tagOrientation);
}

const int _tagOrientation = 0x0112;
const int _tagThumbnailOffset = 0x0201;
const int _tagThumbnailLength = 0x0202;

/// 最多扫多少个 JPEG 段就放弃：畸形输入不该让解析器无限循环。
const int _maxSegments = 64;

/// 找到 APP1/Exif 段并返回其中的 TIFF 块（不含 `Exif\0\0` 前缀）。
Uint8List? _findExifTiffBlock(Uint8List data) {
  if (data.length < 4 || data[0] != 0xFF || data[1] != 0xD8) return null;
  var i = 2;
  var segments = 0;
  while (i + 4 <= data.length && segments++ < _maxSegments) {
    if (data[i] != 0xFF) return null; // 段边界错乱：放弃，不猜
    final marker = data[i + 1];
    if (marker == 0xFF) {
      i += 1; // 填充字节
      continue;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      i += 2; // 无长度字段的标记
      continue;
    }
    if (marker == 0xDA) return null; // 到了图像数据段：EXIF 只会在它之前
    final length = (data[i + 2] << 8) | data[i + 3];
    if (length < 2) return null;
    final payloadStart = i + 4;
    final payloadEnd = i + 2 + length;
    if (payloadEnd > data.length) {
      // 前缀被截断：如果截断点在 EXIF 段内，说明前缀太小，放弃。
      return null;
    }
    if (marker == 0xE1) {
      final payload = Uint8List.sublistView(data, payloadStart, payloadEnd);
      final block = _asTiffBlock(payload);
      if (block != null) return block;
    }
    i = payloadEnd;
  }
  return null;
}

/// APP1 载荷 → TIFF 块：标准写入器带 `Exif\0\0` 前缀，少数直接写裸 TIFF 头，两种都认。
Uint8List? _asTiffBlock(Uint8List payload) {
  if (payload.length > 6) {
    final hasPrefix =
        payload[0] == 0x45 && // E
        payload[1] == 0x78 && // x
        payload[2] == 0x69 && // i
        payload[3] == 0x66 && // f
        payload[4] == 0x00 &&
        payload[5] == 0x00;
    if (hasPrefix) return Uint8List.sublistView(payload, 6);
  }
  if (_looksLikeTiffHeader(payload)) return payload;
  return null;
}

bool _looksLikeTiffHeader(Uint8List b) {
  if (b.length < 8) return false;
  final little = b[0] == 0x49 && b[1] == 0x49; // II
  final big = b[0] == 0x4D && b[1] == 0x4D; // MM
  if (!little && !big) return false;
  final magic = little ? (b[2] | (b[3] << 8)) : ((b[2] << 8) | b[3]);
  return magic == 42;
}

/// TIFF 块读取器（带字节序与边界处理）。
class _TiffReader {
  _TiffReader(this.bytes) : _littleEndian = _isLittleEndian(bytes);

  final Uint8List bytes;
  final bool _littleEndian;

  static bool _isLittleEndian(Uint8List b) => b.length >= 2 && b[0] == 0x49;

  int get ifd0Offset {
    final value = _uint32(4);
    // IFD0 偏移越界时退回 8（TIFF 规范里 IFD0 紧跟在头之后）。
    return value == null || value + 2 > bytes.length ? 8 : value;
  }

  int? _uint16(int at) {
    if (at < 0 || at + 2 > bytes.length) return null;
    return _littleEndian
        ? bytes[at] | (bytes[at + 1] << 8)
        : (bytes[at] << 8) | bytes[at + 1];
  }

  int? _uint32(int at) {
    if (at < 0 || at + 4 > bytes.length) return null;
    return _littleEndian
        ? bytes[at] |
              (bytes[at + 1] << 8) |
              (bytes[at + 2] << 16) |
              (bytes[at + 3] << 24)
        : (bytes[at] << 24) |
              (bytes[at + 1] << 16) |
              (bytes[at + 2] << 8) |
              bytes[at + 3];
  }

  /// IFD 的条目数（读不到为 0）。
  int _entryCount(int ifdOffset) => _uint16(ifdOffset) ?? 0;

  /// 某个 IFD 里指定 tag 的条目位置（值区起始处）。
  int? _entryAt(int ifdOffset, int tag) {
    final count = _entryCount(ifdOffset);
    for (var k = 0; k < count; k++) {
      final at = ifdOffset + 2 + k * 12;
      if (at + 12 > bytes.length) return null;
      if (_uint16(at) == tag) return at;
    }
    return null;
  }

  /// 取 SHORT 型 tag 的值（内联在条目值区的前两字节）。
  int? shortTag(int ifdOffset, int tag) {
    final at = _entryAt(ifdOffset, tag);
    if (at == null) return null;
    return _uint16(at + 8);
  }

  /// 取 LONG 型 tag 的值（内联在条目值区的四字节）。
  int? longTag(int ifdOffset, int tag) {
    final at = _entryAt(ifdOffset, tag);
    if (at == null) return null;
    return _uint32(at + 8);
  }

  /// IFD 之后的"下一个 IFD"偏移（IFD1 就在这里）。
  int? nextIfdOffset(int ifdOffset) =>
      _uint32(ifdOffset + 2 + _entryCount(ifdOffset) * 12);
}
