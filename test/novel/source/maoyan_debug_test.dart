// 精确诊断：MaoYanNovelSource fetchDetail 章节提取追踪
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../../../lib/novel/core/maoyan_novel_source.dart';
import '../../../lib/novel/core/models.dart';

void main() {
  test('MaoYan 端到端诊断：search → fetchDetail 章节提取', () async {
    final file = File('assets/data/maoyan_book_source.json');
    final jsonStr = await file.readAsString();
    final bookSource = jsonDecode(jsonStr) as Map<String, dynamic>;
    final source = MaoYanNovelSource.fromBookSourceJson(bookSource);

    // Step 1: 搜索
    final kw = '大奉打更人';
    print('=== Step 1: 搜索 "$kw" ===');
    final books = await source.searchBooks(kw);
    print('搜索结果: ${books.length} 本');
    if (books.isEmpty) {
      print('❌ 搜索无结果，终止');
      return;
    }
    final book = books.first;
    print('第一本书: id=${book.id}, title=${book.title}, author=${book.author}');
    print('detailUrl: ${book.detailUrl}');

    // Step 2: fetchDetail
    print('\n=== Step 2: fetchDetail ===');
    NovelDetail detail;
    try {
      detail = await source.fetchDetail(
        bookId: book.id,
        detailUrl: book.detailUrl,
      );
      print('✅ fetchDetail 成功');
    } catch (e) {
      print('❌ fetchDetail 失败: $e');
      return;
    }

    print('书籍: ${detail.book.title}');
    print('章节数量: ${detail.chapters.length}');

    if (detail.chapters.isEmpty) {
      print('\n⚠️ 章节为空！深入诊断...');

      // 直接测试详情 API 原始响应
      print('\n=== Step 3: 直接调用详情 API ===');
      // 从 source 中获取 domains 和 headers
      final comment = '${bookSource['bookSourceComment'] ?? ''}';
      final extracted = MaoYanNovelSource.extractAuthFromComment(comment);
      final domains = extracted.$1;
      final aesKeys = extracted.$2;
      final authTokens = extracted.$3;

      // 从 header 解析原始 headers
      final baseHeaders = <String, String>{
        'User-Agent': 'okhttp/4.9.2',
      };
      final rawHeader = bookSource['header'] as String?;
      if (rawHeader != null) {
        try {
          final hMap = jsonDecode(rawHeader) as Map;
          for (final e in hMap.entries) {
            baseHeaders['${e.key}'] = '${e.value}'.trim();
          }
        } catch (_) {}
      }

      // 直接从第一个域名请求详情
      final (domain, uType) = domains.first;
      final clientDevice = md5.convert(utf8.encode(aesKeys[uType])).toString();
      final authHeader = authTokens[uType];
      final mergedHeaders = Map<String, String>.from(baseHeaders);
      mergedHeaders['client-device'] = clientDevice;
      mergedHeaders['Authorization'] = authHeader;

      final detailPath = '/novel/${book.id}';
      final urls = [
        'http://api.$domain.com$detailPath',
        'https://api.$domain.com$detailPath',
      ];

      Map<String, dynamic>? detailData;
      for (final url in urls) {
        print('尝试: $url');
        try {
          final resp = await http.Client()
              .get(Uri.parse(url), headers: mergedHeaders)
              .timeout(const Duration(seconds: 15));
          print('  HTTP ${resp.statusCode} (${resp.body.length} bytes)');
          if (resp.statusCode == 200) {
            final json = jsonDecode(resp.body);
            print('  响应顶层 keys: ${(json is Map ? json.keys.toList() : [])}');

            if (json is Map) {
              // 获取 data 字段
              final data = json['data'];
              if (data is Map) {
                print('  data 字段 keys: ${data.keys.toList()}');
                detailData = Map<String, dynamic>.from(data);

                // 检查是否有 list
                if (data.containsKey('list')) {
                  final list = data['list'];
                  print('  data.list 类型: ${list.runtimeType}');
                  if (list is List) {
                    print('  data.list 长度: ${list.length}');
                    if (list.isNotEmpty && list.first is Map) {
                      final first = list.first as Map;
                      print('  第一个元素 keys: ${first.keys.toList()}');
                      print('  chapterName: ${first['chapterName']}');
                      print('  path: ${first['path']?.toString().substring(0, 50)}');
                    }
                  }
                } else {
                  print('  ⚠️ data 中无 list 字段!');
                  // 搜索所有 List 类型的字段
                  for (final e in data.entries) {
                    if (e.value is List) {
                      print('  data.${e.key} 是 List，长度=${(e.value as List).length}');
                    }
                  }
                }
              } else {
                print('  data 字段不是 Map，类型: ${data.runtimeType}');
                // 搜索所有顶层 List
                for (final e in json.entries) {
                  if (e.value is List) {
                    print('  顶层.${e.key} 是 List，长度=${(e.value as List).length}');
                  }
                }
              }
            }
            break; // 成功就退出
          }
        } catch (e) {
          print('  失败: $e');
        }
      }

      // 如果找到了 detailData，尝试从中提取章节
      if (detailData != null) {
        print('\n=== Step 4: 手动从 detailData 提取章节 ===');
        // 用 _buildChaptersFromList 相同的逻辑
        for (final key in detailData.keys) {
          final val = detailData[key];
          if (val is List) {
            print('  data.$key 是数组 (${val.length}项)');
            if (val.isNotEmpty && val.first is Map) {
              print('  首项 fields: ${(val.first as Map).keys}');
            }
          }
        }

        // 特别关注 list 字段
        final list = detailData['list'];
        if (list is List) {
          print('\n  从 list 构建章节:');
          var successCount = 0;
          for (final item in list) {
            if (item is Map) {
              final name = item['chapterName'] ?? item['name'] ?? item['title'] ?? '(无)';
              final path = item['path'] ?? item['url'] ?? '(无)';
              if (name is String && name.isNotEmpty && path is String && path.isNotEmpty) {
                successCount++;
                if (successCount <= 3) {
                  print('    第$successCount章: name=$name, path=${path.substring(0, 50)}...');
                }
              }
            }
          }
          print('  可构建章节: $successCount / ${list.length}');
          if (successCount == 0) {
            // 字段名可能不同，打印所有字段
            if (list.isNotEmpty && list.first is Map) {
              print('  实际字段: ${(list.first as Map).keys.toList()}');
            }
          }
        }
      }

      // Step 5: 测试 _fetchChapters 路径
      print('\n=== Step 5: 直接测试独立章节 API ===');
      final paths = [
        '/novel/${book.id}/chapters',
        '/novel/${book.id}/toc',
        '/novel/${book.id}/chapterList',
        '/book/${book.id}/chapters',
      ];
      for (final path in paths) {
        for (final proto in ['http', 'https']) {
          final url = '$proto://api.$domain.com$path';
          try {
            final resp = await http.Client()
                .get(Uri.parse(url), headers: mergedHeaders)
                .timeout(const Duration(seconds: 10));
            if (resp.statusCode == 200) {
              print('✅ $url → 200 (${resp.body.length} bytes)');
              if (resp.body.length > 100) {
                final json = jsonDecode(resp.body);
                if (json is Map) {
                  print('  keys: ${json.keys.toList()}');
                  for (final e in json.entries) {
                    if (e.value is List) {
                      print('  ${e.key} 是数组: ${(e.value as List).length}项');
                    }
                  }
                } else if (json is List) {
                  print('  直接是数组: ${json.length}项');
                }
              }
            } else {
              print('❌ $url → ${resp.statusCode}');
            }
          } catch (e) {
            print('❌ $url → $e');
          }
        }
      }
    } else {
      print('✅ 章节列表中有 ${detail.chapters.length} 章');
      print('第一章: ${detail.chapters.first.title}');
    }
  });
}
