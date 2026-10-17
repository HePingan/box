import 'dart:math' as math;

/// 九宫格切图的纯计算部分：把一张宽高切成 [rows]×[cols] 个块。
///
/// 为什么把这一层单独拿出来：切图的边界计算（除不尽时余数落在哪、封面
/// 多出一条 1px 缝）是最容易错的地方，而它完全可以脱离 Canvas 测。
/// UI 只负责「按这里给出的矩形去裁」。
///
/// 不做的事（刻意）：
///   * 不缩放 —— 切图是**无损裁切**，原图多大切出来就多大；
///   * 不补边 —— 除不尽时把余下的像素并入最后一行/列，避免出现 1px 白缝
///     （按 `width ~/ 3` 切三刀的做法会丢/多出像素，真机上就是一条缝）。
class GridCutGeometry {
  const GridCutGeometry._();

  /// 计算 [width]×[height] 按 [rows]×[cols] 切分后的块边界。
  ///
  /// 返回长度为 `rows * cols` 的列表，每项是 `(left, top, width, height)`，
  /// 顺序为**从左到右、从上到下**（九宫格的自然阅读序）。
  ///
  /// 除不尽时余数并入最后一块：三块宽度为 `w ~/ 3, w ~/ 3, w - 2*(w ~/ 3)`。
  /// 这样三块加起来**严格等于原宽**，拼回去与原图逐像素一致。
  static List<Rect> split({
    required int width,
    required int height,
    int rows = 3,
    int cols = 3,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('图片尺寸必须为正（收到 $width×$height）');
    }
    if (rows <= 0 || cols <= 0) {
      throw ArgumentError('行列数必须为正（收到 $rows×$cols）');
    }
    if (rows > height || cols > width) {
      throw ArgumentError('切块数比像素还多（$width×$height 切 $rows×$cols）');
    }

    final xs = _edges(width, cols);
    final ys = _edges(height, rows);

    final out = <Rect>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        out.add(
          Rect(
            left: xs[c].$1,
            top: ys[r].$1,
            width: xs[c].$2 - xs[c].$1,
            height: ys[r].$2 - ys[r].$1,
          ),
        );
      }
    }
    return out;
  }

  /// 把 [total] 像素切成 [parts] 段，返回每段的 `(起, 止)`。
  ///
  /// 余数全部给最后一段（而不是均摊到每段）：均摊会在中间产生
  /// 1px 缝，而 `|起-止|` 逐段相加必须严格等于 total。
  static List<(int, int)> _edges(int total, int parts) {
    final base = total ~/ parts;
    final edges = <(int, int)>[];
    var start = 0;
    for (var i = 0; i < parts; i++) {
      final end = i == parts - 1 ? total : start + base;
      edges.add((start, end));
      start = end;
    }
    return edges;
  }

  /// 形状建议：原图接近正方形时给 3×3，明显偏宽/偏长时按比例选。
  ///
  /// 只是给 UI 一个默认值，用户随时可改 —— 所以这里不追求"最优解"，
  /// 只要别在 16:9 的图上默认给 3×3 就行。
  static (int rows, int cols) suggestGrid(int width, int height) {
    if (width <= 0 || height <= 0) return (3, 3);
    final ratio = width / height;
    if (ratio > 1.4) return (2, 4); // 横图：更像朋友圈长图切法
    if (ratio < 0.71) return (4, 2); // 竖图
    return (3, 3);
  }
}

/// 一个矩形块（不依赖 dart:ui，方便纯 Dart 单测）。
class Rect {
  const Rect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;

  @override
  String toString() => 'Rect($left,$top $width×$height)';

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// 校验一张图能不能按 [rows]×[cols] 切：块太小就没意义了。
///
/// 20px 是拍的：再小的话切出来连缩略图都不够看，属于"操作能跑但没意义"。
bool canSplitInto({required int width, required int height, required int rows, required int cols}) {
  if (width <= 0 || height <= 0 || rows <= 0 || cols <= 0) return false;
  return math.min(width ~/ cols, height ~/ rows) >= 20;
}
