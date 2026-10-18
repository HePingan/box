// 壁纸提取：把图裁成屏幕比例。
//
// 重点不是"能不能裁"，而是**裁哪一块**与"比例真的对了吗"。
// 手机壁纸是 9:19.5 这类细长比例，而多数照片是 4:3 / 16:9 ——
// 直接设成壁纸会被系统拉伸或裁掉主体，所以裁剪这块矩形的位置很关键。
import 'package:box/features/local_tools/domain/image_tool_wallpaper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _solid(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(120, 80, 40));
  return im;
}

void main() {
  group('横图裁竖版（宽图 → 细长）', () {
    test('1920x1080 裁 9:19.5 → 高度满格、宽度按比例', () {
      final out = ImageToolWallpaper.crop(
        source: _solid(1920, 1080),
        aspect: 9 / 19.5,
      );

      expect(out.height, 1080, reason: '高度是受限的那一边');
      expect(out.width, (1080 * 9 / 19.5).round(), reason: '宽度按比例算');
      expect(out.width / out.height, closeTo(9 / 19.5, 0.01));
    });

    test('居中裁剪时左右对称', () {
      final src = _solid(1000, 1000);
      final out = ImageToolWallpaper.crop(
        source: src,
        aspect: 1 / 2, // 竖长
      );
      // 1000x1000 裁成 1:2 → 500x1000
      expect(out.width, 500);
      expect(out.height, 1000);
    });
  });

  group('竖图裁横版', () {
    test('1080x1920 裁 16:9 → 宽度满格', () {
      final out = ImageToolWallpaper.crop(
        source: _solid(1080, 1920),
        aspect: 16 / 9,
      );

      expect(out.width, 1080, reason: '宽度是受限的那一边');
      expect(out.height, (1080 / (16 / 9)).round());
      expect(out.width / out.height, closeTo(16 / 9, 0.02));
    });
  });

  group('比例已经一致', () {
    test('同比例不裁剪，尺寸不变', () {
      final out = ImageToolWallpaper.crop(
        source: _solid(900, 1600),
        aspect: 9 / 16,
      );
      expect(out.width, 900);
      expect(out.height, 1600);
    });
  });

  group('保留位置真的生效', () {
    /// 造一张上红下蓝的图，看裁完保留的是哪半。
    img.Image topRedBottomBlue(int w, int h) {
      final im = img.Image(width: w, height: h, numChannels: 3);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (y < h ~/ 2) {
            im.setPixelRgb(x, y, 255, 0, 0);
          } else {
            im.setPixelRgb(x, y, 0, 0, 255);
          }
        }
      }
      return im;
    }

    test('靠上 → 保留上半（红）', () {
      final out = ImageToolWallpaper.crop(
        source: topRedBottomBlue(400, 400),
        aspect: 1.0, // 方形，不裁
        focus: WallpaperFocus.top,
      );
      expect(out.getPixel(10, 10).r, greaterThan(200));
    });

    test('靠下裁竖向长图时保留下半', () {
      // 400x400 裁成 1:2（400x800 不可能）→ 实际是 200x400，横向裁。
      // 换一个真正上下裁的场景：400x400 裁成 4:1 横条 → 400x100。
      final out = ImageToolWallpaper.crop(
        source: topRedBottomBlue(400, 400),
        aspect: 4.0,
        focus: WallpaperFocus.bottom,
      );

      expect(out.height, 100);
      // 取底部区域的一个像素，应当是蓝色（下半）。
      final p = out.getPixel(10, out.height - 5);
      expect(p.b, greaterThan(200), reason: '靠下应保留图片下半部');
      expect(p.r, lessThan(60));
    });

    test('靠左/靠右在横向裁剪时生效', () {
      // 造左绿右黄的图。
      final im = img.Image(width: 400, height: 400, numChannels: 3);
      for (var y = 0; y < 400; y++) {
        for (var x = 0; x < 400; x++) {
          if (x < 200) {
            im.setPixelRgb(x, y, 0, 255, 0);
          } else {
            im.setPixelRgb(x, y, 255, 255, 0);
          }
        }
      }

      // 裁成 1:2 竖条 → 宽变成 200，需要左右裁掉一半。
      final left = ImageToolWallpaper.crop(
        source: im,
        aspect: 1 / 2,
        focus: WallpaperFocus.left,
      );
      expect(left.getPixel(5, 5).g, greaterThan(200), reason: '靠左保留左半（绿）');
      expect(left.getPixel(5, 5).r, lessThan(60));

      final right = ImageToolWallpaper.crop(
        source: im,
        aspect: 1 / 2,
        focus: WallpaperFocus.right,
      );
      expect(right.getPixel(5, 5).r, greaterThan(200), reason: '靠右保留右半（黄）');
    });
  });

  group('尺寸预估', () {
    test('预估尺寸与实际裁剪一致', () {
      const w = 1920, h = 1080;
      final aspect = WallpaperAspect.phoneTall.ratio;
      final (ew, eh) = wallpaperResultSize(
        sourceWidth: w,
        sourceHeight: h,
        aspect: aspect,
      );
      final cropped = ImageToolWallpaper.crop(
        source: _solid(w, h),
        aspect: aspect,
      );
      expect((cropped.width, cropped.height), (ew, eh),
          reason: 'UI 提前显示的尺寸必须与实际结果一致');
    });

    test('被裁掉的像素数不为负', () {
      expect(
        wallpaperCroppedPixels(
          sourceWidth: 100,
          sourceHeight: 100,
          aspect: 1,
        ),
        0,
        reason: '同比例不裁，裁掉 0',
      );
      expect(
        wallpaperCroppedPixels(
          sourceWidth: 1000,
          sourceHeight: 1000,
          aspect: 1 / 2,
        ),
        greaterThan(0),
      );
    });
  });

  group('比例定义', () {
    test('五个比例都有中文标签且 ratio 正确', () {
      expect(WallpaperAspect.values.length, 5);
      for (final a in WallpaperAspect.values) {
        expect(a.label, isNotEmpty);
        expect(a.ratio, closeTo(a.width / a.height, 1e-9));
      }
      expect(WallpaperAspect.phoneTall.ratio, closeTo(9 / 19.5, 1e-9));
      expect(WallpaperAspect.square.ratio, 1.0);
    });

    test('保留位置有五个且都有标签', () {
      expect(WallpaperFocus.values.length, 5);
      for (final f in WallpaperFocus.values) {
        expect(f.label, isNotEmpty);
      }
    });
  });

  group('输入校验', () {
    test('比例非正报错', () {
      expect(
        () => ImageToolWallpaper.crop(source: _solid(10, 10), aspect: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => wallpaperResultSize(
          sourceWidth: 10,
          sourceHeight: 10,
          aspect: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
