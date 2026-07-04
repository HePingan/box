// 直接用 MaoYanNovelSource 的 _request 方法测试
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

// 导入源码以供测试 — 通过函数调用间接使用 _request
import '../../../lib/novel/core/maoyan_novel_source.dart';

void main() {
  test('MaoYanNovelSource._request 直接测试', () async {
    final file = File('assets/data/maoyan_book_source.json');
    final jsonStr = await file.readAsString();
    final bookSource = jsonDecode(jsonStr) as Map<String, dynamic>;

    // 通过 fromBookSourceJson 创建源
    final source = MaoYanNovelSource.fromBookSourceJson(bookSource);

    // 模拟 searchBooks 的流程：直接使用 _request
    final kw = '大奉打更人';
    final searchPath = '/search?keyword=${Uri.encodeComponent(kw)}&page=1';
    print('搜索路径: $searchPath');

    try {
      // 使用 searchBooks 间接测试 — 它内部就是调 _request
      final books = await source.searchBooks(kw);
      print('searchBooks 返回: ${books.length} 本');
      if (books.isEmpty) {
        // 尝试直接通过 extractAuth 验证配置
        final comment = '${bookSource['bookSourceComment'] ?? ''}';
        final extracted = MaoYanNovelSource.extractAuthFromComment(comment);
        print('域名数量: ${extracted.$1.length}');
        print('AES Key 数量: ${extracted.$2.length}');

        // 检查 ruleSearch 中的 bookList
        final ruleSearch = bookSource['ruleSearch'] as Map? ?? {};
        print('ruleSearch: $ruleSearch');
        print('bookList 规则: ${ruleSearch['bookList']?.toString().substring(0, 200)}...');
        
        // 直接用 http client 验证
        final (domain, uType) = extracted.$1.first;
        final clientDevice = md5.convert(utf8.encode(extracted.$2[uType])).toString();
        final headers = {
          'User-Agent': 'okhttp/4.9.2',
          'client-device': clientDevice,
          'Authorization': extracted.$3[uType],
        };
        
        // 加上 client-* 头
        final rawHeader = bookSource['header'] as String?;
        if (rawHeader != null) {
          try {
            final hMap = jsonDecode(rawHeader) as Map;
            for (final e in hMap.entries) {
              headers['${e.key}'] = '${e.value}'.trim();
            }
          } catch (_) {}
        }
        
        print('尝试直接 http 请求...');
        final resp = await http.Client()
            .get(Uri.parse('http://api.$domain.com$searchPath'),
                 headers: headers)
            .timeout(const Duration(seconds: 15));
        print('HTTP ${resp.statusCode} (${resp.body.length} 字节)');
        final json = jsonDecode(resp.body);
        print('code: ${json['code']}, data 类型: ${json['data'].runtimeType}');
        if (json['data'] is List) {
          print('data 长度: ${(json['data'] as List).length}');
        }
      } else {
        print('第一本书: ${books.first.title} (${books.first.id})');
        
        // 测试详情
        final detail = await source.fetchDetail(
          bookId: books.first.id,
          detailUrl: books.first.detailUrl,
        );
        print('详情成功: ${detail.book.title}');
        print('章节数: ${detail.chapters.length}');
        if (detail.chapters.isNotEmpty) {
          print('第一章: ${detail.chapters.first.title}');
        }
      }
    } catch (e) {
      print('❌ 错误: $e');
      print('${StackTrace.current}');
    }
  });
}
