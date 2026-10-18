// 文字水印：重点锁住"中文画不出来"这个真实限制。
//
// image 包只内置 arial14/24/48 三款位图字体，字形表里没有汉字。
// 实测 drawString("中文") 的深色像素数为 **0** —— 不是难看，是一个像素都不画。
// 所以 textRenders() 必须在用户按下按钮**之前**就能告诉他，而不是让他对着
// 一张没有任何水印的图发愣。
import 'package:box/features/local_tools/domain/image_tool_watermark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _blank({int w = 400, int h = 300}) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
  return im;
}

/// 数一下图里有多少不透明像素（用来证明"字真的画上去了"）。
int _opaqueCount(img.Image image) {
  var n = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a > 0) n++;
    }
  }
  return n;
}

void main() {
  group('textRenders：能不能画', () {
    test('纯 ASCII 可以', () {
      expect(ImageToolWatermark.textRenders('SAMPLE'), isTrue);
      expect(ImageToolWatermark.textRenders('abc 123 !@#'), isTrue);
      expect(ImageToolWatermark.textRenders(''), isTrue, reason: '空串没有不可绘字符');
    });

    test('中文不可以（位图字体没有汉字字形）', () {
      expect(ImageToolWatermark.textRenders('中文'), isFalse);
      expect(ImageToolWatermark.textRenders('Box 极客匣'), isFalse);
    });

    test('全角标点/emoji 也不可以', () {
      expect(ImageToolWatermark.textRenders('，。'), isFalse);
      expect(ImageToolWatermark.textRenders('😀'), isFalse);
    });
  });

  group('apply：真的画上去了', () {
    test('ASCII 水印会在图上产生不透明像素', () {
      final out = ImageToolWatermark.apply(
        image: _blank(),
        text: 'HELLO',
        anchor: WatermarkAnchor.center,
        opacity: 1.0,
        scale: 2,
      );

      expect(
        _opaqueCount(out),
        greaterThan(0),
        reason: '画完一个像素都没有 = 用户拿到一张没有水印的图',
      );
    });

    test('opacity 越低，不透明像素越少', () {
      final full = ImageToolWatermark.apply(
        image: _blank(),
        text: 'HELLO',
        anchor: WatermarkAnchor.center,
        opacity: 1.0,
        scale: 2,
      );
      final faint = ImageToolWatermark.apply(
        image: _blank(),
        text: 'HELLO',
        anchor: WatermarkAnchor.center,
        opacity: 0.15,
        scale: 2,
      );

      // alpha 很低时，仍有像素但 alpha 值更小；用累计 alpha 比较更准。
      int totalAlpha(img.Image im) {
        var t = 0;
        for (var y = 0; y < im.height; y++) {
          for (var x = 0; x < im.width; x++) {
            t += im.getPixel(x, y).a.toInt();
          }
        }
        return t;
      }

      expect(totalAlpha(faint), lessThan(totalAlpha(full)),
          reason: '不透明度要真的生效');
    });

    test('中文水印会明确报错，而不是静默画一张空图', () {
      expect(
        () => ImageToolWatermark.apply(
          image: _blank(),
          text: '中文水印',
          anchor: WatermarkAnchor.center,
          opacity: 1.0,
          scale: 2,
        ),
        throwsA(isA<ArgumentError>()),
        reason: '静默返回原图 = 用户以为加了水印，实际什么也没有',
      );
    });

    test('空文字报错', () {
      expect(
        () => ImageToolWatermark.apply(
          image: _blank(),
          text: '   ',
          anchor: WatermarkAnchor.center,
          opacity: 1.0,
          scale: 2,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('不改原图（返回新图）', () {
      final original = _blank();
      final before = _opaqueCount(original);
      ImageToolWatermark.apply(
        image: original,
        text: 'HELLO',
        anchor: WatermarkAnchor.center,
        opacity: 1.0,
        scale: 2,
      );
      expect(_opaqueCount(original), before, reason: '原图必须保持不动');
    });
  });

  group('九宫格位置', () {
    test('九个位置都在画布内', () {
      const w = 400, h = 300, tw = 100, th = 20;
      for (final a in WatermarkAnchor.values) {
        final (x, y) = a.compute(
          canvasWidth: w,
          canvasHeight: h,
          textWidth: tw,
          textHeight: th,
        );
        expect(x, greaterThanOrEqualTo(0), reason: '${a.label} 越界');
        expect(y, greaterThanOrEqualTo(0), reason: '${a.label} 越界');
        expect(x + tw, lessThanOrEqualTo(w), reason: '${a.label} 右侧越界');
        expect(y + th, lessThanOrEqualTo(h), reason: '${a.label} 下方越界');
      }
    });

    test('左上在左上角、右下在右下角', () {
      final (lx, ly) = WatermarkAnchor.topLeft.compute(
        canvasWidth: 400,
        canvasHeight: 300,
        textWidth: 100,
        textHeight: 20,
        margin: 10,
      );
      expect((lx, ly), (10, 10));

      final (rx, ry) = WatermarkAnchor.bottomRight.compute(
        canvasWidth: 400,
        canvasHeight: 300,
        textWidth: 100,
        textHeight: 20,
        margin: 10,
      );
      expect((rx, ry), (400 - 100 - 10, 300 - 20 - 10));
    });

    test('文字比画布还宽时不出现负坐标', () {
      final (x, _) = WatermarkAnchor.bottomRight.compute(
        canvasWidth: 50,
        canvasHeight: 50,
        textWidth: 200,
        textHeight: 20,
      );
      expect(x, greaterThanOrEqualTo(0), reason: '负坐标会让 drawString 直接画到画布外');
    });

    test('九个位置的中文标签都非空', () {
      for (final a in WatermarkAnchor.values) {
        expect(a.label, isNotEmpty);
      }
      expect(WatermarkAnchor.values.length, 9);
    });
  });
}
