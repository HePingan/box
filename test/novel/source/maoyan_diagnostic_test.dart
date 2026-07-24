// 端到端诊断：真实 API 调用测试
// 运行: flutter test test/novel/source/maoyan_diagnostic_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() {
  test('diagnostic: test real API endpoints with debug output', () async {
    // ─── 1. 加载内置书源 JSON ───
    // assets 目录对于 flutter test 不可直接访问, 改用原始 JSON 字符串
    final file = File('assets/data/maoyan_book_source.json');
    final jsonStr = await file.readAsString();
    final bookSource = jsonDecode(jsonStr) as Map<String, dynamic>;
    final comment = '${bookSource['bookSourceComment'] ?? ''}';

    print('═══════════════════════════════════════════');
    print('书源: ${bookSource['bookSourceName']}');
    print('═══════════════════════════════════════════');
    print('评论长度: ${comment.length} chars');

    // ─── 2. 提取认证信息 ───
    final domains = <(String, int)>[];
    final aesKeys = <String>[];
    final authTokens = <String>[];

    // 匹配 ["domain_name", digit] 格式 — 域名只用 base name，不加 .com
    final domainRegex = RegExp(r'\["([a-z]+)",\s*(\d)\]');
    for (final m in domainRegex.allMatches(comment)) {
      domains.add((m.group(1)!, int.parse(m.group(2)!)));
      if (domains.length <= 3) {
        print('  域名匹配: "${m.group(1)}" type=${m.group(2)}');
      }
    }

    final authRegex = RegExp(r'\["([a-f0-9]+)",\s*"([^"]+)"\]');
    for (final m in authRegex.allMatches(comment)) {
      aesKeys.add(m.group(1)!);
      var token = m.group(2)!;
      if (!token.toLowerCase().startsWith('bearer')) {
        token = 'Bearer $token';
      } else {
        token = 'Bearer ${token.substring(6)}';
      }
      authTokens.add(token.trim());
    }

    print('\n域名数: ${domains.length}');
    for (int i = 0; i < domains.length && i < 3; i++) {
      print('  ${domains[i].$1} (type=${domains[i].$2})');
    }
    if (domains.length > 3) print('  ...还有${domains.length - 3}个');
    print('AES Key 组数: ${aesKeys.length}');
    print('Auth Token 组数: ${authTokens.length}');

    final testDomain = domains.first;
    print('\n测试域名: api.${testDomain.$1}.com (type=${testDomain.$2})');
    final uType = testDomain.$2;
    final clientDevice = md5.convert(utf8.encode(aesKeys[uType])).toString();
    final authToken = authTokens[uType];
    final baseHeaders = {
      'User-Agent': 'okhttp/4.9.2',
      'client-device': clientDevice,
      'Authorization': authToken,
    };
    print('client-device: $clientDevice');
    print('Authorization: $authToken');
    print('');

    // ─── 3. 测试搜索 API ───
    print('─── 测试搜索 API ───');
    const kw = '大奉打更人';
    final searchPath = '/search?keyword=${Uri.encodeComponent(kw)}&page=1';
    var success = false;
    String? responseBody;

    for (final scheme in ['http', 'https']) {
      for (final (domain, _) in domains) {
        final url = '$scheme://api.$domain.com$searchPath';
        print('尝试: $url');
        try {
          final resp = await http.Client()
              .get(Uri.parse(url), headers: baseHeaders)
              .timeout(const Duration(seconds: 10));
          print('  -> HTTP ${resp.statusCode} (${resp.body.length} bytes)');
          if (resp.statusCode == 200) {
            responseBody = resp.body;
            success = true;
            break;
          }
          // 打印部分响应
          final snippet = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
          print('  -> Body: $snippet');
        } catch (e) {
          print('  -> ERROR: $e');
        }
      }
      if (success) break;
    }

    if (!success || responseBody == null) {
      print('❌ 搜索 API 全部失败');
      return;
    }

    // 解析搜索结果
    final searchData = jsonDecode(responseBody);
    print('搜索响应类型: ${searchData.runtimeType}');
    print('搜索响应键: ${searchData is Map ? searchData.keys.join(", ") : "is List"}');

    // 找 data 字段
    dynamic searchResult = searchData;
    if (searchData is Map && searchData.containsKey('data')) {
      searchResult = searchData['data'];
      print('searchData["data"] 类型: ${searchResult.runtimeType}');
    }

    if (searchResult is! List || searchResult.isEmpty) {
      print('❌ 搜索结果为空或格式异常');
      return;
    }

    print('搜索结果数量: ${searchResult.length}');
    final firstBook = searchResult[0] as Map;
    final novelId = firstBook['novelId'] ?? firstBook['novel_id'] ?? firstBook['bookId'] ?? firstBook['id'];
    final novelName = firstBook['novelName'] ?? firstBook['novel_name'] ?? firstBook['bookName'] ?? firstBook['name'];
    print('第一本书 novelId: $novelId');
    print('第一本书名称: $novelName');
    print('第一本书的所有键: ${firstBook.keys.join(", ")}');

    // ─── 3.5 解析 header 字段 ───
    print('\n─── 解析 header 字段 ───');
    final rawHeader = bookSource['header'];
    print('header 原始类型: ${rawHeader.runtimeType}');
    print('header 原始值: $rawHeader');
    Map<String, String> parsedHeaders = {'User-Agent': 'okhttp/4.9.2'};
    if (rawHeader is String) {
      try {
        final hMap = jsonDecode(rawHeader) as Map;
        for (final e in hMap.entries) {
          parsedHeaders['${e.key}'] = '${e.value}'.trim();
        }
        print('解析后的 headers:');
        parsedHeaders.forEach((k, v) => print('  $k: $v'));
      } catch (e) {
        print('header 解析失败: $e');
      }
    }
    // 添加认证头
    parsedHeaders['client-device'] = clientDevice;
    parsedHeaders['Authorization'] = authToken;
    print('最终请求头:');
    parsedHeaders.forEach((k, v) => print('  $k: $v'));

    print('');

    // ─── 4. 测试详情 API ───
    print('─── 测试详情 API（所有域名）───');
    final detailPath = '/novel/$novelId';
    success = false;
    String? detailBody;

    for (final scheme in ['http', 'https']) {
      for (final (domain, _) in domains) {
        final url = '$scheme://api.$domain.com$detailPath';
        print('尝试: $url');
        try {
          final resp = await http.Client()
              .get(Uri.parse(url), headers: parsedHeaders)
              .timeout(const Duration(seconds: 10));
          final snippet = resp.body.length > 300 ? '${resp.body.substring(0, 300)}...' : resp.body;
          print('  -> HTTP ${resp.statusCode} (${resp.body.length} bytes): $snippet');
          if (resp.statusCode == 200) {
            detailBody = resp.body;
            success = true;
            break;
          }
        } catch (e) {
          print('  -> ERROR: $e');
        }
      }
      if (success) break;
    }

    if (!success || detailBody == null) {
      print('❌ 详情 API 全部失败');
      return;
    }

    final detailData = jsonDecode(detailBody);
    print('\n详情响应类型: ${detailData.runtimeType}');
    print('详情响应键: ${detailData is Map ? detailData.keys.join(", ") : "is List"}');

    // 检查 data 字段
    dynamic detailInfo = detailData;
    String? detailNovelId;
    if (detailData is Map) {
      if (detailData.containsKey('data') && detailData['data'] is Map) {
        detailInfo = detailData['data'];
        print('详情 data 字段键: ${(detailInfo as Map).keys.join(", ")}');
        detailNovelId = '${detailInfo['novelId'] ?? detailInfo['novel_id'] ?? detailInfo['bookId'] ?? detailInfo['id'] ?? ''}';
      } else {
        detailNovelId = '${detailData['novelId'] ?? detailData['novel_id'] ?? detailData['bookId'] ?? detailData['id'] ?? ''}';
      }
    }
    print('详情 API novelId: "$detailNovelId"');
    print('搜索 API novelId: "$novelId"');
    print('两者相同: ${detailNovelId == "$novelId"}');

    // 打印详情完整响应（精简）
    final detailSnippet = detailBody.length > 500 ? '${detailBody.substring(0, 500)}...' : detailBody;
    print('详情响应体预览: $detailSnippet');
    print('');

    // ─── 5. 测试章节 API ───
    print('─── 测试章节 API ───');
    // 用详情 API 返回的 novelId
    final effectiveNovelId = detailNovelId != null && detailNovelId.isNotEmpty && detailNovelId != 'null'
        ? detailNovelId
        : '$novelId';
    print('用于章节接口的 novelId: "$effectiveNovelId"');

    final chapterPaths = [
      '/novel/$effectiveNovelId/chapters',
      '/novel/$effectiveNovelId/toc',
      '/novel/$effectiveNovelId/chapterList',
      '/book/$effectiveNovelId/chapters',
    ];

    for (final path in chapterPaths) {
      print('\n尝试路径: $path');
      for (final scheme in ['http', 'https']) {
        for (final (domain, _) in domains.take(3)) {
          final url = '$scheme://api.$domain.com$path';
          try {
            final resp = await http.Client()
                .get(Uri.parse(url), headers: parsedHeaders)
                .timeout(const Duration(seconds: 10));
            if (resp.statusCode == 200) {
              print('  ✅ $scheme://api.$domain.com$path -> HTTP 200 (${resp.body.length} bytes)');
              final snippet = resp.body.length > 500 ? '${resp.body.substring(0, 500)}...' : resp.body;
              print('  响应: $snippet');

              // 尝试解析 JSON
              try {
                final parsed = jsonDecode(resp.body);
                print('  JSON 类型: ${parsed.runtimeType}');
                if (parsed is Map) {
                  print('  键: ${parsed.keys.join(", ")}');
                  for (final k in parsed.keys) {
                    final v = parsed[k];
                    if (v is List) {
                      print('  $k: List(${v.length})');
                    } else {
                      print('  $k: ${v.runtimeType} = ${v.toString().substring(0, v.toString().length > 80 ? 80 : v.toString().length)}');
                    }
                  }
                } else if (parsed is List) {
                  print('  数组长度: ${parsed.length}');
                  if (parsed.isNotEmpty) {
                    final first = parsed[0];
                    if (first is Map) print('  第一项键: ${first.keys.join(", ")}');
                  }
                }
              } catch (_) {
                print('  不是有效 JSON');
              }

              success = true;
              break;
            } else {
              print('  ❌ $scheme://api.$domain.com$path -> HTTP ${resp.statusCode}');
              final snippet = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
              print('  响应: $snippet');
            }
          } catch (e) {
            print('  ❌ $scheme://api.$domain.com$path -> ERROR: $e');
          }
        }
        if (success) break;
      }
      if (success) break;
    }

    if (!success) {
      print('\n❌ 所有章节路径均失败');
    }

    print('\n══════════ 诊断完成 ══════════');
  });
}
