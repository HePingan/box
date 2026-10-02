// 「追更」记录本：记住目录、只比对两头、取不到就当没消息、限流。
//
// **不联网**：取数注入假的取数器，HTML 用手写的（形状照真站点：`li.comic-chapter-item` +
// `a[href=...][title=...]`，最新一话在最前 —— 2026-10-02 从站点实测来的）。
library;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_fetcher.dart';
import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/comic_update_watch.dart';
import 'package:box/features/comic/domain/sources/seed_comic_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假取数器：按 URL 返回预置 HTML，并记账"取过几次"。
class _FakeFetcher implements ComicFetcher {
  _FakeFetcher(this.htmlOf);

  /// url → HTML；抛异常 = 模拟取不到（站点抽风 / 超时）。
  final String Function(String url) htmlOf;
  final List<String> requested = <String>[];

  @override
  Map<String, String> get headers => const <String, String>{};

  @override
  Map<String, String> headersFor(String url) => const <String, String>{};

  @override
  Future<String> getText(String url) async {
    requested.add(url);
    return htmlOf(url);
  }

  @override
  Future<String> postForm(String url, Map<String, String> form) async =>
      throw UnimplementedError();

  @override
  String wrap(String url) => url;

  @override
  void close() {}
}

/// 站点目录 HTML：**最新一话在最前**（与真站点一致）。
String _tocHtml(List<String> latestFirst) {
  final sb = StringBuffer('<html><body><ul id="js_chapters">');
  for (var i = 0; i < latestFirst.length; i++) {
    final t = latestFirst[i];
    sb.write(
      '<li class="comic-chapter-item" data-index="${i + 1}">'
      '<a class="comic-chapter-link" href="/chapter/96/${1000 + i}.html" '
      'title="$t">$t</a></li>',
    );
  }
  sb.write('</ul></body></html>');
  return sb.toString();
}

void main() {
  const bookUrl = 'https://yemancomic.com/book/96/';

  late ComicSource source;
  late CacheStore cache;

  setUp(() {
    source = ComicSource.tryParse(kSeedComicSourceYemanJson)!;
    cache = CacheStore.inMemory('update_watch_${DateTime.now().microsecondsSinceEpoch}');
  });

  ComicUpdateWatch watch(_FakeFetcher f) => ComicUpdateWatch(
    cacheStore: cache,
    source: source,
    fetcher: f,
  );

  test('第一次查只是"记下现在的目录"，不报新话（不然一进收藏全是红点）', () async {
    final f = _FakeFetcher((_) => _tocHtml(['第3话', '第2话', '第1话']));
    final w = watch(f);

    final rec = await w.check(bookUrl);

    expect(rec, isNotNull);
    expect(rec!.chapterCount, 3);
    expect(rec.newCount, 0);
    expect(rec.hasNew, isFalse);
    expect(f.requested, [bookUrl]);
  });

  test('目录两头都没动：不报新话', () async {
    final f = _FakeFetcher((_) => _tocHtml(['第3话', '第2话', '第1话']));
    final w = watch(f);
    await w.check(bookUrl);

    final rec = await w.check(bookUrl, force: true);

    expect(rec!.newCount, 0);
  });

  test('更新了（最新在前，顶上多一话）：报 1 话', () async {
    var html = _tocHtml(['第3话', '第2话', '第1话']);
    final f = _FakeFetcher((_) => html);
    final w = watch(f);
    await w.check(bookUrl);

    html = _tocHtml(['第4话', '第3话', '第2话', '第1话']);
    final rec = await w.check(bookUrl, force: true);

    expect(rec!.newCount, 1);
    expect(rec.hasNew, isTrue);
    expect(rec.chapterCount, 4);
  });

  test('更新了 3 话就说 3 话', () async {
    var html = _tocHtml(['第3话', '第2话', '第1话']);
    final f = _FakeFetcher((_) => html);
    final w = watch(f);
    await w.check(bookUrl);

    html = _tocHtml(['第6话', '第5话', '第4话', '第3话', '第2话', '第1话']);
    expect((await w.check(bookUrl, force: true))!.newCount, 3);
  });

  test('取不到（站点抽风）：保留原来的判断，别把红点误报出来', () async {
    var broken = false;
    final f = _FakeFetcher(
      (_) => broken ? throw Exception('Connection reset') : _tocHtml(['第3话', '第2话', '第1话']),
    );
    final w = watch(f);
    await w.check(bookUrl);
    broken = true;

    final rec = await w.check(bookUrl, force: true);

    expect(rec!.newCount, 0, reason: '取不到 = 这次没消息');
    expect(rec.chapterCount, 3, reason: '旧记录还在');
  });

  test('rules 解析不出目录：也算没消息（不能把所有书都标成有新话）', () async {
    var html = _tocHtml(['第3话', '第2话', '第1话']);
    final f = _FakeFetcher((_) => html);
    final w = watch(f);
    await w.check(bookUrl);

    html = '<html><body><p>站点改版了 / WAF 挑战页</p></body></html>';
    final rec = await w.check(bookUrl, force: true);

    expect(rec!.newCount, 0);
  });

  test('限流：刚查过的书不再发请求（收藏十几本时这是必须的）', () async {
    final f = _FakeFetcher((_) => _tocHtml(['第3话', '第2话', '第1话']));
    final w = watch(f);
    await w.check(bookUrl);
    expect(f.requested.length, 1);

    await w.check(bookUrl); // 默认 6 小时限流

    expect(f.requested.length, 1, reason: '限流内的不该再取一次');
  });

  test('批量：最多查 max 本，其余留着下次', () async {
    final f = _FakeFetcher((_) => _tocHtml(['第3话', '第2话', '第1话']));
    final w = watch(f);

    final urls = [for (var i = 0; i < 5; i++) 'https://yemancomic.com/book/$i/'];
    await w.checkDue(urls, max: 2);

    expect(f.requested.length, 2);
  });

  test('点刷新（force）：跳过限流，把该查的都查一遍', () async {
    final f = _FakeFetcher((_) => _tocHtml(['第3话', '第2话', '第1话']));
    final w = watch(f);
    await w.checkDue([bookUrl], max: 3);
    expect(f.requested.length, 1);

    await w.checkDue([bookUrl], max: 3, force: true);

    expect(f.requested.length, 2);
  });

  test('seen()：用户看见了目录 → 角标清掉', () async {
    var html = _tocHtml(['第3话', '第2话', '第1话']);
    final f = _FakeFetcher((_) => html);
    final w = watch(f);
    await w.check(bookUrl);
    html = _tocHtml(['第4话', '第3话', '第2话', '第1话']);
    expect((await w.check(bookUrl, force: true))!.newCount, 1);

    // 用户点进这本书（详情页拿到目录）→ 记成"看过了"
    await w.seen(
      bookUrl: bookUrl,
      titles: ['第4话', '第3话', '第2话', '第1话'],
      urls: [
        for (var i = 0; i < 4; i++) '$bookUrl/chapter/${i + 1}',
      ],
    );

    final rec = await w.read(bookUrl);
    expect(rec!.newCount, 0, reason: '看过了就不该还挂着红点');
    expect(rec.chapterCount, 4);
  });
}
