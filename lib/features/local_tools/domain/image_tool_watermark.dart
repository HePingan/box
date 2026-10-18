import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 给图片加文字水印的纯计算部分。
///
/// ## 一个必须提前说清楚的限制：**只支持 ASCII，中文画不出来**
///
/// `image` 包只内置三款位图字体（`arial14/24/48`），字形表里没有汉字。
/// 实测（`drawString` 画 "中文"）：深色像素数为 **0** —— 不是画得难看，是
/// 一个像素都不画。而 ASCII（"Hello"）正常出 299 个深色像素。
///
/// 所以 [textRenders] 这个函数存在的意义就是：**在用户按下"加文字"之前**
/// 告诉他这段文字会被画成空白，而不是让他对着一张没有任何水印的图发愣。
///
/// 想支持中文只有两条路，都要额外成本：
///   * 打包一个自带汉字的 TTF + 用 `BitmapFont.fromZip`/自绘字形；
///   * 改用 `dart:ui` 的 TextPainter 渲染文字成图片，再叠到原图上
///     （这条路可行，但要处理字体加载与 DPI，属于独立一版）。
class ImageToolWatermark {
  const ImageToolWatermark._();

  /// 这个字符串能否被位图字体画出来。
  ///
  /// 判据：每一个字符的码点都 < 0x80（ASCII）。比逐个字形查表简单，
  /// 而且对这些固定字体是准确的。
  static bool textRenders(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x80) return false;
    }
    return true;
  }

  /// 在图上绘制文字水印，返回新的图（不改原图）。
  ///
  /// [scale] 决定用哪款内置字体：<=1 用 14px，<=2 用 24px，否则 48px。
  /// 字号是**离散**的：位图字体不能任意缩，硬缩放只会糊。
  static img.Image apply({
    required img.Image image,
    required String text,
    required WatermarkAnchor anchor,
    required double opacity,
    required int scale,
    img.Color? color,
  }) {
    if (text.trim().isEmpty) {
      throw ArgumentError('水印文字不能为空');
    }
    if (!textRenders(text)) {
      throw ArgumentError(
        '水印文字含非 ASCII 字符（如中文），位图字体画不出来 —— '
        '请用英文、数字或符号',
      );
    }

    final font = _fontForScale(scale);
    // 复制一份：调用方可能还要用原图（比如重试另一次水印）。
    final canvas = image.clone();

    final textWidth = _measure(text, font);
    final textHeight = font.lineHeight;
    final pos = anchor.compute(
      canvasWidth: canvas.width,
      canvasHeight: canvas.height,
      textWidth: textWidth,
      textHeight: textHeight,
    );

    // opacity 通过颜色的 alpha 实现；这里把用户给的不透明度乘进 alpha。
    final a = (opacity.clamp(0.0, 1.0) * 255).round();
    final base = color ?? img.ColorRgb8(255, 255, 255);
    final paint = img.ColorRgba8(base.r.toInt(), base.g.toInt(), base.b.toInt(), a);

    // 描边：在四个方向各偏移 1px 画一遍深色字，再画正色字。
    // 目的不是好看 —— 浅色背景上的白字不加描边等于没加（用户会以为水印没生效）。
    final shadow = img.ColorRgba8(0, 0, 0, (a * 0.85).round());
    for (final d in const [
      (1, 0),
      (-1, 0),
      (0, 1),
      (0, -1),
    ]) {
      img.drawString(
        canvas,
        text,
        font: font,
        x: pos.$1 + d.$1,
        y: pos.$2 + d.$2,
        color: shadow,
      );
    }

    img.drawString(canvas, text, font: font, x: pos.$1, y: pos.$2, color: paint);
    return canvas;
  }

  /// 编码为 JPEG（水印图绝大多数是照片，PNG 会大很多）。
  static Uint8List encode(img.Image image, {int quality = 92}) =>
      img.encodeJpg(image, quality: quality);

  static img.BitmapFont _fontForScale(int scale) {
    if (scale <= 1) return img.arial14;
    if (scale <= 2) return img.arial24;
    return img.arial48;
  }

  /// 估宽：位图字体是等宽表，但空格与字母宽度不同，这里用实际绘制量测。
  ///
  /// 简单做法：画到一张临时透明图上再扫非透明像素的包围盒。
  /// 比起猜字符宽度，这样对任意 ASCII 串都准（含空格结尾的情况除外，
  /// 而水印末尾的空格没有意义，所以不处理）。
  static int _measure(String text, img.BitmapFont font) {
    // 先给一个足够大的画布再量。
    final wide = img.Image(
      width: text.length * font.size * 2 + 8,
      height: font.lineHeight + 4,
      numChannels: 4,
    );
    img.fill(wide, color: img.ColorRgba8(0, 0, 0, 0));
    img.drawString(
      wide,
      text,
      font: font,
      x: 0,
      y: 0,
      color: img.ColorRgba8(255, 255, 255, 255),
    );

    var maxX = 0;
    for (var y = 0; y < wide.height; y++) {
      for (var x = 0; x < wide.width; x++) {
        if (wide.getPixel(x, y).a > 0 && x > maxX) maxX = x;
      }
    }
    return maxX + 1;
  }
}

/// 水印的九个位置。
enum WatermarkAnchor {
  topLeft('左上'),
  topCenter('上中'),
  topRight('右上'),
  centerLeft('左中'),
  center('正中'),
  centerRight('右中'),
  bottomLeft('左下'),
  bottomCenter('下中'),
  bottomRight('右下');

  const WatermarkAnchor(this.label);

  final String label;

  /// 算出左上角坐标，四周留 [margin] 像素边距。
  (int, int) compute({
    required int canvasWidth,
    required int canvasHeight,
    required int textWidth,
    required int textHeight,
    int margin = 16,
  }) {
    final x = switch (this) {
      WatermarkAnchor.topLeft ||
      WatermarkAnchor.centerLeft ||
      WatermarkAnchor.bottomLeft => margin,
      WatermarkAnchor.topCenter ||
      WatermarkAnchor.center ||
      WatermarkAnchor.bottomCenter => ((canvasWidth - textWidth) ~/ 2).clamp(0, 1 << 30),
      WatermarkAnchor.topRight ||
      WatermarkAnchor.centerRight ||
      WatermarkAnchor.bottomRight => (canvasWidth - textWidth - margin).clamp(0, 1 << 30),
    };
    final y = switch (this) {
      WatermarkAnchor.topLeft ||
      WatermarkAnchor.topCenter ||
      WatermarkAnchor.topRight => margin,
      WatermarkAnchor.centerLeft ||
      WatermarkAnchor.center ||
      WatermarkAnchor.centerRight => ((canvasHeight - textHeight) ~/ 2).clamp(0, 1 << 30),
      WatermarkAnchor.bottomLeft ||
      WatermarkAnchor.bottomCenter ||
      WatermarkAnchor.bottomRight => (canvasHeight - textHeight - margin).clamp(0, 1 << 30),
    };
    return (x, y);
  }
}
