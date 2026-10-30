import 'package:box/features/extensions/plugins/wallpaper/domain/wallpaper_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// 壁纸清单的解析口径：清单是我自己生成的，但 App 得能扛住它被改坏/被截断。
void main() {
  group('joinWallpaperUrl', () {
    test('相对文件名拼到 baseUrl 上（末尾斜杠有无都对）', () {
      expect(
        joinWallpaperUrl('https://a.com/w/', 'wp-01.jpg'),
        'https://a.com/w/wp-01.jpg',
      );
      expect(
        joinWallpaperUrl('https://a.com/w', 'wp-01.jpg'),
        'https://a.com/w/wp-01.jpg',
      );
    });

    test('完整 URL 原样保留（便于以后换 CDN 不改 App）', () {
      expect(
        joinWallpaperUrl('https://a.com/w/', 'https://cdn.b.com/x.jpg'),
        'https://cdn.b.com/x.jpg',
      );
    });

    test('空文件名返回空串（调用方据此不渲染图片）', () {
      expect(joinWallpaperUrl('https://a.com/w/', '  '), isEmpty);
    });
  });

  group('parseWallpaperManifest', () {
    const good = '''
{"version":1,"baseUrl":"https://a.com/w/","source":"测试源",
 "items":[
   {"id":"wp-01","title":"金发","file":"wp-01.jpg","thumb":"wp-01-t.jpg",
    "width":1896,"height":2560,"bytes":682000,"tags":["金发","柔和"]},
   {"id":"wp-02","title":"蓝调","file":"wp-02.jpg","thumb":"wp-02-t.jpg",
    "width":1294,"height":2300,"bytes":476000,"tags":["奇幻","柔和"]}
 ]}''';

    test('正常清单：条目、来源、标签都解析出来', () {
      final m = parseWallpaperManifest(good);
      expect(m.items, hasLength(2));
      expect(m.source, '测试源');
      expect(m.items.first.resolutionText, '1896 × 2560');
      expect(m.allTags, ['金发', '柔和', '奇幻'], reason: '去重且保持出现顺序');
    });

    test('按标签筛选；空标签 = 全部', () {
      final m = parseWallpaperManifest(good);
      expect(m.filtered('').length, 2);
      expect(m.filtered('柔和').map((e) => e.id), ['wp-01', 'wp-02']);
      expect(m.filtered('奇幻').map((e) => e.id), ['wp-02']);
      expect(m.filtered('不存在'), isEmpty);
    });

    test('坏条目跳过，不连累整张清单', () {
      final m = parseWallpaperManifest(
        '{"baseUrl":"https://a.com/","items":[{"title":"没有 file"},'
        '{"id":"ok","file":"ok.jpg"}]}',
      );
      expect(m.items.single.id, 'ok');
    });

    test('thumb 缺省时回落到 file', () {
      final m = parseWallpaperManifest('{"items":[{"file":"a.jpg"}]}');
      expect(m.items.single.thumb, 'a.jpg');
    });

    test('清单损坏时抛出带人话的异常（不是崩溃）', () {
      for (final bad in ['', '   ', 'not json', '[]', '{"items":5}']) {
        expect(
          () => parseWallpaperManifest(bad),
          throwsA(isA<WallpaperManifestException>()),
          reason: bad,
        );
      }
    });
  });

  group('WallpaperItem', () {
    test('未知尺寸不显示「0 × 0」', () {
      const item = WallpaperItem(id: 'x', title: 'x', file: 'x.jpg', thumb: 'x.jpg');
      expect(item.resolutionText, isEmpty);
    });

    test('fullUrl/thumbUrl 走同一个拼接规则', () {
      const item = WallpaperItem(
        id: 'x',
        title: 'x',
        file: 'x.jpg',
        thumb: 'x-t.jpg',
      );
      expect(item.fullUrl('https://a.com/w'), 'https://a.com/w/x.jpg');
      expect(item.thumbUrl('https://a.com/w'), 'https://a.com/w/x-t.jpg');
    });
  });
}
