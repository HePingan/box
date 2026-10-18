import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图片拼接的纯计算部分。
///
/// 最容易挨骂的一点是**拉伸**：把不同比例的照片硬塞进等大的格子，
/// 人脸会变胖 —— 这是拼接类工具最常见的差评来源。所以这里一律
/// **等比缩放 + 居中留边（letterbox）**，绝不拉伸。
class ImageToolCollage {
  const ImageToolCollage._();

  /// 按网格拼接。[columns] 由调用方按图片数量推荐（见 [suggestColumns]）。
  ///
  /// [gap] 是格子之间的间距（像素），[background] 是留边与间隙的颜色。
  static CollageResult grid({
    required List<img.Image> images,
    required int columns,
    int gap = 8,
    int cellSize = 1080,
    img.Color? background,
  }) {
    if (images.isEmpty) {
      throw ArgumentError('没有可拼接的图片');
    }
    if (columns < 1) {
      throw ArgumentError('列数必须 ≥ 1（收到 $columns）');
    }

    final cols = math.min(columns, images.length);
    final rows = (images.length / cols).ceil();
    final bg = background ?? img.ColorRgb8(255, 255, 255);

    // 每格边长 = (总宽 - 间隙)/列数。所以总宽 = 单元格宽 × 列 + 间隙 × (列-1)。
    final outWidth = cellSize * cols + gap * (cols - 1);
    final outHeight = cellSize * rows + gap * (rows - 1);

    final canvas = img.Image(
      width: outWidth,
      height: outHeight,
      numChannels: 3,
    );
    img.fill(canvas, color: bg);

    for (var i = 0; i < images.length; i++) {
      final r = i ~/ cols;
      final c = i % cols;
      final cellX = c * (cellSize + gap);
      final cellY = r * (cellSize + gap);

      final fitted = _fitInto(images[i], cellSize, cellSize);
      // 居中放置（留边自然对称）。
      final dx = cellX + (cellSize - fitted.width) ~/ 2;
      final dy = cellY + (cellSize - fitted.height) ~/ 2;
      img.compositeImage(canvas, fitted, dstX: dx, dstY: dy);
    }

    return CollageResult(
      image: canvas,
      columns: cols,
      rows: rows,
      cellSize: cellSize,
      gap: gap,
    );
  }

  /// 按 [maxWidth] 等比缩放，不放大。
  ///
  /// 不放大是刻意的：小图放大只会糊，而且拼接的意义是排版不是变清晰。
  static img.Image _fitInto(img.Image src, int maxWidth, int maxHeight) {
    final scale = math.min(maxWidth / src.width, maxHeight / src.height);
    if (scale >= 1) return src;
    final w = (src.width * scale).round().clamp(1, maxWidth);
    final h = (src.height * scale).round().clamp(1, maxHeight);
    return img.copyResize(
      src,
      width: w,
      height: h,
      maintainAspect: false, // w/h 已按同一比例算好，这里不需要再算一次
      interpolation: img.Interpolation.average,
    );
  }

  /// 按图片数量推荐列数：1-2 张并排，3-4 张 2 列，5-9 张 3 列，更多 4 列。
  static int suggestColumns(int count) {
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    return 4;
  }

  /// 编码为 JPEG（拼接产物几乎都是照片混排，PNG 会大很多）。
  static Uint8List encode(img.Image image, {int quality = 90}) =>
      img.encodeJpg(image, quality: quality);
}

/// 一次拼接的布局与产物。
class CollageResult {
  const CollageResult({
    required this.image,
    required this.columns,
    required this.rows,
    required this.cellSize,
    required this.gap,
  });

  final img.Image image;
  final int columns;
  final int rows;
  final int cellSize;
  final int gap;

  int get width => image.width;
  int get height => image.height;
}
