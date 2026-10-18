import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 格式转换的纯计算部分。
///
/// 最容易翻车的一点是**透明通道**：JPEG 没有 alpha。直接 `encodeJpg` 一个带透明
/// 的图，image 包会丢掉 alpha 而保留原 RGB —— 结果是透明区域变成**黑色或乱色**，
/// 不是用户预期的白底。所以这里强制要求调用方选一个底色，并在结果里如实标记
/// "原图有透明、被我铺掉了"。
class ImageToolConvert {
  const ImageToolConvert._();

  /// 转换到 [format]，按 [flatten] 处理透明。
  static ConvertResult run({
    required img.Image image,
    required ConvertFormat format,
    required FlattenColor flatten,
  }) {
    final hadAlpha = image.hasAlpha;

    // 目标格式不支持透明时，显式铺底（而不是让编码器丢掉 alpha）。
    final work = (format.dropsAlpha && hadAlpha)
        ? _flatten(image, flatten)
        : image;

    final Uint8List bytes;
    switch (format) {
      case ConvertFormat.png:
        bytes = img.encodePng(work);
      case ConvertFormat.jpg:
        // 质量 92：转格式不该顺手降画质，用户要的是"换个容器"。
        bytes = img.encodeJpg(work, quality: 92);
      case ConvertFormat.bmp:
        bytes = img.encodeBmp(work);
    }

    return ConvertResult(
      bytes: bytes,
      extension: format.extension,
      width: work.width,
      height: work.height,
      hadAlpha: hadAlpha,
    );
  }

  static img.Image _flatten(img.Image source, FlattenColor color) {
    final canvas = img.Image(
      width: source.width,
      height: source.height,
      numChannels: 3,
    );
    img.fill(canvas, color: color.rgb);
    img.compositeImage(canvas, source);
    return canvas;
  }
}

/// 可转换的目标格式。
///
/// **刻意不含 WebP**：image 4.x 有 WebP **解码**器，但没有编码器
/// （`encodeWebP` 不存在）。放一个转不出来的格式在列表里，用户点了才发现
/// 不行，比没有这个选项更糟。
enum ConvertFormat {
  png(extension: 'png', label: 'PNG', dropsAlpha: false),
  jpg(extension: 'jpg', label: 'JPEG', dropsAlpha: true),
  bmp(extension: 'bmp', label: 'BMP', dropsAlpha: true);

  const ConvertFormat({
    required this.extension,
    required this.label,
    required this.dropsAlpha,
  });

  final String extension;
  final String label;

  /// 这个格式是否丢透明（丢的话必须让用户选底色）。
  final bool dropsAlpha;
}

/// 铺底颜色（只在目标格式丢透明时用得上）。
///
/// 不把 `img.ColorRgb8` 直接作为枚举值：它不是 const 构造器，
/// 枚举的字段必须是编译期常量。这里存 RGB 三个分量，用时再构造。
enum FlattenColor {
  white(label: '白色', r: 255, g: 255, b: 255),
  black(label: '黑色', r: 0, g: 0, b: 0),
  gray(label: '浅灰', r: 240, g: 240, b: 240);

  const FlattenColor({
    required this.label,
    required this.r,
    required this.g,
    required this.b,
  });

  final String label;
  final int r;
  final int g;
  final int b;

  img.Color get rgb => img.ColorRgb8(r, g, b);
}

/// 一次转换的结果。
class ConvertResult {
  const ConvertResult({
    required this.bytes,
    required this.extension,
    required this.width,
    required this.height,
    required this.hadAlpha,
  });

  final Uint8List bytes;
  final String extension;
  final int width;
  final int height;

  /// 原图是否带透明通道。UI 用它决定要不要提示"已铺底"。
  final bool hadAlpha;
}
