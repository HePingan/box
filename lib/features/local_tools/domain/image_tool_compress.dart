import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图片压缩的纯计算部分：参数决策 + 编码。
///
/// 为什么单独一层：压缩最容易出错的地方不是"调哪个 API"，而是**决策**——
/// 该不该缩、缩到多大、编码后到底有没有变小。这些判断能脱离 UI 与平台通道测试。
///
/// 三条刻意的规则（都有测试锁着）：
/// 1. **只缩不放**：原图小于目标尺寸时不动，放大只会糊而且更大；
/// 2. **压完更大 = 不值得存**：PNG→JPEG 有时反而变大（大面积纯色图），
///    这时必须让调用方知道"保留原图"，而不是给用户一个更大的文件还说"已压缩"；
/// 3. **本来就很小的图不重编码**：重编码一定引入代际损失，
///    为了省几 KB 去损失画质不值。
class ImageToolCompress {
  const ImageToolCompress._();

  /// 小于这个体积就不压了：再压省不了多少，画质一定掉。
  static const int skipBelowBytes = 80 * 1024;

  /// 按预设压缩一张图。
  static CompressResult run({
    required img.Image image,
    required CompressPreset preset,
    required int originalBytes,
  }) {
    final targetMax = preset.maxDimension;

    // 规则 1 + 3：不需要处理的情况直接返回原图信息，由调用方决定"保留原图"。
    //
    // 判据只看**尺寸**是否超限，不看原图体积 —— 体积交给编码后再比
    // （见下面的 isWorthSaving）。这两个判断必须分开：
    //   * 尺寸超限 = 必须缩（用户要的就是变小，缩了必然小）；
    //   * 尺寸没超 = 不重编码（重编码只掉画质）；
    //     这时如果原图本来就小，就是 alreadySmall；如果原图很大（比如 PNG
    //     无损大图），转 JPEG 仍然可能显著变小 —— 那种情况不该被"alreadySmall"挡掉。
    final needsResize = targetMax != null &&
        (image.width > targetMax || image.height > targetMax);
    if (!needsResize && originalBytes <= skipBelowBytes) {
      return CompressResult(
        bytes: Uint8List(0),
        width: image.width,
        height: image.height,
        extension: 'jpg',
        originalBytes: originalBytes,
        reason: CompressSkipReason.alreadySmall,
      );
    }

    var work = image;
    if (needsResize) {
      // maintainAspect 保证不拉伸；width/height 只给一个即可。
      work = img.copyResize(
        image,
        width: image.width >= image.height ? targetMax : null,
        height: image.height > image.width ? targetMax : null,
        maintainAspect: true,
        interpolation: img.Interpolation.average,
      );
    }

    // JPEG 没有透明通道：压缩一律用 JPEG（体积小得多），透明区域铺白。
    // 想保留透明的用户应该选「格式转换 → PNG」，而不是压缩。
    final flattened = _flattenOnWhite(work);

    final bytes = img.encodeJpg(flattened, quality: preset.jpegQuality);
    return CompressResult(
      bytes: bytes,
      width: flattened.width,
      height: flattened.height,
      extension: 'jpg',
      originalBytes: originalBytes,
    );
  }

  /// 把透明区域铺成白色（JPEG 不支持 alpha）。
  ///
  /// 先铺白底再叠原图：直接 `encodeJpg` 一个带 alpha 的图，image 包会**丢掉**
  /// alpha 通道，半透明像素会变成奇怪的颜色（不是变白，是按原 RGB 直接留下）。
  static img.Image _flattenOnWhite(img.Image source) {
    if (!source.hasAlpha) return source;

    final canvas = img.Image(
      width: source.width,
      height: source.height,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, source);
    return canvas;
  }
}

/// 压缩预设。数值是拍的，选型理由写在每个取值上。
enum CompressPreset {
  /// 体积优先：长边 1280、质量 72。发群/朋友圈够用。
  small(maxDimension: 1280, jpegQuality: 72),

  /// 平衡：长边 2048、质量 82。默认值，肉眼很难看出与原图差别。
  balanced(maxDimension: 2048, jpegQuality: 82),

  /// 画质优先：只限长边 4096、质量 92。接近原图，但仍能省一些。
  quality(maxDimension: 4096, jpegQuality: 92);

  const CompressPreset({
    required this.maxDimension,
    required this.jpegQuality,
  });

  /// 长边上限（像素）。null = 不限。
  final int? maxDimension;

  /// JPEG 质量（1-100）。
  final int jpegQuality;

  String get label {
    switch (this) {
      case CompressPreset.small:
        return '体积优先';
      case CompressPreset.balanced:
        return '平衡';
      case CompressPreset.quality:
        return '画质优先';
    }
  }

  String get explanation {
    switch (this) {
      case CompressPreset.small:
        return '长边缩到 1280、质量 72 —— 发消息/朋友圈够用';
      case CompressPreset.balanced:
        return '长边缩到 2048、质量 82 —— 默认，肉眼几乎看不出差别';
      case CompressPreset.quality:
        return '长边最多 4096、质量 92 —— 接近原图，省得少';
    }
  }
}

/// 没能产出新文件的原因（调用方用它决定对用户说什么）。
enum CompressSkipReason {
  /// 原图本来就不大，且尺寸没超限 → 不值得重编码。
  alreadySmall,

  /// 编码成功，但比原图更大 → 应该保留原图。
  biggerThanOriginal,
}

/// 一次压缩的结果。
class CompressResult {
  const CompressResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.extension,
    required this.originalBytes,
    this.reason,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String extension;
  final int originalBytes;

  /// 非空表示"这次没有值得保存的新文件"，调用方应保留原图。
  final CompressSkipReason? reason;

  /// 新文件是否比原图小（且确实产出了文件）。
  ///
  /// 这个判断必须由这里给出，不能让 UI 自己算 —— 否则迟早出现
  /// "界面说已压缩、实际存了个更大的文件"。
  bool get isWorthSaving {
    if (reason != null) return false;
    if (bytes.isEmpty) return false;
    return bytes.length < originalBytes;
  }

  /// 省下的字节数（可能为负；调用方展示前应判 [isWorthSaving]）。
  int get savedBytes => originalBytes - bytes.length;
}
