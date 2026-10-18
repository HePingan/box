// 图片压缩的纯计算：参数决策 + 编码。
//
// 这张测试真正要守的不是"能不能编码"（那是 image 包的事），而是**决策**：
//   * 小图不重编码（重编码一定掉画质，为几 KB 不值）
//   * 只缩不放（放大会糊且更大）
//   * 压完更大时必须能被识别出来（否则界面会拿一个更大的文件说"已压缩"）
import 'package:box/features/local_tools/domain/image_tool_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 造一张带渐变噪声的图（纯色的图 JPEG 压缩率极高，测不出真实体积关系）。
img.Image _noisy(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, (x * 7 + y * 13) % 256, (x * 11) % 256, (y * 17) % 256);
    }
  }
  return im;
}

void main() {
  group('不该压的情况', () {
    test('尺寸没超限且体积很小 → alreadySmall，不给新文件', () {
      final small = _noisy(80, 80);
      final result = ImageToolCompress.run(
        image: small,
        preset: CompressPreset.balanced,
        // 故意报一个很小的原始体积（模拟"本来就几十 KB"）
        originalBytes: 10 * 1024,
      );

      expect(result.reason, CompressSkipReason.alreadySmall);
      expect(result.isWorthSaving, isFalse);
      expect(result.bytes, isEmpty);
    });

    test('小图但尺寸超限 → 仍然要压（尺寸是硬条件）', () {
      final big = _noisy(3000, 2000);
      final result = ImageToolCompress.run(
        image: big,
        preset: CompressPreset.small,
        originalBytes: 10 * 1024,
      );

      expect(result.reason, isNull);
      expect(result.width, 1280, reason: '长边要缩到 1280');
      expect(result.height, 853, reason: '等比：2000 * 1280/3000 ≈ 853');
    });
  });

  group('只缩不放', () {
    test('原图小于目标长边时不放大', () {
      final small = _noisy(400, 300);
      final result = ImageToolCompress.run(
        image: small,
        preset: CompressPreset.balanced, // 长边上限 2048
        originalBytes: 500 * 1024, // 逼它走编码路径
      );

      expect(result.width, 400);
      expect(result.height, 300);
    });

    test('横图按宽缩、竖图按高缩，比例保持', () {
      final landscape = _noisy(4000, 2000);
      final r1 = ImageToolCompress.run(
        image: landscape,
        preset: CompressPreset.small,
        originalBytes: 5 * 1024 * 1024,
      );
      expect(r1.width, 1280);
      expect(r1.height, 640);

      final portrait = _noisy(2000, 4000);
      final r2 = ImageToolCompress.run(
        image: portrait,
        preset: CompressPreset.small,
        originalBytes: 5 * 1024 * 1024,
      );
      expect(r2.width, 640);
      expect(r2.height, 1280);
    });
  });

  group('压缩是否值得保存', () {
    test('大图压完确实更小 → isWorthSaving 为真', () {
      final big = _noisy(3000, 3000);
      // 用真实编码后的大小当作"原图"，再压一次必定更小。
      final originalSize = img.encodeJpg(big, quality: 95).length;

      final result = ImageToolCompress.run(
        image: big,
        preset: CompressPreset.small,
        originalBytes: originalSize,
      );

      expect(result.isWorthSaving, isTrue);
      expect(result.savedBytes, greaterThan(0));
      expect(result.extension, 'jpg');
    });

    test('尺寸没超限时一律不编码（哪怕自报体积很大）', () {
      // 判据是"尺寸是否超限"，不是"自报体积"。1200x1200 没超过 small 的
      // 1280 上限，所以走 alreadySmall、不产出文件。
      final result = ImageToolCompress.run(
        image: _noisy(1200, 1200),
        preset: CompressPreset.small,
        originalBytes: 1,
      );

      expect(result.reason, CompressSkipReason.alreadySmall);
      expect(result.bytes, isEmpty);
    });

    test('压完比原图大 → isWorthSaving 为假（界面据此保留原图）', () {
      // 2000x2000 超过 small 的 1280 上限 → 一定会编码；
      // 再把 originalBytes 报成 1 字节，模拟"压完反而更大"。
      final r2 = ImageToolCompress.run(
        image: _noisy(2000, 2000),
        preset: CompressPreset.small,
        originalBytes: 1,
      );

      expect(
        r2.isWorthSaving,
        isFalse,
        reason: '编码成功但比原图大时，绝不能告诉用户"已压缩"',
      );
      expect(r2.reason, isNull, reason: '这次是"更大"，不是 alreadySmall');
      expect(r2.bytes, isNotEmpty, reason: '文件确实产出了，只是不值得存');
    });
  });

  group('透明处理', () {
    test('带透明的图压成 JPEG 时铺白底（不是留下乱色）', () {
      final withAlpha = img.Image(width: 200, height: 200, numChannels: 4);
      // 左半透明、右半不透明红
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          if (x < 100) {
            withAlpha.setPixelRgba(x, y, 0, 0, 0, 0);
          } else {
            withAlpha.setPixelRgba(x, y, 255, 0, 0, 255);
          }
        }
      }

      final result = ImageToolCompress.run(
        image: withAlpha,
        preset: CompressPreset.balanced,
        originalBytes: 10 * 1024 * 1024,
      );

      // 解回来检查左半区域是否变成接近白色（JPEG 有损，给一点容差）。
      final decoded = img.decodeJpg(result.bytes)!;
      final p = decoded.getPixel(10, 10);
      expect(p.r, greaterThan(200), reason: '透明区应被铺成白底');
      expect(p.g, greaterThan(200));
      expect(p.b, greaterThan(200));
    });
  });

  group('预设参数', () {
    test('三档的长边与质量是递减/递增关系（别写反）', () {
      expect(CompressPreset.small.maxDimension, lessThan(CompressPreset.balanced.maxDimension!));
      expect(CompressPreset.balanced.maxDimension, lessThan(CompressPreset.quality.maxDimension!));
      expect(CompressPreset.small.jpegQuality, lessThan(CompressPreset.balanced.jpegQuality));
      expect(CompressPreset.balanced.jpegQuality, lessThan(CompressPreset.quality.jpegQuality));
    });

    test('每档都有中文标签与说明', () {
      for (final p in CompressPreset.values) {
        expect(p.label, isNotEmpty);
        expect(p.explanation, isNotEmpty);
      }
    });
  });
}
