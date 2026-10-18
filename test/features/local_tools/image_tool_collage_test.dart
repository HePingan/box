// 图片拼接：重点锁住"不拉伸"。
//
// 拼接类工具最常见的差评就是"把人脸拉变形了" —— 把 4:3 和 16:9 的照片硬塞进
// 等大的方格子，必然有一个方向被拉。这里一律等比缩放 + 居中留边（letterbox），
// 所以测试要能证明：宽高比不同的图拼进去，比例仍然保持。
import 'package:box/features/local_tools/domain/image_tool_collage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _solid(int w, int h, int r, int g, int b) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return im;
}

void main() {
  group('网格尺寸计算', () {
    test('4 张图、2 列 → 2 行；总尺寸含间隙', () {
      final result = ImageToolCollage.grid(
        images: [
          _solid(100, 100, 255, 0, 0),
          _solid(100, 100, 0, 255, 0),
          _solid(100, 100, 0, 0, 255),
          _solid(100, 100, 255, 255, 0),
        ],
        columns: 2,
        cellSize: 100,
        gap: 10,
      );

      expect(result.columns, 2);
      expect(result.rows, 2);
      // 宽 = 100*2 + 10
      expect(result.width, 210);
      expect(result.height, 210);
    });

    test('5 张图、2 列 → 3 行（最后一格留空）', () {
      final result = ImageToolCollage.grid(
        images: List.generate(5, (i) => _solid(50, 50, i * 20, 0, 0)),
        columns: 2,
        cellSize: 100,
        gap: 0,
      );

      expect(result.rows, 3);
      expect(result.width, 200);
      expect(result.height, 300);
    });

    test('单张图 → 1x1', () {
      final result = ImageToolCollage.grid(
        images: [_solid(50, 50, 1, 2, 3)],
        columns: 3,
      );
      expect(result.columns, 1, reason: '列数不能超过图片数');
      expect(result.rows, 1);
    });

    test('间隙为 0 时尺寸等于格子数乘以边长', () {
      final result = ImageToolCollage.grid(
        images: List.generate(3, (_) => _solid(40, 40, 0, 0, 0)),
        columns: 3,
        cellSize: 100,
        gap: 0,
      );
      expect(result.width, 300);
      expect(result.height, 100);
    });
  });

  group('不拉伸（等比留边）', () {
    test('超宽图（16:9）放进方格后左右留边、自身比例不变', () {
      // 400x225 是 16:9；放进 100x100 的格子后应该是 100x56（不是 100x100）。
      final wide = _solid(400, 225, 255, 0, 0);
      final result = ImageToolCollage.grid(
        images: [wide],
        columns: 1,
        cellSize: 200,
        gap: 0,
        background: img.ColorRgb8(0, 0, 255), // 蓝底便于识别留边
      );

      // 找出红色像素的包围盒，验证比例。
      var minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
      for (var y = 0; y < result.height; y++) {
        for (var x = 0; x < result.width; x++) {
          final p = result.image.getPixel(x, y);
          if (p.r > 200 && p.g < 60 && p.b < 60) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      final w = maxX - minX + 1;
      final h = maxY - minY + 1;
      expect(w, 200, reason: '宽应占满格子');
      expect(h, 113, reason: '400:225 = 200:112.5 → 约 113，绝不该是 200');
      expect(
        (w / h - 400 / 225).abs(),
        lessThan(0.05),
        reason: '宽高比必须保持 —— 硬拉成 200x200 就是"人脸变胖"的那个 bug',
      );
    });

    test('小图不放大（放大只会糊）', () {
      final tiny = _solid(20, 10, 255, 0, 0);
      final result = ImageToolCollage.grid(
        images: [tiny],
        columns: 1,
        cellSize: 300,
        gap: 0,
        background: img.ColorRgb8(0, 0, 255),
      );

      var redPixels = 0;
      for (var y = 0; y < result.height; y++) {
        for (var x = 0; x < result.width; x++) {
          final p = result.image.getPixel(x, y);
          if (p.r > 200 && p.g < 60 && p.b < 60) redPixels++;
        }
      }
      // 20x10 原图应保持 20x10 = 200 个红像素，而不是被放大到 300x300。
      expect(redPixels, 200, reason: '小图不该被放大填满格子');
    });

    test('竖图（100x400）放进方格：高度满格、左右留边', () {
      // 等比缩放：scale = min(200/100, 200/400) = 0.5 → 50x200。
      // 所以**左右**留边（75px），上下不留边 —— 竖图本来就是高的。
      final tall = _solid(100, 400, 255, 0, 0);
      final result = ImageToolCollage.grid(
        images: [tall],
        columns: 1,
        cellSize: 200,
        gap: 0,
        background: img.ColorRgb8(0, 0, 255),
      );

      var minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
      for (var y = 0; y < result.height; y++) {
        for (var x = 0; x < result.width; x++) {
          final p = result.image.getPixel(x, y);
          if (p.r > 200 && p.g < 60 && p.b < 60) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      expect(maxY - minY + 1, 200, reason: '高应占满格子');
      expect(maxX - minX + 1, 50, reason: '宽按比例 = 200 * 100/400 = 50');
      expect(minX, greaterThan(0), reason: '竖图应左右留边');
      expect(
        (maxX - minX + 1) / (maxY - minY + 1),
        closeTo(100 / 400, 0.02),
        reason: '宽高比必须保持',
      );
    });
  });

  group('列数推荐', () {
    test('按张数给出合理列数', () {
      expect(ImageToolCollage.suggestColumns(1), 1);
      expect(ImageToolCollage.suggestColumns(2), 2);
      expect(ImageToolCollage.suggestColumns(4), 2);
      expect(ImageToolCollage.suggestColumns(6), 3);
      expect(ImageToolCollage.suggestColumns(9), 3);
      expect(ImageToolCollage.suggestColumns(12), 4);
    });
  });

  group('输入校验', () {
    test('没有图片时报错', () {
      expect(
        () => ImageToolCollage.grid(images: const [], columns: 2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('列数 < 1 报错', () {
      expect(
        () => ImageToolCollage.grid(
          images: [_solid(10, 10, 0, 0, 0)],
          columns: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('编码', () {
    test('拼好的图能编成 JPEG', () {
      final result = ImageToolCollage.grid(
        images: [_solid(50, 50, 10, 20, 30)],
        columns: 1,
      );
      final bytes = ImageToolCollage.encode(result.image);
      expect(bytes, isNotEmpty);
      expect(img.decodeJpg(bytes), isNotNull);
    });
  });
}
