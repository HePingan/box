import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_paginator.dart';

final _content = List.generate(
  60,
  (i) => '第${i + 1}段：' + '这是一段用于验证增量分页不会丢失尾部内容的中文正文。' * 3,
).join('\n\n');

ReaderPaginationRequest _request() => ReaderPaginationRequest(
      bookId: 'inc-book',
      chapterIndex: 0,
      content: _content,
      fitWidth: 360,
      firstPageHeight: 520,
      normalPageHeight: 600,
      fontSize: 18,
      lineHeight: 1.8,
      letterSpacing: 0.6,
      textDirection: TextDirection.ltr,
    );

/// 模拟 reader_page._paginateRemaining 的消费方式：
/// 每 [flushEvery] 个 chunk 刷新一次 UI，循环结束后做一次收尾刷新。
List<String> _drainLikeReaderPage(
  IncrementalPaginationResult result, {
  required int flushEvery,
}) {
  final accumulated = <String>[...result.firstChunk];
  var visible = <String>[...result.firstChunk];
  var chunkCount = 0;

  final it = result.remaining;
  while (!it.isDone) {
    final chunk = it.nextChunk();
    if (chunk.isEmpty) break;
    accumulated.addAll(chunk);
    chunkCount++;
    if (chunkCount >= flushEvery) {
      visible = List<String>.from(accumulated);
      chunkCount = 0;
    }
  }

  // 收尾刷新（这一步就是修复的内容；缺了它就会丢尾页）
  visible = List<String>.from(accumulated);
  return visible;
}

void main() {
  setUp(ReaderPaginator.clearCache);

  test('增量分页拼回的正文与全量分页完全一致', () {
    final full = ReaderPaginator.paginate(_request());
    ReaderPaginator.clearCache();
    final incremental = _drainLikeReaderPage(
      ReaderPaginator.paginateIncremental(_request(), chunkSize: 5),
      flushEvery: 2,
    );

    expect(incremental.join(), full.join());
    expect(incremental.length, full.length);
  });

  test('无论 chunk 数是否为刷新步长的整数倍都不丢页', () {
    final full = ReaderPaginator.paginate(_request());

    for (final chunkSize in [1, 2, 3, 5, 7]) {
      for (final flushEvery in [1, 2, 3]) {
        ReaderPaginator.clearCache();
        final pages = _drainLikeReaderPage(
          ReaderPaginator.paginateIncremental(_request(), chunkSize: chunkSize),
          flushEvery: flushEvery,
        );
        expect(
          pages.join(),
          full.join(),
          reason: 'chunkSize=$chunkSize flushEvery=$flushEvery 丢内容了',
        );
      }
    }
  });

  test('分页结果覆盖原文全部字符，无重复无丢失', () {
    final pages = _drainLikeReaderPage(
      ReaderPaginator.paginateIncremental(_request(), chunkSize: 5),
      flushEvery: 2,
    );
    expect(pages.join(), _content);
  });

  test('最后一页非空（回归：尾部 chunk 曾被丢弃）', () {
    final pages = _drainLikeReaderPage(
      ReaderPaginator.paginateIncremental(_request(), chunkSize: 5),
      flushEvery: 2,
    );
    expect(pages.length, greaterThan(1));
    expect(pages.last.trim(), isNotEmpty);
    expect(_content.endsWith(pages.last), isTrue);
  });
}
