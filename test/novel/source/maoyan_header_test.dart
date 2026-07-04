// 端到端测试：用 MaoYanNovelSource 直接测试真实 API
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/novel/core/maoyan_novel_source.dart';
import '../../../lib/novel/core/models.dart';

void main() {
  test('MaoYanNovelSource 端到端测试', () async {
    final file = File('assets/data/maoyan_book_source.json');
    final jsonStr = await file.readAsString();
    final bookSource = jsonDecode(jsonStr) as Map<String, dynamic>;

    final source = MaoYanNovelSource.fromBookSourceJson(bookSource);

    print('─── 搜索测试 ───');
    final kw = '大奉打更人';
    List<NovelBook>? books;
    try {
      books = await source.searchBooks(kw);
    } catch (e) {
      print('❌ 搜索异常: $e');
    }
    print('搜索结果: ${books?.length ?? 0} 本');
    if (books != null) {
      for (final b in books.take(3)) {
        print('  - ${b.title} (id=${b.id})');
      }
    }

    if (books != null && books.isNotEmpty) {
      final first = books.first;
      print('\n─── 详情测试: ${first.title} ───');

      try {
        final detail = await source.fetchDetail(
          bookId: first.id,
          detailUrl: first.detailUrl,
        );
        print('书名: ${detail.book.title}');
        print('作者: ${detail.book.author}');
        print('ID: ${detail.book.id}');
        print('章节数: ${detail.chapters.length}');
        if (detail.chapters.isNotEmpty) {
          print('前 5 章:');
          for (int i = 0; i < 5 && i < detail.chapters.length; i++) {
            print('  [$i] ${detail.chapters[i].title}');
          }
          // 测试第一章内容
          print('\n─── 正文测试 ───');
          try {
            final content = await source.fetchChapter(
              detail: detail,
              chapterIndex: 0,
            );
            print('标题: ${content.title}');
            final bodyPreview = content.content.length > 200
                ? '${content.content.substring(0, 200)}...'
                : content.content;
            print('正文预览: $bodyPreview');
          } catch (e) {
            print('❌ 正文获取失败: $e');
          }
        } else {
          print('⚠️ 章节列表为空！');
        }
      } catch (e) {
        print('❌ 详情异常: $e');
      }
    }

    print('\n─── 诊断完成 ───');
  });
}
