// 格式转换：透明通道的处理是重点。
//
// image 包对带 alpha 的图直接 encodeJpg 会**丢掉** alpha 而保留原 RGB ——
// 结果是透明区域变成黑色或乱色，而不是用户预期的白底。这条测试锁住：
// 转 JPEG/BMP 时必须显式铺底，且结果要如实报告"原图有过透明"。
import 'package:box/features/local_tools/domain/image_tool_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _rgba() {
  final im = img.Image(width: 40, height: 40, numChannels: 4);
  for (var y = 0; y < 40; y++) {
    for (var x = 0; x < 40; x++) {
      // 全透明
      im.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  return im;
}

img.Image _rgb() {
  final im = img.Image(width: 30, height: 20, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(10, 20, 30));
  return im;
}

void main() {
  group('透明处理', () {
    test('全透明图转 PNG：保留透明，不铺底', () {
      final result = ImageToolConvert.run(
        image: _rgba(),
        format: ConvertFormat.png,
        flatten: FlattenColor.white,
      );

      final back = img.decodePng(result.bytes)!;
      expect(back.getPixel(5, 5).a, 0, reason: 'PNG 支持透明，不该被铺底');
      expect(result.hadAlpha, isTrue, reason: '要如实报告原图带透明');
    });

    test('全透明图转 JPEG：按选定底色铺底（白）', () {
      final result = ImageToolConvert.run(
        image: _rgba(),
        format: ConvertFormat.jpg,
        flatten: FlattenColor.white,
      );

      final back = img.decodeJpg(result.bytes)!;
      final p = back.getPixel(5, 5);
      expect(p.r, greaterThan(240), reason: '透明区必须变成白底');
      expect(p.g, greaterThan(240));
      expect(p.b, greaterThan(240));
    });

    test('转 JPEG 选黑底时确实铺黑（不是固定白底）', () {
      final result = ImageToolConvert.run(
        image: _rgba(),
        format: ConvertFormat.jpg,
        flatten: FlattenColor.black,
      );

      final back = img.decodeJpg(result.bytes)!;
      final p = back.getPixel(5, 5);
      expect(p.r, lessThan(20), reason: '用户选了黑底就该是黑底');
      expect(p.g, lessThan(20));
      expect(p.b, lessThan(20));
    });

    test('不带透明的图转 JPEG：不铺底（避免多余的一次合成）', () {
      final result = ImageToolConvert.run(
        image: _rgb(),
        format: ConvertFormat.jpg,
        flatten: FlattenColor.white,
      );

      final back = img.decodeJpg(result.bytes)!;
      final p = back.getPixel(5, 5);
      // 原色 (10,20,30) 应基本保留；若被铺白会变成 ~255。
      expect(p.r, lessThan(40));
      expect(result.hadAlpha, isFalse);
    });
  });

  group('格式与尺寸', () {
    test('每种格式的扩展名与尺寸正确', () {
      for (final f in ConvertFormat.values) {
        final result = ImageToolConvert.run(
          image: _rgb(),
          format: f,
          flatten: FlattenColor.white,
        );
        expect(result.extension, f.extension);
        expect(result.width, 30);
        expect(result.height, 20);
        expect(result.bytes, isNotEmpty, reason: '${f.label} 应产出字节');
      }
    });

    test('PNG 产出的是真 PNG（解回来不报错）', () {
      final result = ImageToolConvert.run(
        image: _rgb(),
        format: ConvertFormat.png,
        flatten: FlattenColor.white,
      );
      expect(img.decodePng(result.bytes), isNotNull);
    });

    test('JPEG 产出的是真 JPEG', () {
      final result = ImageToolConvert.run(
        image: _rgb(),
        format: ConvertFormat.jpg,
        flatten: FlattenColor.white,
      );
      expect(img.decodeJpg(result.bytes), isNotNull);
    });

    test('BMP 产出的是真 BMP', () {
      final result = ImageToolConvert.run(
        image: _rgb(),
        format: ConvertFormat.bmp,
        flatten: FlattenColor.white,
      );
      expect(img.decodeBmp(result.bytes), isNotNull);
    });
  });

  group('格式能力声明', () {
    test('只有 JPEG/BMP 声明丢透明（PNG 不丢）', () {
      expect(ConvertFormat.png.dropsAlpha, isFalse);
      expect(ConvertFormat.jpg.dropsAlpha, isTrue);
      expect(ConvertFormat.bmp.dropsAlpha, isTrue);
    });

    test('三个底色选项都有中文名', () {
      for (final c in FlattenColor.values) {
        expect(c.label, isNotEmpty);
      }
    });
  });
}
