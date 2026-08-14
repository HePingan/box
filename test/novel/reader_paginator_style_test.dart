import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_paginator.dart';

/// 一段足够长的中文正文，保证会切出多页
final _content = '''
这是一段用于验证分页测量参数的正文内容。分页器必须使用与渲染层完全一致的
TextStyle，否则测量出的每页字数会偏多，实际排版时页底文字会被裁掉。
为了让二分查找产生多页结果，这里需要足够长的内容，因此重复描述若干次。
分页测量涉及字号、行高、字间距与字体族四个参数，任意一项与渲染不一致都会出问题。
''' * 12;

ReaderPaginationRequest _request({
  double letterSpacing = 0.6,
  String? fontFamily,
}) {
  return ReaderPaginationRequest(
    bookId: 'style-test',
    chapterIndex: 0,
    content: _content,
    fitWidth: 320,
    firstPageHeight: 420,
    normalPageHeight: 480,
    fontSize: 18,
    lineHeight: 1.8,
    letterSpacing: letterSpacing,
    fontFamily: fontFamily,
  );
}

void main() {
  setUp(ReaderPaginator.clearCache);

  test('字间距变大时每页容纳的字数变少（测量参数真实生效）', () {
    final tight = ReaderPaginator.paginate(_request(letterSpacing: 0.6));
    final loose = ReaderPaginator.paginate(_request(letterSpacing: 1.6));

    expect(tight.length, greaterThan(1), reason: '正文应被切成多页');
    expect(
      loose.first.length,
      lessThan(tight.first.length),
      reason: '字间距增大后首页应装下更少的字符',
    );
    expect(
      loose.length,
      greaterThanOrEqualTo(tight.length),
      reason: '字间距增大后总页数不应减少',
    );
  });

  test('字间距不同不会命中同一份分页缓存', () {
    final tight = ReaderPaginator.paginate(_request(letterSpacing: 0.6));
    final loose = ReaderPaginator.paginate(_request(letterSpacing: 1.6));
    // 再取一次紧排，确认缓存返回的仍是紧排结果而非被松排覆盖
    final tightAgain = ReaderPaginator.paginate(_request(letterSpacing: 0.6));

    expect(tightAgain.first, tight.first);
    expect(tightAgain.first, isNot(loose.first));
  });

  test('字体族参数进入分页请求且分页仍然无损', () {
    // 注意：flutter_test 环境下所有 fontFamily 都回落到同一测试字体，
    // 字形宽度不会变化，因此这里无法断言"换字体后切页结果不同"。
    // 能验证的是：字体族被携带进请求、传给测量 TextStyle 后分页依然正确无损。
    final request = _request(fontFamily: 'monospace');
    expect(request.fontFamily, 'monospace');

    final pages = ReaderPaginator.paginate(request);
    expect(pages.length, greaterThan(1));
    expect(
      pages.join().replaceAll('\n', ''),
      _content.replaceAll('\n', ''),
    );
  });

  test('分页结果拼接后与原文一致（不丢字）', () {
    final pages = ReaderPaginator.paginate(_request(letterSpacing: 1.0));
    final joined = pages.join();
    final normalizedSource = _content.replaceAll('\n', '');

    expect(joined.replaceAll('\n', ''), normalizedSource);
  });

  test('增量分页与全量分页在相同样式下结果一致', () {
    final full = ReaderPaginator.paginate(_request(letterSpacing: 1.2));

    ReaderPaginator.clearCache();
    final incremental = ReaderPaginator.paginateIncremental(
      _request(letterSpacing: 1.2),
      chunkSize: 3,
    );
    final pages = <String>[...incremental.firstChunk];
    while (!incremental.remaining.isDone) {
      pages.addAll(incremental.remaining.nextChunk());
    }

    expect(pages, full);
  });

  test('textDirection 默认为 ltr', () {
    expect(_request().textDirection, TextDirection.ltr);
  });
}
