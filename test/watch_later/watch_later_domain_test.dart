import 'package:box/features/extensions/plugins/watch_later/domain/watch_later_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// 稍后看清单的领域逻辑：地址校验、标题推导、JSON 往返、去重与排序、payload 解析。
/// 清单文件在远程存储里可能被别的工具改坏，所以「坏数据不抛异常」是硬要求。
void main() {
  group('isPlayableWatchLaterUrl', () {
    test('http/https 放行', () {
      expect(isPlayableWatchLaterUrl('https://a.com/v/1'), isTrue);
      expect(isPlayableWatchLaterUrl('http://a.com/v/1.m3u8'), isTrue);
    });

    test('其它协议一律拒绝（清单可能来自外部文件或插件 payload）', () {
      for (final bad in [
        'file:///sdcard/a.mp4',
        'javascript:alert(1)',
        'content://media/1',
        'ftp://a.com/a.mp4',
        '/local/path.mp4',
        'https://',
        'http://',
        '',
      ]) {
        expect(isPlayableWatchLaterUrl(bad), isFalse, reason: bad);
      }
    });
  });

  group('watchLaterTitleFromUrl', () {
    test('取最后一段路径，去掉播放后缀并把分隔符还原成空格', () {
      expect(
        watchLaterTitleFromUrl('https://v.qq.com/x/cover/abc/My_Show_S01E02.m3u8'),
        'My Show S01E02',
      );
      expect(
        watchLaterTitleFromUrl('https://a.com/movie/流浪地球.mp4'),
        '流浪地球',
      );
    });

    test('没有可用路径时用主机名', () {
      expect(watchLaterTitleFromUrl('https://example.com/'), 'example.com');
      expect(watchLaterTitleFromUrl('https://example.com'), 'example.com');
    });

    test('彻底解析不出来给「未命名」，不返回空串', () {
      expect(watchLaterTitleFromUrl('not a url'), isNotEmpty);
    });
  });

  group('清单 JSON', () {
    final now = DateTime(2026, 10, 30, 22, 0).millisecondsSinceEpoch;

    WatchLaterItem item(String url, {String title = '', int addedAt = 0}) =>
        WatchLaterItem(
          url: url,
          title: title,
          addedAtMs: addedAt == 0 ? now : addedAt,
        );

    test('编码 → 解析往返一致', () {
      final items = [
        item('https://a.com/1', title: '一号'),
        item('https://a.com/2', title: '二号', addedAt: now - 60000),
      ];
      final parsed = parseWatchLaterDoc(encodeWatchLaterDoc(items));
      expect(parsed.map((e) => e.url), ['https://a.com/1', 'https://a.com/2']);
      expect(parsed.first.title, '一号');
      expect(parsed.first.addedAtMs, now);
    });

    test('空/坏数据返回空清单，不抛异常', () {
      for (final raw in [null, '', '   ', 'not json', '[]', '{"items": 5}']) {
        expect(parseWatchLaterDoc(raw), isEmpty, reason: '$raw');
      }
    });

    test('也认裸数组（别人手写的清单）', () {
      final parsed = parseWatchLaterDoc(
        '[{"url":"https://a.com/x","title":"手写"}]',
      );
      expect(parsed.single.title, '手写');
    });

    test('非法地址条目被跳过，其它条目照常保留', () {
      final parsed = parseWatchLaterDoc(
        '{"items":[{"url":"file:///etc/passwd"},'
        '{"url":"https://a.com/ok","title":"留下"}]}',
      );
      expect(parsed.single.url, 'https://a.com/ok');
    });

    test('没有标题时从地址推导，不留空标题', () {
      final parsed = parseWatchLaterDoc(
        '{"items":[{"url":"https://a.com/movie/流浪地球.mp4"}]}',
      );
      expect(parsed.single.title, '流浪地球');
    });

    test('同一地址重复出现只留第一条', () {
      final parsed = parseWatchLaterDoc(
        '{"items":[{"url":"https://a.com/1","title":"先"},'
        '{"url":"https://a.com/1","title":"后"}]}',
      );
      expect(parsed, hasLength(1));
      expect(parsed.single.title, '先');
    });

    test('按添加时间倒序', () {
      final parsed = parseWatchLaterDoc(
        encodeWatchLaterDoc([
          item('https://a.com/old', title: '老', addedAt: now - 999999),
          item('https://a.com/new', title: '新', addedAt: now),
        ]),
      );
      expect(parsed.first.url, 'https://a.com/new');
    });
  });

  group('增删', () {
    final now = DateTime(2026, 10, 30, 22, 0).millisecondsSinceEpoch;

    test('新增排在最前', () {
      final list = addWatchLater(
        const [],
        WatchLaterItem(url: 'https://a.com/1', title: '一', addedAtMs: now),
      );
      expect(list.single.title, '一');
    });

    test('同一地址再加一次：更新标题并提到最前，不出现两条', () {
      final first = addWatchLater(
        const [],
        WatchLaterItem(url: 'https://a.com/1', title: '旧标题', addedAtMs: now - 1000),
      );
      final second = addWatchLater(
        first,
        WatchLaterItem(url: 'https://a.com/1', title: '新标题', addedAtMs: now),
      );
      expect(second, hasLength(1));
      expect(second.single.title, '新标题');
    });

    test('删除按地址移除', () {
      final list = [
        WatchLaterItem(url: 'https://a.com/1', title: '一', addedAtMs: now),
        WatchLaterItem(url: 'https://a.com/2', title: '二', addedAtMs: now - 1),
      ];
      final after = removeWatchLater(list, 'https://a.com/1');
      expect(after.map((e) => e.url), ['https://a.com/2']);
      expect(list, hasLength(2), reason: '不改入参');
    });
  });

  group('parseWatchLaterPayload', () {
    test('纯 URL：整串当地址', () {
      final p = parseWatchLaterPayload('  https://a.com/v/9  ');
      expect(p?.url, 'https://a.com/v/9');
      expect(p?.title, '');
    });

    test('JSON：url + title（url/link/href 都认）', () {
      expect(parseWatchLaterPayload('{"url":"https://a.com/1","title":"片子"}')?.title,
          '片子');
      expect(
        parseWatchLaterPayload('{"link":"https://a.com/2"}')?.url,
        'https://a.com/2',
      );
      expect(
        parseWatchLaterPayload('{"href":"https://a.com/3"}')?.url,
        'https://a.com/3',
      );
    });

    test('空/坏 JSON/非法地址 → null（当没给参数）', () {
      for (final raw in [null, '', '  ', '{"url":', 'file:///a.mp4', '[1,2]']) {
        expect(parseWatchLaterPayload(raw), isNull, reason: '$raw');
      }
    });
  });

  group('watchLaterHostOf', () {
    test('取主机名，解析不出就原样返回', () {
      expect(watchLaterHostOf('https://v.qq.com/x/1'), 'v.qq.com');
      expect(watchLaterHostOf('garbage'), 'garbage');
    });
  });

  test('清单路径固定（用户能在远程存储里找到）', () {
    expect(kWatchLaterPath, 'box-watchlist/watch-later.json');
  });
}
