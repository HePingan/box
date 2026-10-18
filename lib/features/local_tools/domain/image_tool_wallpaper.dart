import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 壁纸提取的纯计算部分：把一张图裁成指定屏幕比例。
///
/// 这个工具的名字容易让人误会成"从网上抓壁纸"，实际做的是**从你选的图里
/// 裁出一块能当壁纸的区域**：手机屏幕比例（如 9:19.5）与大多数图片（4:3 / 16:9）
/// 都不一样，直接设成壁纸会被系统拉伸或裁掉主体。所以这里的活是：
/// 按目标比例取最大内接矩形，再让用户决定保留哪一块。
class ImageToolWallpaper {
  const ImageToolWallpaper._();

  /// 把 [source] 裁成 [aspect]（宽/高）比例的最大内接矩形。
  ///
  /// [focus] 决定这块矩形在可移动范围里靠哪边：
  /// 居中 / 靠上 / 靠下（竖图裁竖版时最有用的三个位置）。
  ///
  /// 只裁不放：如果原图比例已经等于目标比例，原样返回（clone 一份）。
  static img.Image crop({
    required img.Image source,
    required double aspect,
    WallpaperFocus focus = WallpaperFocus.center,
  }) {
    if (aspect <= 0) {
      throw ArgumentError('目标比例必须为正（收到 $aspect）');
    }

    final srcAspect = source.width / source.height;

    // 原图比目标更宽 → 以高为准，左右裁；否则以宽为准，上下裁。
    final int cropW;
    final int cropH;
    if (srcAspect > aspect) {
      cropH = source.height;
      cropW = (source.height * aspect).round().clamp(1, source.width);
    } else {
      cropW = source.width;
      cropH = (source.width / aspect).round().clamp(1, source.height);
    }

    // 可移动的余量。
    final slackX = source.width - cropW;
    final slackY = source.height - cropH;

    final (dx, dy) = switch (focus) {
      WallpaperFocus.center => (slackX ~/ 2, slackY ~/ 2),
      WallpaperFocus.top => (slackX ~/ 2, 0),
      WallpaperFocus.bottom => (slackX ~/ 2, slackY),
      WallpaperFocus.left => (0, slackY ~/ 2),
      WallpaperFocus.right => (slackX, slackY ~/ 2),
    };

    return img.copyCrop(
      source,
      x: dx,
      y: dy,
      width: cropW,
      height: cropH,
    );
  }

  /// 编码成 JPEG（壁纸几乎都是照片/插画，PNG 会大很多）。
  static Uint8List encode(img.Image image, {int quality = 92}) =>
      img.encodeJpg(image, quality: quality);
}

/// 常见的壁纸比例。
///
/// 数值取自真实设备分辨率：19.5:9 是近年多数全面屏，16:9 是老机型与 iPad，
/// 1:1 用于桌面小组件/头像。不做"按机型自动识别"——那要读设备信息，
/// 而这里只是裁图，用户自己知道目标设备。
enum WallpaperAspect {
  phoneTall(label: '全面屏 9:19.5', width: 9, height: 19.5),
  phoneClassic(label: '经典 9:16', width: 9, height: 16),
  square(label: '方形 1:1', width: 1, height: 1),
  landscape(label: '横屏 16:9', width: 16, height: 9),
  tablet(label: '平板 4:3', width: 4, height: 3);

  const WallpaperAspect({
    required this.label,
    required this.width,
    required this.height,
  });

  final String label;
  final double width;
  final double height;

  double get ratio => width / height;
}

/// 裁剪时保留哪一块。
enum WallpaperFocus {
  center('居中'),
  top('靠上'),
  bottom('靠下'),
  left('靠左'),
  right('靠右');

  const WallpaperFocus(this.label);

  final String label;
}

/// 给定原图与目标比例，算出裁剪后的尺寸（UI 用来提前显示"会变成多大"）。
(int, int) wallpaperResultSize({
  required int sourceWidth,
  required int sourceHeight,
  required double aspect,
}) {
  if (aspect <= 0) throw ArgumentError('目标比例必须为正');
  final srcAspect = sourceWidth / sourceHeight;
  if (srcAspect > aspect) {
    final w = (sourceHeight * aspect).round().clamp(1, sourceWidth);
    return (w, sourceHeight);
  }
  final h = (sourceWidth / aspect).round().clamp(1, sourceHeight);
  return (sourceWidth, h);
}

/// 需要的裁剪像素数（用于提示"这样会裁掉多少"）。
int wallpaperCroppedPixels({
  required int sourceWidth,
  required int sourceHeight,
  required double aspect,
}) {
  final (w, h) = wallpaperResultSize(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    aspect: aspect,
  );
  return math.max(0, sourceWidth * sourceHeight - w * h);
}
